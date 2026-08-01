use std::fs::File;
use std::io::{BufWriter, Write};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use platform_desktop::DesktopPlatform;
use volward_core::classify::Classifier;
use volward_core::delete::DeleteOrchestrator;
use volward_core::model::{
    DeleteReport, PlatformCapabilities, ScanProgress, StorageSnapshot, TrashEmptyReport,
};
use volward_core::rules::DesktopRules;
use volward_core::scan::ScanOrchestrator;
use volward_core::PlatformStorage;
use volward_core::SnapshotCatalog;
use volward_core::SnapshotIndex;

use crate::proto;

fn load_classifier(platform: &DesktopPlatform) -> Classifier {
    let path = std::env::var("VOLWARD_RULES_PATH")
        .ok()
        .map(PathBuf::from)
        .or_else(|| {
            let p = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../rules/desktop.yaml");
            p.exists().then_some(p)
        });

    if let Some(path) = path {
        if let Ok(yaml) = std::fs::read_to_string(&path) {
            if let Ok(rules) = DesktopRules::parse_yaml(&yaml) {
                return Classifier::from_rules(&rules, platform.protected_prefixes());
            }
        }
    }
    Classifier::new(platform.protected_prefixes().to_vec())
}

fn load_classifier_from_arc(platform: &Arc<DesktopPlatform>) -> Classifier {
    load_classifier(platform.as_ref())
}

pub struct VolwardEngine {
    platform: Arc<DesktopPlatform>,
    cancel: Arc<AtomicBool>,
    is_scanning: Arc<AtomicBool>,
    last_snapshot: Arc<Mutex<Option<StorageSnapshot>>>,
    /// Authoritative path-keyed index rebuilt whenever a new snapshot is set.
    /// Dart queries this via FFI instead of hydrating the full snapshot.
    last_index: Arc<Mutex<Option<SnapshotIndex>>>,
    /// Monotonic version counter — incremented each time last_index is rebuilt.
    index_version: Arc<std::sync::atomic::AtomicU64>,
    last_progress: Arc<Mutex<Option<ScanProgress>>>,
    last_checkpoint: Arc<Mutex<Option<StorageSnapshot>>>,
    _scan_handle: Arc<Mutex<Option<std::thread::JoinHandle<()>>>>,
}

impl Default for VolwardEngine {
    fn default() -> Self {
        Self::new()
    }
}

impl VolwardEngine {
    pub fn new() -> Self {
        Self {
            platform: Arc::new(DesktopPlatform::new()),
            cancel: Arc::new(AtomicBool::new(false)),
            is_scanning: Arc::new(AtomicBool::new(false)),
            last_snapshot: Arc::new(Mutex::new(None)),
            last_index: Arc::new(Mutex::new(None)),
            index_version: Arc::new(std::sync::atomic::AtomicU64::new(0)),
            last_progress: Arc::new(Mutex::new(None)),
            last_checkpoint: Arc::new(Mutex::new(None)),
            _scan_handle: Arc::new(Mutex::new(None)),
        }
    }

    pub fn probe_capabilities(&self) -> PlatformCapabilities {
        self.platform.probe_capabilities()
    }

    pub fn is_deep_scan_ready(&self) -> bool {
        self.platform.is_deep_scan_ready()
    }

    pub fn open_permission_settings(&self) -> Result<(), String> {
        self.platform
            .open_permission_settings()
            .map_err(|e| e.to_string())
    }

    pub fn set_last_snapshot(&self, snapshot: StorageSnapshot) {
        // Rebuild the path-keyed index atomically alongside the snapshot so
        // Dart can query it immediately without a separate hydration call.
        let version = self.index_version.fetch_add(1, Ordering::Relaxed) + 1;
        let index = SnapshotIndex::from_snapshot_with_version(&snapshot, version);
        if let Ok(mut g) = self.last_index.lock() {
            *g = Some(index);
        }
        if let Ok(mut g) = self.last_snapshot.lock() {
            *g = Some(snapshot);
        }
    }

    /// Current catalog version — Dart uses this as `SnapshotQueryKey.version`
    /// so cache invalidation is aligned with the Rust index.
    pub fn index_version(&self) -> u64 {
        self.index_version.load(Ordering::Relaxed)
    }

    // ------------------------------------------------------------------
    // Catalog index queries (Design §5.3 — Dart calls these over FFI)
    // ------------------------------------------------------------------

    /// Query direct children of `path` with optional filter/sort.
    /// Pure in-memory — no file-system scan triggered.
    pub fn query_directory_json(
        &self,
        path: &str,
        category_filter: Option<&str>,
        deletable_only: bool,
        sort_mode: &str,
    ) -> Result<String, String> {
        let guard = self.last_index.lock().map_err(|e| format!("lock: {e}"))?;
        let index = guard
            .as_ref()
            .ok_or_else(|| "error:no index loaded".to_string())?;
        index.query_directory_json(path, category_filter, deletable_only, sort_mode)
    }

    /// Re-query the existing index for `path` — pure in-memory, no scan.
    /// This is the implementation of Design §7.2 "current directory refresh".
    pub fn refresh_directory(&self, path: &str) -> Result<String, String> {
        let guard = self.last_index.lock().map_err(|e| format!("lock: {e}"))?;
        let index = guard
            .as_ref()
            .ok_or_else(|| "error:no index loaded".to_string())?;
        index.refresh_directory_json(path)
    }

    /// Load a persisted index file into the engine.
    /// On success the in-memory index is replaced and the version counter bumped.
    pub fn load_index_from_path(&self, path: &str) -> Result<(), String> {
        let file = File::open(path).map_err(|e| format!("error:open index: {e}"))?;
        let index = match serde_json::from_reader::<_, SnapshotIndex>(file) {
            Ok(index) => index,
            Err(index_error) => {
                let file = File::open(path).map_err(|e| format!("error:open snapshot: {e}"))?;
                serde_json::from_reader::<_, StorageSnapshot>(file)
                    .map(|snapshot| SnapshotIndex::from(&snapshot))
                    .map_err(|snapshot_error| {
                        format!("error:parse index: {index_error}; snapshot: {snapshot_error}")
                    })?
            }
        };
        self.index_version.store(index.version, Ordering::Relaxed);
        if let Ok(mut g) = self.last_index.lock() {
            *g = Some(index);
        }
        if let Ok(mut g) = self.last_snapshot.lock() {
            *g = None;
        }
        Ok(())
    }

    pub fn get_index_summary_json(&self) -> Result<String, String> {
        let guard = self.last_index.lock().map_err(|e| format!("lock: {e}"))?;
        let index = guard
            .as_ref()
            .ok_or_else(|| "error:no index loaded".to_string())?;
        index.summary_json()
    }

    /// Persist the current index (as a snapshot JSON) to `path`.
    /// Returns the snapshot_id on success.
    pub fn write_last_index_to_path(&self, path: &str) -> Result<String, String> {
        {
            let guard = self.last_index.lock().map_err(|e| format!("lock: {e}"))?;
            if let Some(index) = guard.as_ref() {
                let file = File::create(path).map_err(|e| format!("error:create index: {e}"))?;
                let mut writer = BufWriter::new(file);
                serde_json::to_writer(&mut writer, index)
                    .map_err(|e| format!("error:serialize index: {e}"))?;
                writer
                    .flush()
                    .map_err(|e| format!("error:flush index: {e}"))?;
                return Ok(index.snapshot_id.clone());
            }
        }

        let snapshot_guard = self
            .last_snapshot
            .lock()
            .map_err(|e| format!("lock snapshot: {e}"))?;
        let snapshot = snapshot_guard
            .as_ref()
            .ok_or_else(|| "error:no index".to_string())?;
        let index = SnapshotIndex::from(snapshot);
        let file = File::create(path).map_err(|e| format!("error:create index: {e}"))?;
        let mut writer = BufWriter::new(file);
        serde_json::to_writer(&mut writer, &index)
            .map_err(|e| format!("error:serialize index: {e}"))?;
        writer
            .flush()
            .map_err(|e| format!("error:flush index: {e}"))?;
        Ok(index.snapshot_id)
    }

    pub fn is_scan_running(&self) -> bool {
        self.is_scanning.load(Ordering::Relaxed)
    }

    pub fn start_scan(&self, job_id: String, roots: Vec<String>, incremental: bool) -> String {
        // Reject if a scan is already in progress (defense-in-depth —
        // Dart callers use start_scan_async, but blocking path is also
        // exposed through C FFI).
        if self
            .is_scanning
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::Relaxed)
            .is_err()
        {
            return "error:scan already in progress".to_string();
        }

        self.cancel.store(false, Ordering::Relaxed);
        let classifier = load_classifier(self.platform.as_ref());
        let orchestrator = ScanOrchestrator::new(self.platform.as_ref(), classifier);
        let cancel = self.cancel.clone();
        let last_snapshot = self.last_snapshot.clone();
        let last_progress = self.last_progress.clone();

        let result = orchestrator.run_scan(
            job_id,
            roots,
            incremental,
            &cancel,
            |progress| {
                if let Ok(mut g) = last_progress.lock() {
                    *g = Some(progress);
                }
            },
            |_checkpoint| {},
        );

        self.is_scanning.store(false, Ordering::Relaxed);

        match result {
            Ok(snapshot) => {
                let id = snapshot.snapshot_id.clone();
                if let Ok(mut g) = last_snapshot.lock() {
                    *g = Some(snapshot);
                }
                id
            }
            Err(e) => format!("error:{e}"),
        }
    }

    pub fn start_scan_async(
        &self,
        job_id: String,
        roots: Vec<String>,
        incremental: bool,
    ) -> String {
        // Reject if a scan is already in progress.
        if self
            .is_scanning
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::Relaxed)
            .is_err()
        {
            return "error:scan already in progress".to_string();
        }

        // Clear any prior cancel request so a new async scan is not aborted
        // immediately when the shared main engine is reused after cancel.
        self.cancel.store(false, Ordering::Relaxed);

        let platform = self.platform.clone();
        let cancel = self.cancel.clone();
        let last_snapshot = self.last_snapshot.clone();
        let last_index = self.last_index.clone();
        let last_progress = self.last_progress.clone();
        let last_checkpoint = self.last_checkpoint.clone();
        let is_scanning = self.is_scanning.clone();
        let index_version = self.index_version.clone();
        let scan_handle = self._scan_handle.clone();

        let job_id_clone = job_id.clone();

        let handle = std::thread::spawn(move || {
            let classifier = load_classifier_from_arc(&platform);
            let orchestrator = ScanOrchestrator::new(platform.as_ref(), classifier);
            match orchestrator.run_index_scan(
                job_id_clone,
                roots,
                incremental,
                &cancel,
                |progress| {
                    if let Ok(mut g) = last_progress.lock() {
                        *g = Some(progress);
                    }
                },
            ) {
                Ok(mut index) => {
                    // A cancelled walk returns a truncated catalog. Keep any prior
                    // good index so Dart (which still shows the previous snapshot)
                    // does not suddenly query/delete against partial results.
                    if index.scan_state == "Cancelled" {
                        // leave last_index / last_snapshot unchanged
                    } else {
                        let version = index_version.fetch_add(1, Ordering::Relaxed) + 1;
                        index.version = version;
                        if let Ok(mut g) = last_index.lock() {
                            *g = Some(index);
                        }
                        if let Ok(mut g) = last_snapshot.lock() {
                            *g = None;
                        }
                        if let Ok(mut g) = last_checkpoint.lock() {
                            *g = None;
                        }
                    }
                }
                Err(_e) => {
                    // snapshot stays None; caller should check via get_last_snapshot
                }
            }
            is_scanning.store(false, Ordering::Relaxed);
        });

        if let Ok(mut g) = scan_handle.lock() {
            *g = Some(handle);
        }

        job_id
    }

    pub fn cancel_scan(&self) {
        self.cancel.store(true, Ordering::Relaxed);
    }

    pub fn get_last_snapshot(&self) -> Option<StorageSnapshot> {
        self.last_snapshot.lock().ok().and_then(|g| g.clone())
    }

    pub fn get_last_progress(&self) -> Option<ScanProgress> {
        self.last_progress.lock().ok().and_then(|g| g.clone())
    }

    pub fn delete_entries(
        &self,
        snapshot_id: &str,
        entry_ids: Vec<String>,
        dry_run: bool,
    ) -> Result<DeleteReport, String> {
        {
            let guard = self.last_index.lock().map_err(|e| format!("lock: {e}"))?;
            if let Some(index) = guard.as_ref() {
                if index.snapshot_id != snapshot_id {
                    return Err("Snapshot expired or mismatch".to_string());
                }
                let entries = index.deletable_entries_for_ids(&entry_ids);
                return DeleteOrchestrator::delete_index_entries(
                    &index.snapshot_id,
                    &entries,
                    dry_run,
                    &*self.platform,
                )
                .map_err(|e| e.to_string());
            }
        }

        let snapshot = self
            .get_last_snapshot()
            .ok_or_else(|| "No snapshot loaded".to_string())?;
        if snapshot.snapshot_id != snapshot_id {
            return Err("Snapshot expired or mismatch".to_string());
        }
        DeleteOrchestrator::delete_entries(&snapshot, &entry_ids, dry_run, &*self.platform)
            .map_err(|e| e.to_string())
    }

    pub fn empty_trash(&self) -> Result<TrashEmptyReport, String> {
        DeleteOrchestrator::empty_trash(&*self.platform).map_err(|e| e.to_string())
    }

    pub fn probe_capabilities_json(&self) -> String {
        serde_json::to_string(&self.probe_capabilities()).unwrap_or_else(|_| "{}".to_string())
    }

    pub fn get_last_snapshot_json(&self) -> Option<String> {
        self.get_last_snapshot()
            .and_then(|s| serde_json::to_string(&s).ok())
    }

    pub fn get_last_snapshot_catalog_json(&self) -> Option<String> {
        self.get_last_snapshot()
            .and_then(|s| serde_json::to_string(&SnapshotCatalog::from(&s)).ok())
    }

    pub fn get_last_progress_json(&self) -> Option<String> {
        self.get_last_progress()
            .and_then(|p| serde_json::to_string(&p).ok())
    }

    pub fn get_last_checkpoint(&self) -> Option<StorageSnapshot> {
        self.last_checkpoint.lock().ok().and_then(|g| g.clone())
    }

    /// Serializes the last checkpoint directly to `path`. Returns
    /// `error:no checkpoint` if the current scan hasn't produced one yet.
    pub fn write_last_checkpoint_to_path(&self, path: &str) -> Result<String, String> {
        let guard = self
            .last_checkpoint
            .lock()
            .map_err(|e| format!("lock checkpoint: {e}"))?;
        let snapshot = guard
            .as_ref()
            .ok_or_else(|| "error:no checkpoint".to_string())?;
        let file = File::create(path).map_err(|e| format!("error:create checkpoint: {e}"))?;
        let mut writer = BufWriter::new(file);
        serde_json::to_writer(&mut writer, snapshot)
            .map_err(|e| format!("error:serialize checkpoint: {e}"))?;
        writer
            .flush()
            .map_err(|e| format!("error:flush checkpoint: {e}"))?;
        Ok(snapshot.snapshot_id.clone())
    }

    /// Encodes the last checkpoint as protobuf and writes it atomically to
    /// `path` (temp file + rename), so a concurrent reader never observes a
    /// truncated file. Returns `error:no checkpoint` if none exists yet.
    pub fn write_last_checkpoint_to_path_pb(&self, path: &str) -> Result<String, String> {
        let guard = self
            .last_checkpoint
            .lock()
            .map_err(|e| format!("lock checkpoint: {e}"))?;
        let snapshot = guard
            .as_ref()
            .ok_or_else(|| "error:no checkpoint".to_string())?;
        let id = snapshot.snapshot_id.clone();
        write_snapshot_pb_atomic(snapshot, path)?;
        Ok(id)
    }

    /// Single-level, non-recursive directory listing (see
    /// `PlatformStorage::quick_list_dir`). Safe to call while a scan is
    /// running — it does not touch `is_scanning`/shared scan state.
    pub fn quick_list_dir_json(&self, path: &str) -> String {
        match self.platform.quick_list_dir(path) {
            Ok(entries) => serde_json::to_string(&entries).unwrap_or_else(|_| "[]".to_string()),
            Err(e) => serde_json::json!({ "error": e.to_string() }).to_string(),
        }
    }

    pub fn set_last_snapshot_json(&self, json: &str) -> Result<(), String> {
        let snapshot: StorageSnapshot =
            serde_json::from_str(json).map_err(|e| format!("invalid snapshot json: {e}"))?;
        self.set_last_snapshot(snapshot);
        Ok(())
    }

    /// Serializes the last snapshot directly to [path] without an intermediate Dart copy.
    /// Returns the snapshot_id on success, or `error:…` on failure.
    pub fn write_last_snapshot_to_path(&self, path: &str) -> Result<String, String> {
        let guard = self
            .last_snapshot
            .lock()
            .map_err(|e| format!("lock snapshot: {e}"))?;
        let snapshot = guard
            .as_ref()
            .ok_or_else(|| "error:no snapshot".to_string())?;
        let file = File::create(path).map_err(|e| format!("error:create snapshot: {e}"))?;
        let mut writer = BufWriter::new(file);
        serde_json::to_writer(&mut writer, snapshot)
            .map_err(|e| format!("error:serialize snapshot: {e}"))?;
        writer
            .flush()
            .map_err(|e| format!("error:flush snapshot: {e}"))?;
        Ok(snapshot.snapshot_id.clone())
    }

    pub fn write_last_snapshot_catalog_to_path(&self, path: &str) -> Result<String, String> {
        let guard = self
            .last_snapshot
            .lock()
            .map_err(|e| format!("lock snapshot: {e}"))?;
        let snapshot = guard
            .as_ref()
            .ok_or_else(|| "error:no snapshot".to_string())?;
        let catalog = SnapshotCatalog::from(snapshot);
        let file = File::create(path).map_err(|e| format!("error:create catalog: {e}"))?;
        let mut writer = BufWriter::new(file);
        serde_json::to_writer(&mut writer, &catalog)
            .map_err(|e| format!("error:serialize catalog: {e}"))?;
        writer
            .flush()
            .map_err(|e| format!("error:flush catalog: {e}"))?;
        Ok(catalog.snapshot_id)
    }

    pub fn load_snapshot_catalog_from_path(&self, path: &str) -> Result<String, String> {
        let json = std::fs::read_to_string(path).map_err(|e| format!("read catalog: {e}"))?;
        let catalog: SnapshotCatalog =
            serde_json::from_str(&json).map_err(|e| format!("invalid catalog json: {e}"))?;
        serde_json::to_string(&catalog).map_err(|e| format!("serialize catalog: {e}"))
    }

    /// Encodes the last snapshot as protobuf and writes it atomically to
    /// `path` (temp file + rename). Returns the snapshot_id on success.
    pub fn write_last_snapshot_to_path_pb(&self, path: &str) -> Result<String, String> {
        let guard = self
            .last_snapshot
            .lock()
            .map_err(|e| format!("lock snapshot: {e}"))?;
        let snapshot = guard
            .as_ref()
            .ok_or_else(|| "error:no snapshot".to_string())?;
        let id = snapshot.snapshot_id.clone();
        write_snapshot_pb_atomic(snapshot, path)?;
        Ok(id)
    }

    /// Loads snapshot from [path] into this engine (single parse, for delete operations).
    pub fn load_last_snapshot_from_path(&self, path: &str) -> Result<(), String> {
        let json = std::fs::read_to_string(path).map_err(|e| format!("read snapshot: {e}"))?;
        self.set_last_snapshot_json(&json)
    }

    pub fn delete_entries_json(
        &self,
        snapshot_id: &str,
        entry_ids: Vec<String>,
        dry_run: bool,
    ) -> String {
        match self.delete_entries(snapshot_id, entry_ids, dry_run) {
            Ok(report) => serde_json::to_string(&report).unwrap_or_else(|_| "{}".to_string()),
            Err(e) => serde_json::json!({ "error": e }).to_string(),
        }
    }
}

/// Encodes `snapshot` as protobuf and writes it atomically to `path`.
///
/// Writes to a sibling temp file (`<path>.tmp.<id>`) then renames onto `path`.
/// `rename` is atomic on the same filesystem, so a concurrent reader sees
/// either the previous file or the fully-written new one — never a truncated
/// stream. This removes the read-while-writing race the JSON path has.
fn write_snapshot_pb_atomic(snapshot: &StorageSnapshot, path: &str) -> Result<String, String> {
    use prost::Message;

    let msg = proto::StorageSnapshot::from(snapshot);
    let bytes = msg.encode_to_vec();

    let tmp = format!("{path}.tmp.{}", snapshot.snapshot_id);
    {
        let file = File::create(&tmp).map_err(|e| format!("error:create pb tmp: {e}"))?;
        let mut writer = BufWriter::new(file);
        writer
            .write_all(&bytes)
            .map_err(|e| format!("error:write pb: {e}"))?;
        writer.flush().map_err(|e| format!("error:flush pb: {e}"))?;
    }
    std::fs::rename(&tmp, path).map_err(|e| {
        // Best-effort cleanup so a failed rename doesn't leak temp files.
        let _ = std::fs::remove_file(&tmp);
        format!("error:rename pb: {e}")
    })?;
    Ok(snapshot.snapshot_id.clone())
}

#[cfg(test)]
mod tests {
    use super::*;
    use volward_core::model::{
        CapabilityLevel, EntryCategory, RiskLevel, ScanStats, ScanTreeNode, SourceType,
        StorageEntry, StorageSnapshot,
    };

    fn minimal_snapshot() -> StorageSnapshot {
        StorageSnapshot {
            snapshot_id: "test-snap".to_string(),
            scanned_at_ms: 1,
            capability: CapabilityLevel::FullPath,
            volume_total_bytes: 100,
            volume_used_bytes: 50,
            reclaimable_estimate_bytes: 10,
            entries: vec![StorageEntry {
                id: "e1".to_string(),
                display_name: "file".to_string(),
                path_or_uri: "/tmp/file".to_string(),
                size_bytes: 10,
                category: EntryCategory::Cache,
                risk_level: RiskLevel::Low,
                source_type: SourceType::File,
                deletable: true,
                reason: "test".to_string(),
            }],
            tree: ScanTreeNode {
                name: "root".to_string(),
                path: "/".to_string(),
                is_dir: true,
                size_bytes: 10,
                entry_id: None,
                children: vec![],
            },
            stats: ScanStats::default(),
            warnings: vec![],
        }
    }

    #[test]
    fn write_last_snapshot_roundtrip() {
        let engine = VolwardEngine::new();
        let snapshot = minimal_snapshot();
        let expected_id = snapshot.snapshot_id.clone();
        engine.set_last_snapshot(snapshot);

        let path = std::env::temp_dir().join(format!(
            "volward-write-snapshot-{}.json",
            std::process::id()
        ));
        let path_str = path.to_string_lossy();

        let id = engine
            .write_last_snapshot_to_path(&path_str)
            .expect("write should succeed");
        assert_eq!(id, expected_id);

        let engine2 = VolwardEngine::new();
        engine2
            .load_last_snapshot_from_path(&path_str)
            .expect("load should succeed");
        let loaded = engine2.get_last_snapshot().expect("snapshot loaded");
        assert_eq!(loaded.snapshot_id, expected_id);

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn checkpoint_starts_empty_and_quick_list_dir_reports_unsupported_error() {
        let engine = VolwardEngine::new();
        assert!(engine.get_last_checkpoint().is_none());

        // No real directory needed: an obviously-missing path exercises the
        // error path end-to-end through the JSON encoding.
        let json = engine.quick_list_dir_json("/definitely/does/not/exist/volward-test");
        assert!(json.contains("error"));
    }
}
