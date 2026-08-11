use std::fs::File;
use std::io::{BufWriter, Write};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use platform_desktop::DesktopPlatform;
use volward_core::classify::Classifier;
use volward_core::delete::DeleteOrchestrator;
use volward_core::model::{
    DeleteReport, PlatformCapabilities, ScanProgress, ScanTreeNode, StorageSnapshot,
    TrashEmptyReport,
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
    is_index_loading: Arc<AtomicBool>,
    last_index_load_error: Arc<Mutex<Option<String>>>,
    index_load_generation: Arc<std::sync::atomic::AtomicU64>,
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
            is_index_loading: Arc::new(AtomicBool::new(false)),
            last_index_load_error: Arc::new(Mutex::new(None)),
            index_load_generation: Arc::new(std::sync::atomic::AtomicU64::new(0)),
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

    /// Splices a freshly scanned subtree (from a peek/scoped scan) into the
    /// catalog index, replacing the directory at `target_path`, and bumps the
    /// index version so Dart-side caches invalidate.
    ///
    /// This is what makes a peek refresh visible to the UI when the index API
    /// is active: previously the peek result only updated the Dart overlay,
    /// while `query_directory` kept reading the stale catalog.
    pub fn replace_directory_with_subtree_json(
        &self,
        target_path: &str,
        subtree_json: &str,
    ) -> Result<u64, String> {
        #[derive(serde::Deserialize)]
        struct SubtreePayload {
            tree: volward_core::model::ScanTreeNode,
            #[serde(default)]
            entries: Vec<volward_core::model::StorageEntry>,
        }
        let payload: SubtreePayload =
            serde_json::from_str(subtree_json).map_err(|e| format!("error:parse subtree: {e}"))?;
        let mut guard = self.last_index.lock().map_err(|e| format!("lock: {e}"))?;
        let index = guard
            .as_mut()
            .ok_or_else(|| "error:no index loaded".to_string())?;
        let new_version =
            index.replace_directory_with_subtree(target_path, &payload.tree, &payload.entries)?;
        // Keep the engine-level version counter aligned with the index's own
        // version so Dart's catalogVersion sees the bump.
        self.index_version.store(new_version, Ordering::Relaxed);
        Ok(new_version)
    }

    /// Load a persisted index file into the engine.
    /// On success the in-memory index is replaced and the version counter bumped.
    pub fn load_index_from_path(&self, path: &str) -> Result<(), String> {
        self.invalidate_index_load();
        let index = Self::read_index_or_legacy_snapshot(path)?;
        self.set_loaded_index(index);
        Ok(())
    }

    fn read_index_or_legacy_snapshot(path: &str) -> Result<SnapshotIndex, String> {
        let file = File::open(path).map_err(|e| format!("error:open index: {e}"))?;
        Ok(match serde_json::from_reader::<_, SnapshotIndex>(file) {
            Ok(index) => index,
            Err(index_error) => {
                let file = File::open(path).map_err(|e| format!("error:open snapshot: {e}"))?;
                serde_json::from_reader::<_, StorageSnapshot>(file)
                    .map(|snapshot| SnapshotIndex::from(&snapshot))
                    .map_err(|snapshot_error| {
                        format!("error:parse index: {index_error}; snapshot: {snapshot_error}")
                    })?
            }
        })
    }

    fn set_loaded_index(&self, index: SnapshotIndex) {
        self.index_version.store(index.version, Ordering::Relaxed);
        if let Ok(mut g) = self.last_index.lock() {
            *g = Some(index);
        }
        if let Ok(mut g) = self.last_snapshot.lock() {
            *g = None;
        }
    }

    /// Load a persisted index/snapshot on a Rust worker thread so Flutter's
    /// main isolate remains responsive while large legacy caches are migrated.
    pub fn start_load_index_from_path_async(&self, path: String) -> String {
        if self
            .is_index_loading
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::Relaxed)
            .is_err()
        {
            return "busy:index load already in progress".to_string();
        }

        // Supersede any older async restore. The generation check below
        // prevents older workers from publishing their result after this call
        // starts; is_index_loading tracks the physical worker so Dart can avoid
        // running a scan concurrently with a still-parsing large cache file.
        let load_generation = self.index_load_generation.fetch_add(1, Ordering::SeqCst) + 1;
        if let Ok(mut g) = self.last_index_load_error.lock() {
            *g = None;
        }

        let last_index = self.last_index.clone();
        let last_snapshot = self.last_snapshot.clone();
        let index_version = self.index_version.clone();
        let is_index_loading = self.is_index_loading.clone();
        let last_index_load_error = self.last_index_load_error.clone();
        let index_load_generation = self.index_load_generation.clone();

        std::thread::spawn(move || {
            match Self::read_index_or_legacy_snapshot(&path) {
                Ok(index) => {
                    if index_load_generation.load(Ordering::SeqCst) == load_generation {
                        index_version.store(index.version, Ordering::Relaxed);
                        if let Ok(mut g) = last_index.lock() {
                            *g = Some(index);
                        }
                        if let Ok(mut g) = last_snapshot.lock() {
                            *g = None;
                        }
                    }
                }
                Err(error) => {
                    if index_load_generation.load(Ordering::SeqCst) == load_generation {
                        if let Ok(mut g) = last_index_load_error.lock() {
                            *g = Some(error);
                        }
                    }
                }
            }
            is_index_loading.store(false, Ordering::Release);
        });

        "ok".to_string()
    }

    pub fn invalidate_index_load(&self) {
        self.index_load_generation.fetch_add(1, Ordering::SeqCst);
        if let Ok(mut g) = self.last_index_load_error.lock() {
            *g = None;
        }
    }

    pub fn is_index_loading(&self) -> bool {
        self.is_index_loading.load(Ordering::Relaxed)
    }

    pub fn get_last_index_load_error(&self) -> Option<String> {
        self.last_index_load_error
            .lock()
            .ok()
            .and_then(|g| g.clone())
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

        self.invalidate_index_load();
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
        self.invalidate_index_load();
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
                let mut paths = Vec::new();
                for target in &entry_ids {
                    let resolved_entries = index.entries_for_ids(std::slice::from_ref(target));
                    if let Some(entry) = resolved_entries.first() {
                        paths.push((entry.path.clone(), entry.size_bytes));
                        continue;
                    }
                    if let Some(dir) = index.directory_record(target) {
                        paths.push((dir.path, dir.size_bytes));
                        continue;
                    }
                    if let Some((path, size_bytes)) = index_target_path_size(index, target.as_str())
                    {
                        paths.push((path, size_bytes));
                    }
                }
                return DeleteOrchestrator::delete_explicit_paths(paths, dry_run, &*self.platform)
                    .map_err(|e| e.to_string());
            }
        }

        let snapshot = self
            .get_last_snapshot()
            .ok_or_else(|| "No snapshot loaded".to_string())?;
        if snapshot.snapshot_id != snapshot_id {
            return Err("Snapshot expired or mismatch".to_string());
        }
        let mut paths = Vec::new();
        for target in &entry_ids {
            if let Some((path, size_bytes)) =
                snapshot_target_path_size(&snapshot.tree, &snapshot.entries, target)
            {
                paths.push((path, size_bytes));
            }
        }
        DeleteOrchestrator::delete_explicit_paths(paths, dry_run, &*self.platform)
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

fn index_target_path_size(index: &SnapshotIndex, target: &str) -> Option<(String, u64)> {
    let target = normalize_facade_path(target);
    let parent = parent_path_of(&target)?;
    let query = index.query_directory(&parent, None, false, "name");
    query
        .direct_children
        .into_iter()
        .find(|node| facade_paths_equal(&node.path, &target))
        .map(|node| (node.path, node.size_bytes))
}

fn snapshot_target_path_size(
    root: &ScanTreeNode,
    entries: &[volward_core::model::StorageEntry],
    target: &str,
) -> Option<(String, u64)> {
    if let Some(entry) = entries.iter().find(|entry| entry.id == target) {
        return Some((entry.path_or_uri.clone(), entry.size_bytes));
    }
    find_tree_node(root, target).map(|node| (node.path.clone(), node.size_bytes))
}

fn find_tree_node<'a>(node: &'a ScanTreeNode, target: &str) -> Option<&'a ScanTreeNode> {
    let target = normalize_facade_path(target);
    if facade_paths_equal(&normalize_facade_path(&node.path), &target) {
        return Some(node);
    }
    for child in &node.children {
        if let Some(found) = find_tree_node(child, &target) {
            return Some(found);
        }
    }
    None
}

fn parent_path_of(path: &str) -> Option<String> {
    let normalized = normalize_facade_path(path);
    if let Some(share) = unc_share_root(&normalized) {
        if share.eq_ignore_ascii_case(&normalized) {
            return Some(share);
        }
    }
    match normalized.rfind('/') {
        Some(2) if has_windows_drive_prefix(&normalized) => Some(normalized[..3].to_string()),
        Some(0) => Some("/".to_string()),
        Some(i) if i > 0 => Some(normalized[..i].to_string()),
        _ => {
            if is_windows_drive_root(&normalized) {
                Some(normalized)
            } else {
                None
            }
        }
    }
}

fn normalize_facade_path(path: &str) -> String {
    let normalized = path.replace('\\', "/");
    if is_unc_path(&normalized) {
        let trimmed = normalized.trim_end_matches('/');
        if trimmed.is_empty() || trimmed == "/" {
            return normalized;
        }
        return trimmed.to_string();
    }
    if normalized.len() > 1 && normalized.ends_with('/') && !is_windows_drive_root(&normalized) {
        normalized[..normalized.len() - 1].to_string()
    } else {
        normalized
    }
}

fn is_unc_path(path: &str) -> bool {
    if !path.starts_with("//") {
        return false;
    }
    let mut parts = path[2..].split('/').filter(|p| !p.is_empty());
    parts.next().is_some() && parts.next().is_some()
}

fn unc_share_root(path: &str) -> Option<String> {
    if !is_unc_path(path) {
        return None;
    }
    let mut parts = path[2..].split('/').filter(|p| !p.is_empty());
    let server = parts.next()?;
    let share = parts.next()?;
    Some(format!("//{server}/{share}"))
}

fn facade_paths_equal(left: &str, right: &str) -> bool {
    let windows_style = has_windows_drive_prefix(left)
        || has_windows_drive_prefix(right)
        || left.starts_with("//")
        || right.starts_with("//");
    if windows_style {
        left.eq_ignore_ascii_case(right)
    } else {
        left == right
    }
}

fn has_windows_drive_prefix(path: &str) -> bool {
    let bytes = path.as_bytes();
    bytes.len() >= 3 && bytes[1] == b':' && bytes[2] == b'/' && bytes[0].is_ascii_alphabetic()
}

fn is_windows_drive_root(path: &str) -> bool {
    has_windows_drive_prefix(path) && path.len() == 3
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
    fn load_index_from_path_accepts_legacy_snapshot_json() {
        let snapshot = minimal_snapshot();
        let expected_id = snapshot.snapshot_id.clone();
        let path = std::env::temp_dir().join(format!(
            "volward-legacy-snapshot-index-{}.json",
            std::process::id()
        ));

        let file = File::create(&path).expect("create legacy snapshot");
        serde_json::to_writer(BufWriter::new(file), &snapshot).expect("write legacy snapshot");

        let engine = VolwardEngine::new();
        engine
            .load_index_from_path(&path.to_string_lossy())
            .expect("legacy snapshot should load as index");
        let summary_json = engine
            .get_index_summary_json()
            .expect("index summary should exist");
        assert!(summary_json.contains(&expected_id));

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn delete_entries_json_allows_explicit_non_deletable_media_in_index_mode() {
        let engine = VolwardEngine::new();
        let mut snapshot = minimal_snapshot();
        snapshot.entries.push(StorageEntry {
            id: "e3".to_string(),
            display_name: "movie.mov".to_string(),
            path_or_uri: "/Users/x/Movies/movie.mov".to_string(),
            size_bytes: 120,
            category: EntryCategory::Media,
            risk_level: RiskLevel::High,
            source_type: SourceType::File,
            deletable: false,
            reason: "media".to_string(),
        });
        engine.set_last_snapshot(snapshot);

        let report = engine.delete_entries_json("test-snap", vec!["e3".to_string()], true);
        assert!(report.contains(r#""deleted_count":1"#), "{report}");
        assert!(report.contains(r#""freed_bytes":120"#), "{report}");
        assert!(!report.contains(r#""error""#), "{report}");
    }

    #[test]
    fn delete_entries_json_allows_directory_paths_in_index_mode() {
        let engine = VolwardEngine::new();
        let mut snapshot = minimal_snapshot();
        snapshot.tree.children.push(ScanTreeNode {
            name: "Users".to_string(),
            path: "/Users".to_string(),
            is_dir: true,
            size_bytes: 40,
            entry_id: None,
            children: vec![ScanTreeNode {
                name: "notes.txt".to_string(),
                path: "/Users/notes.txt".to_string(),
                is_dir: false,
                size_bytes: 40,
                entry_id: Some("dir-child".to_string()),
                children: vec![],
            }],
        });
        engine.set_last_snapshot(snapshot);

        let report = engine.delete_entries_json("test-snap", vec!["/Users".to_string()], true);
        assert!(report.contains(r#""deleted_count":1"#), "{report}");
        assert!(report.contains(r#""freed_bytes":40"#), "{report}");
        assert!(!report.contains(r#""error""#), "{report}");
    }

    #[test]
    fn async_load_index_from_path_accepts_legacy_snapshot_json() {
        let snapshot = minimal_snapshot();
        let expected_id = snapshot.snapshot_id.clone();
        let path = std::env::temp_dir().join(format!(
            "volward-async-legacy-snapshot-index-{}.json",
            std::process::id()
        ));

        let file = File::create(&path).expect("create legacy snapshot");
        serde_json::to_writer(BufWriter::new(file), &snapshot).expect("write legacy snapshot");

        let engine = VolwardEngine::new();
        assert_eq!(
            engine.start_load_index_from_path_async(path.to_string_lossy().into_owned()),
            "ok"
        );
        while engine.is_index_loading() {
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        assert!(engine.get_last_index_load_error().is_none());
        let summary_json = engine
            .get_index_summary_json()
            .expect("index summary should exist");
        assert!(summary_json.contains(&expected_id));

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn invalidated_async_index_load_does_not_publish_stale_error() {
        let engine = VolwardEngine::new();
        let missing_path = std::env::temp_dir().join(format!(
            "volward-missing-index-{}-{}.json",
            std::process::id(),
            uuid::Uuid::new_v4()
        ));

        assert_eq!(
            engine.start_load_index_from_path_async(missing_path.to_string_lossy().into_owned()),
            "ok"
        );
        engine.invalidate_index_load();
        std::thread::sleep(std::time::Duration::from_millis(50));

        assert!(!engine.is_index_loading());
        assert!(engine.get_last_index_load_error().is_none());
    }

    #[test]
    fn repeated_async_index_load_start_is_busy_or_retries_after_prior_load() {
        let engine = VolwardEngine::new();
        let first_path = std::env::temp_dir().join(format!(
            "volward-first-missing-index-{}-{}.json",
            std::process::id(),
            uuid::Uuid::new_v4()
        ));
        let second_path = std::env::temp_dir().join(format!(
            "volward-second-missing-index-{}-{}.json",
            std::process::id(),
            uuid::Uuid::new_v4()
        ));

        assert_eq!(
            engine.start_load_index_from_path_async(first_path.to_string_lossy().into_owned()),
            "ok"
        );
        let second_start =
            engine.start_load_index_from_path_async(second_path.to_string_lossy().into_owned());
        assert!(second_start == "ok" || second_start.starts_with("busy:"));
        while engine.is_index_loading() {
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        assert_eq!(
            engine.start_load_index_from_path_async(second_path.to_string_lossy().into_owned()),
            "ok"
        );
        while engine.is_index_loading() {
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
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

    #[test]
    fn parent_path_of_handles_windows_drive_root_children() {
        assert_eq!(parent_path_of("C:/pagefile.sys").as_deref(), Some("C:/"));
        assert_eq!(
            parent_path_of(r"C:\Users\me\a.txt").as_deref(),
            Some("C:/Users/me")
        );
        assert_eq!(
            parent_path_of("/Users/x/a.txt").as_deref(),
            Some("/Users/x")
        );
        assert_eq!(
            parent_path_of("//server/share/a/b.txt").as_deref(),
            Some("//server/share/a")
        );
        assert_eq!(
            parent_path_of("//server/share").as_deref(),
            Some("//server/share")
        );
    }
}
