use std::fs::File;
use std::io::{BufWriter, Write};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use platform_desktop::DesktopPlatform;
use volward_core::classify::Classifier;
use volward_core::delete::DeleteOrchestrator;
use volward_core::model::{
    DeleteReport, EntryCategory, PlatformCapabilities, ScanProgress, ScanTreeNode, SourceType,
    StorageSnapshot, TrashEmptyReport,
};
use volward_core::rules::DesktopRules;
use volward_core::scan::ScanOrchestrator;
use volward_core::PlatformStorage;
use volward_core::SnapshotCatalog;
use volward_core::SnapshotIndex;
use volward_core::{
    ai_aggregate_path_from_delete_target, AiCandidateBuilder, AnalysisOptions, Capability,
    CapabilityAnalysisError, CapabilityAnalysisPhase, CapabilityJobStore, CapabilityRegistry,
    CleanupCandidateAnalyzer, DuplicateFileAnalyzer, LargeFileAnalyzer, NoopProgressSink,
    OsKnowledgeBase, SimilarPhotoAnalyzer, DEFAULT_CANDIDATE_CAP,
};

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
    is_ai_candidates_building: Arc<AtomicBool>,
    ai_candidates_json: Arc<Mutex<Option<String>>>,
    ai_candidates_generation: Arc<std::sync::atomic::AtomicU64>,
    capability_registry: Arc<Mutex<CapabilityRegistry>>,
    /// Async capability jobs keyed by job id; clone-safe interior mutability.
    capability_jobs: CapabilityJobStore,
}

impl Default for VolwardEngine {
    fn default() -> Self {
        Self::new()
    }
}

impl VolwardEngine {
    pub fn new() -> Self {
        let platform = Arc::new(DesktopPlatform::new());
        let mut capability_registry = CapabilityRegistry::new();
        capability_registry.register(Arc::new(LargeFileAnalyzer));
        capability_registry.register(Arc::new(CleanupCandidateAnalyzer::new(load_classifier(
            platform.as_ref(),
        ))));
        capability_registry.register(Arc::new(DuplicateFileAnalyzer::new(
            platform.protected_prefixes().to_vec(),
        )));
        capability_registry.register(Arc::new(SimilarPhotoAnalyzer::new(
            platform.protected_prefixes().to_vec(),
        )));
        Self {
            platform,
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
            is_ai_candidates_building: Arc::new(AtomicBool::new(false)),
            ai_candidates_json: Arc::new(Mutex::new(None)),
            ai_candidates_generation: Arc::new(std::sync::atomic::AtomicU64::new(0)),
            capability_registry: Arc::new(Mutex::new(capability_registry)),
            capability_jobs: CapabilityJobStore::new(),
        }
    }

    /// Engine with a pre-registered capability analyzer set (tests / injection).
    pub fn with_capability_registry(registry: CapabilityRegistry) -> Self {
        let engine = Self::new();
        if let Ok(mut current) = engine.capability_registry.lock() {
            *current = registry;
        }
        engine
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
    // Capability analysis (registry + async job state)

    /// Synchronous capability analysis against the current index. Returns
    /// `{"result": <CapabilityAnalysisResult>}` or `{"error": {...}}`.
    pub fn analyze_capability_json(
        &self,
        snapshot_id: &str,
        capability: &str,
        options_json: &str,
    ) -> String {
        let Some(capability) = parse_capability(capability) else {
            return capability_error_json(&CapabilityAnalysisError::new(
                "invalid_capability",
                format!("unknown capability {capability:?}"),
            ));
        };
        let options = match parse_capability_options(options_json, capability, snapshot_id) {
            Ok(options) => options,
            Err(error) => return capability_error_json(&error),
        };
        let registry = match self.capability_registry.lock() {
            Ok(registry) => registry.clone(),
            Err(_) => {
                return capability_error_json(&CapabilityAnalysisError::new(
                    "internal_error",
                    "capability registry lock poisoned",
                ));
            }
        };
        let Some(index) = self.current_index() else {
            return capability_error_json(&CapabilityAnalysisError::for_request(
                "no_snapshot",
                "no snapshot or index loaded",
                capability,
                snapshot_id,
            ));
        };
        match registry.analyze(&index, snapshot_id, capability, &options, &NoopProgressSink) {
            Ok(result) => serde_json::json!({ "result": result }).to_string(),
            Err(error) => capability_error_json(&error),
        }
    }

    /// Starts an async capability job on a worker thread and returns
    /// `{"job_id": "..."}` or `{"error": {...}}`.
    pub fn start_capability_analysis_json(
        &self,
        snapshot_id: &str,
        capability: &str,
        options_json: &str,
    ) -> String {
        let Some(capability) = parse_capability(capability) else {
            return capability_error_json(&CapabilityAnalysisError::new(
                "invalid_capability",
                format!("unknown capability {capability:?}"),
            ));
        };
        let options = match parse_capability_options(options_json, capability, snapshot_id) {
            Ok(options) => options,
            Err(error) => return capability_error_json(&error),
        };
        let snapshot_matches = self
            .current_index()
            .as_ref()
            .map(|index| index.snapshot_id == snapshot_id)
            .unwrap_or(false);
        if !snapshot_matches {
            return capability_error_json(&CapabilityAnalysisError::for_request(
                "snapshot_mismatch",
                format!("requested snapshot {snapshot_id} does not match the current index"),
                capability,
                snapshot_id,
            ));
        }
        let registry = match self.capability_registry.lock() {
            Ok(registry) => registry.clone(),
            Err(_) => {
                return capability_error_json(&CapabilityAnalysisError::new(
                    "internal_error",
                    "capability registry lock poisoned",
                ));
            }
        };
        if !registry.supports(capability) {
            return capability_error_json(&CapabilityAnalysisError::unsupported(
                capability,
                snapshot_id,
            ));
        }

        let job_handle = self.capability_jobs.create(snapshot_id, capability);
        let job_id = job_handle.job_id().to_string();
        let job_id_inner = job_id.clone();
        let index = self.last_index.clone();
        let job_snapshot = snapshot_id.to_string();
        let job_capability = capability;
        let job_options = options;

        std::thread::spawn(move || {
            job_handle.update_progress(CapabilityAnalysisPhase::Inspecting, 0, 0, None);
            let result = (|| {
                // Clone the index out of the lock so long-running analyzers
                // never stall concurrent FFI (snapshot refresh, status polls).
                let current = index
                    .lock()
                    .map_err(|_| {
                        CapabilityAnalysisError::new("internal_error", "index lock poisoned")
                    })?
                    .clone()
                    .ok_or_else(|| {
                        CapabilityAnalysisError::for_request(
                            "no_snapshot",
                            "no snapshot or index loaded",
                            job_capability,
                            &job_snapshot,
                        )
                    })?;
                if current.snapshot_id != job_snapshot {
                    return Err(CapabilityAnalysisError::for_request(
                        "snapshot_mismatch",
                        format!(
                            "requested snapshot {job_snapshot} does not match the current index {}",
                            current.snapshot_id
                        ),
                        job_capability,
                        &job_snapshot,
                    ));
                }
                registry.analyze(
                    &current,
                    &job_snapshot,
                    job_capability,
                    &job_options,
                    &job_handle,
                )
            })();

            if job_handle.is_cancelled() {
                return;
            }
            match result {
                Ok(analysis) => {
                    // Revalidate the snapshot after analysis: a refresh during
                    // the run must invalidate the job instead of producing a
                    // deletion plan against a stale snapshot.
                    let current_snapshot = index
                        .lock()
                        .ok()
                        .and_then(|guard| guard.as_ref().map(|i| i.snapshot_id.clone()));
                    if current_snapshot.as_deref() != Some(job_snapshot.as_str()) {
                        job_handle.fail(
                            serde_json::json!({
                                "code": "snapshot_mismatch",
                                "message": format!(
                                    "snapshot changed while capability job {job_id_inner} was running"
                                ),
                                "capability": job_capability,
                                "snapshot_id": job_snapshot,
                            })
                            .to_string(),
                        );
                        return;
                    }
                    job_handle.complete(Some(analysis));
                }
                Err(error) => {
                    let error_json = serde_json::to_string(&error).unwrap_or_else(|_| {
                        "{\"code\":\"internal_error\",\"message\":\"error serialization failed\"}"
                            .to_string()
                    });
                    job_handle.fail(error_json);
                }
            }
        });

        serde_json::json!({ "job_id": job_id }).to_string()
    }

    /// Current job status as `{"progress": ..., "result": ...}` or an error envelope.
    pub fn get_capability_job_status_json(&self, job_id: &str) -> String {
        match self.capability_jobs.status(job_id) {
            Some(status) => serde_json::to_string(&status).unwrap_or_else(|_| {
                capability_error_json(&CapabilityAnalysisError::new(
                    "internal_error",
                    "job status serialization failed",
                ))
            }),
            None => capability_error_json(&CapabilityAnalysisError::new(
                "job_not_found",
                format!("no capability job with id {job_id}"),
            )),
        }
    }

    pub fn cancel_capability_analysis(&self, job_id: &str) -> bool {
        self.capability_jobs.cancel(job_id)
    }

    fn current_index(&self) -> Option<SnapshotIndex> {
        self.last_index.lock().ok().and_then(|guard| guard.clone())
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
                    if ai_aggregate_path_from_delete_target(target).is_some() {
                        paths.extend(resolve_index_ai_aggregate_paths(index, target)?);
                        continue;
                    }
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
            if ai_aggregate_path_from_delete_target(target).is_some() {
                paths.extend(resolve_snapshot_ai_aggregate_paths(&snapshot, target)?);
                continue;
            }
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

    /// Build AI candidate JSON for the given snapshot.
    ///
    /// Prefers `last_index` (production path — `run_index_scan` clears
    /// `last_snapshot`), then falls back to in-memory `last_snapshot`
    /// (tests / legacy). Heavy work: call via
    /// [`Self::start_build_ai_candidates_async`] from the UI path.
    pub fn build_ai_candidates_json(&self, snapshot_id: &str) -> String {
        use std::collections::HashSet;
        use volward_core::{
            compute_result_cache_key, AiAnalysisResult, AiCandidateBuilder, OsKnowledgeBase,
            PreClassifiedEntry, DEFAULT_CANDIDATE_CAP, DEFAULT_PRECLASSIFIED_CAP,
        };

        let kb = OsKnowledgeBase::for_current_platform();

        // 1) Prefer index (production path). Copy inputs under the lock, then
        // release before aggregation/serialize so other FFI isn't stalled.
        let index_inputs = if let Ok(guard) = self.last_index.lock() {
            guard.as_ref().map(|index| {
                (
                    index.snapshot_id.clone(),
                    index.root_path.clone(),
                    index.stats.clone(),
                    index.summary().root_size_bytes,
                    index.reclaimable_estimate_bytes,
                    index.classified_paths(),
                    index.unclassified_files(),
                    index
                        .entries_with_category("BuildArtifact")
                        .into_iter()
                        .map(|entry| {
                            (
                                entry.path.clone(),
                                entry.size_bytes,
                                index.is_directory(&entry.path),
                                entry.deletable,
                            )
                        })
                        .collect::<Vec<_>>(),
                )
            })
        } else {
            None
        };

        if let Some((
            index_snap_id,
            root_path,
            stats,
            root_size_bytes,
            reclaimable,
            classified,
            files,
            build_artifacts,
        )) = index_inputs
        {
            if index_snap_id != snapshot_id {
                return format!("error:snapshot_id mismatch: got {index_snap_id}");
            }
            let mut builder = AiCandidateBuilder::from_unclassified_files(&files, &classified, &kb);
            for (path, size_bytes, is_dir, deletable) in build_artifacts {
                builder.push_pre_classified(PreClassifiedEntry {
                    is_dir,
                    path,
                    size_bytes,
                    category: EntryCategory::BuildArtifact,
                    confidence: "high".to_string(),
                    reason: "Classified as build artifact by local rules".to_string(),
                    deletable,
                });
            }
            let set = builder
                .annotate_ai_cleanup_patterns()
                .aggregate_by_dir(20)
                .cap_top_n(DEFAULT_CANDIDATE_CAP)
                .build()
                .cap_pre_classified_top_n(DEFAULT_PRECLASSIFIED_CAP);
            let cache_key =
                compute_result_cache_key(&root_path, &stats, root_size_bytes, reclaimable, &set);
            let has_existing_result =
                AiAnalysisResult::exists(&cache_key) || AiAnalysisResult::exists(snapshot_id);
            return Self::serialize_ai_candidate_set(
                snapshot_id,
                &set,
                has_existing_result,
                &cache_key,
                &root_path,
            );
        }

        // 2) Fallback: in-memory StorageSnapshot (tests / legacy)
        let snapshot_owned = match self.last_snapshot.lock() {
            Ok(g) => g.clone(),
            Err(e) => return format!("error:lock:{e}"),
        };
        let snapshot = match snapshot_owned.as_ref() {
            Some(s) => s,
            None => return "error:no snapshot or index loaded".to_string(),
        };
        if snapshot.snapshot_id != snapshot_id {
            return format!("error:snapshot_id mismatch: got {}", snapshot.snapshot_id);
        }

        let classified: HashSet<String> = snapshot
            .entries
            .iter()
            .map(|e| e.path_or_uri.clone())
            .collect();
        let mut builder = AiCandidateBuilder::from_tree(&snapshot.tree, &classified, &kb);
        for entry in &snapshot.entries {
            if entry.category != EntryCategory::BuildArtifact {
                continue;
            }
            builder.push_pre_classified(PreClassifiedEntry {
                is_dir: entry.source_type == SourceType::Directory,
                path: entry.path_or_uri.clone(),
                size_bytes: entry.size_bytes,
                category: EntryCategory::BuildArtifact,
                confidence: "high".to_string(),
                reason: if entry.reason.is_empty() {
                    "Classified as build artifact by local rules".to_string()
                } else {
                    entry.reason.clone()
                },
                deletable: entry.deletable,
            });
        }
        let set = builder
            .annotate_ai_cleanup_patterns()
            .aggregate_by_dir(20)
            .cap_top_n(DEFAULT_CANDIDATE_CAP)
            .build()
            .cap_pre_classified_top_n(DEFAULT_PRECLASSIFIED_CAP);
        let root_path = snapshot.tree.path.clone();
        let cache_key = compute_result_cache_key(
            &root_path,
            &snapshot.stats,
            snapshot.tree.size_bytes,
            snapshot.reclaimable_estimate_bytes,
            &set,
        );
        let has_existing_result =
            AiAnalysisResult::exists(&cache_key) || AiAnalysisResult::exists(snapshot_id);

        Self::serialize_ai_candidate_set(
            snapshot_id,
            &set,
            has_existing_result,
            &cache_key,
            &root_path,
        )
    }

    fn serialize_ai_candidate_set(
        snapshot_id: &str,
        set: &volward_core::AiCandidateSet,
        has_existing_result: bool,
        cache_key: &str,
        root_path: &str,
    ) -> String {
        match serde_json::to_string(&serde_json::json!({
            "snapshot_id": snapshot_id,
            "root_path": root_path,
            "result_cache_key": cache_key,
            "pre_classified": set.pre_classified,
            "unknown_candidates": set.candidates,
            "estimated_input_tokens": set.estimated_input_tokens,
            "total_raw_count": set.total_raw_count,
            "candidates_total_before_cap": set.candidates_total_before_cap,
            "truncated": set.truncated,
            "pre_classified_truncated": set.pre_classified_truncated,
            "has_existing_result": has_existing_result,
        })) {
            Ok(s) => s,
            Err(e) => format!("error:serialize:{e}"),
        }
    }

    /// Build candidates on a worker thread so Flutter's main isolate stays
    /// responsive on multi-hundred-GB scans.
    pub fn start_build_ai_candidates_async(&self, snapshot_id: String) -> String {
        if self
            .is_ai_candidates_building
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::Relaxed)
            .is_err()
        {
            return "busy:ai candidates build already in progress".to_string();
        }

        let generation = self.ai_candidates_generation.fetch_add(1, Ordering::SeqCst) + 1;
        if let Ok(mut g) = self.ai_candidates_json.lock() {
            *g = None;
        }

        // Snapshot Arc handles for the worker; the build method locks briefly.
        let engine_index = self.last_index.clone();
        let engine_snapshot = self.last_snapshot.clone();
        let result_slot = self.ai_candidates_json.clone();
        let building = self.is_ai_candidates_building.clone();
        let generation_slot = self.ai_candidates_generation.clone();

        // We need a thin stand-in that can call the same build logic. Reconstruct
        // a minimal engine view via a free helper using the cloned Arcs.
        std::thread::spawn(move || {
            let json =
                Self::build_ai_candidates_json_with(&engine_index, &engine_snapshot, &snapshot_id);
            if generation_slot.load(Ordering::SeqCst) == generation {
                if let Ok(mut g) = result_slot.lock() {
                    *g = Some(json);
                }
            }
            building.store(false, Ordering::Release);
        });

        "ok".to_string()
    }

    fn build_ai_candidates_json_with(
        last_index: &Arc<Mutex<Option<SnapshotIndex>>>,
        last_snapshot: &Arc<Mutex<Option<StorageSnapshot>>>,
        snapshot_id: &str,
    ) -> String {
        // Temporary engine shell so we reuse the same method body without
        // duplicating aggregation logic. Only index/snapshot fields are read.
        let shell = VolwardEngine {
            platform: Arc::new(DesktopPlatform::new()),
            cancel: Arc::new(AtomicBool::new(false)),
            is_scanning: Arc::new(AtomicBool::new(false)),
            last_snapshot: last_snapshot.clone(),
            last_index: last_index.clone(),
            is_index_loading: Arc::new(AtomicBool::new(false)),
            last_index_load_error: Arc::new(Mutex::new(None)),
            index_load_generation: Arc::new(std::sync::atomic::AtomicU64::new(0)),
            index_version: Arc::new(std::sync::atomic::AtomicU64::new(0)),
            last_progress: Arc::new(Mutex::new(None)),
            last_checkpoint: Arc::new(Mutex::new(None)),
            _scan_handle: Arc::new(Mutex::new(None)),
            is_ai_candidates_building: Arc::new(AtomicBool::new(false)),
            ai_candidates_json: Arc::new(Mutex::new(None)),
            ai_candidates_generation: Arc::new(std::sync::atomic::AtomicU64::new(0)),
            capability_registry: Arc::new(Mutex::new(CapabilityRegistry::new())),
            capability_jobs: CapabilityJobStore::new(),
        };
        shell.build_ai_candidates_json(snapshot_id)
    }

    pub fn is_ai_candidates_building(&self) -> bool {
        self.is_ai_candidates_building.load(Ordering::Relaxed)
    }

    /// Latest async build payload (or error string). Empty when none yet.
    pub fn get_ai_candidates_json(&self) -> String {
        self.ai_candidates_json
            .lock()
            .ok()
            .and_then(|g| g.clone())
            .unwrap_or_else(|| "error:not_ready".to_string())
    }

    pub fn save_ai_result_json(&self, snapshot_id: &str, result_json: &str) -> bool {
        use volward_core::AiAnalysisResult;
        let mut result: AiAnalysisResult = match serde_json::from_str(result_json) {
            Ok(r) => r,
            Err(_) => return false,
        };
        if result.snapshot_id.is_empty() {
            result.snapshot_id = snapshot_id.to_string();
        }
        result.save_for_reuse().is_ok()
    }

    /// Load a previously saved AI analysis JSON.
    ///
    /// Prefer the content-addressed `cache_key` (stable across re-scans of the
    /// same directory). Falls back to `snapshot_id` for legacy files.
    pub fn load_ai_result_json(&self, key: &str) -> String {
        use volward_core::AiAnalysisResult;
        match AiAnalysisResult::load(key) {
            Some(result) => {
                serde_json::to_string(&result).unwrap_or_else(|e| format!("error:serialize:{e}"))
            }
            None => "error:not_found".to_string(),
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

fn resolve_index_ai_aggregate_paths(
    index: &SnapshotIndex,
    target: &str,
) -> Result<Vec<(String, u64)>, String> {
    let parent = ai_aggregate_path_from_delete_target(target)
        .ok_or_else(|| "Invalid AI aggregate delete target".to_string())?;
    let kb = OsKnowledgeBase::for_current_platform();
    let classified = index.classified_paths();
    let files = index.unclassified_files();
    let set = AiCandidateBuilder::from_unclassified_files(&files, &classified, &kb)
        .annotate_ai_cleanup_patterns()
        .aggregate_by_dir(20)
        .cap_top_n(DEFAULT_CANDIDATE_CAP)
        .build();
    let valid = set.candidates.iter().any(|candidate| {
        candidate.path == parent && candidate.delete_target.as_deref() == Some(target)
    });
    if !valid {
        return Err("AI aggregate candidate is no longer valid".to_string());
    }
    Ok(files
        .into_iter()
        .filter(|(path, _)| {
            parent_path_of(path)
                .as_deref()
                .is_some_and(|candidate_parent| facade_paths_equal(candidate_parent, parent))
                && !classified.contains(path)
                && kb.classify_path(path).is_none()
        })
        .collect())
}

fn resolve_snapshot_ai_aggregate_paths(
    snapshot: &StorageSnapshot,
    target: &str,
) -> Result<Vec<(String, u64)>, String> {
    let parent = ai_aggregate_path_from_delete_target(target)
        .ok_or_else(|| "Invalid AI aggregate delete target".to_string())?;
    let kb = OsKnowledgeBase::for_current_platform();
    let classified: std::collections::HashSet<String> = snapshot
        .entries
        .iter()
        .map(|entry| entry.path_or_uri.clone())
        .collect();
    let set = AiCandidateBuilder::from_tree(&snapshot.tree, &classified, &kb)
        .annotate_ai_cleanup_patterns()
        .aggregate_by_dir(20)
        .cap_top_n(DEFAULT_CANDIDATE_CAP)
        .build();
    let valid = set.candidates.iter().any(|candidate| {
        candidate.path == parent && candidate.delete_target.as_deref() == Some(target)
    });
    if !valid {
        return Err("AI aggregate candidate is no longer valid".to_string());
    }
    let node = find_tree_node(&snapshot.tree, parent)
        .ok_or_else(|| "AI aggregate directory is no longer present".to_string())?;
    Ok(node
        .children
        .iter()
        .filter(|child| {
            !child.is_dir
                && !classified.contains(&child.path)
                && kb.classify_path(&child.path).is_none()
        })
        .map(|child| (child.path.clone(), child.size_bytes))
        .collect())
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

fn parse_capability(value: &str) -> Option<Capability> {
    serde_json::from_str::<Capability>(&format!("\"{value}\"")).ok()
}

fn parse_capability_options(
    options_json: &str,
    capability: Capability,
    snapshot_id: &str,
) -> Result<AnalysisOptions, CapabilityAnalysisError> {
    serde_json::from_str::<AnalysisOptions>(options_json).map_err(|error| {
        CapabilityAnalysisError::for_request(
            "invalid_options",
            format!("options JSON: {error}"),
            capability,
            snapshot_id,
        )
    })
}

fn capability_error_json(error: &CapabilityAnalysisError) -> String {
    serde_json::json!({ "error": error }).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc::{self, Receiver, Sender};
    use volward_core::model::{
        CapabilityLevel, EntryCategory, RiskLevel, ScanStats, ScanTreeNode, SourceType,
        StorageEntry, StorageSnapshot,
    };
    use volward_core::{
        AnalysisOptions, AnalysisSummary, Capability, CapabilityAnalysisError,
        CapabilityAnalysisResult, CapabilityAnalyzer, CapabilityRegistry, DeletionPlan,
        CAPABILITY_SCHEMA_VERSION,
    };

    struct BlockingAnalyzer {
        started: Mutex<Option<Sender<()>>>,
        release: Mutex<Receiver<()>>,
    }

    impl CapabilityAnalyzer for BlockingAnalyzer {
        fn capability(&self) -> Capability {
            Capability::LargeFiles
        }

        fn analyze(
            &self,
            index: &SnapshotIndex,
            normalized_root: &str,
            _options: &AnalysisOptions,
            _progress: &dyn volward_core::CapabilityProgressSink,
        ) -> Result<CapabilityAnalysisResult, CapabilityAnalysisError> {
            if let Some(started) = self.started.lock().unwrap().take() {
                started.send(()).unwrap();
            }
            self.release.lock().unwrap().recv().unwrap();
            Ok(capability_result(index, normalized_root))
        }
    }

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
                modified_at_ms: None,
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

    fn capability_result(index: &SnapshotIndex, root_path: &str) -> CapabilityAnalysisResult {
        CapabilityAnalysisResult {
            schema_version: CAPABILITY_SCHEMA_VERSION,
            capability: Capability::LargeFiles,
            snapshot_id: index.snapshot_id.clone(),
            root_path: root_path.to_string(),
            analyzer_version: "fake-v1".to_string(),
            generated_at_ms: 1,
            capability_level: CapabilityLevel::FullPath,
            summary: AnalysisSummary::default(),
            groups: vec![],
            next_cursor: None,
            deletion_plan: DeletionPlan {
                snapshot_id: index.snapshot_id.clone(),
                target_count: 0,
                target_bytes: 0,
                targets: vec![],
                blocked_targets: vec![],
                requires_confirmation: true,
            },
            warnings: vec![],
        }
    }

    fn options_json() -> String {
        serde_json::to_string(&AnalysisOptions {
            root_path: "/".to_string(),
            ..AnalysisOptions::default()
        })
        .unwrap()
    }

    fn blocking_engine() -> (VolwardEngine, Receiver<()>, Sender<()>) {
        let (started_tx, started_rx) = mpsc::channel();
        let (release_tx, release_rx) = mpsc::channel();
        let mut registry = CapabilityRegistry::new();
        registry.register(Arc::new(BlockingAnalyzer {
            started: Mutex::new(Some(started_tx)),
            release: Mutex::new(release_rx),
        }));
        let engine = VolwardEngine::with_capability_registry(registry);
        engine.set_last_snapshot(minimal_snapshot());
        (engine, started_rx, release_tx)
    }

    fn start_capability_job(engine: &VolwardEngine) -> String {
        let raw = engine.start_capability_analysis_json(
            "test-snap",
            "large_files",
            &options_json(),
        );
        let value: serde_json::Value = serde_json::from_str(&raw).expect("start response JSON");
        value["job_id"].as_str().expect("job_id").to_string()
    }

    fn wait_for_completed_status(engine: &VolwardEngine, job_id: &str) -> serde_json::Value {
        for _ in 0..100 {
            let raw = engine.get_capability_job_status_json(job_id);
            let status: serde_json::Value = serde_json::from_str(&raw).unwrap();
            if status["progress"]["phase"] == "completed"
                || status["progress"]["cancelled"] == true
            {
                return status;
            }
            std::thread::sleep(std::time::Duration::from_millis(5));
        }
        panic!("capability job did not finish");
    }

    #[test]
    fn capability_analysis_rejects_snapshot_mismatch_and_unsupported_capability() {
        let engine = VolwardEngine::new();
        engine.set_last_snapshot(minimal_snapshot());

        let mismatch: serde_json::Value = serde_json::from_str(
            &engine.analyze_capability_json("stale", "large_files", &options_json()),
        )
        .unwrap();
        assert_eq!(mismatch["error"]["code"], "snapshot_mismatch");

        // large_files/cleanup_candidates/duplicate_files/similar_photos are
        // registered by `new()`; an unregistered capability must still
        // return a structured error.
        let unsupported: serde_json::Value = serde_json::from_str(
            &engine.analyze_capability_json("test-snap", "applications", &options_json()),
        )
        .unwrap();
        assert_eq!(unsupported["error"]["code"], "unsupported_capability");
    }

    #[test]
    fn async_capability_job_reports_progress_and_cancels_without_result() {
        let (engine, started, release) = blocking_engine();
        let job_id = start_capability_job(&engine);
        started.recv().unwrap();

        let active: serde_json::Value = serde_json::from_str(
            &engine.get_capability_job_status_json(&job_id),
        )
        .unwrap();
        assert_eq!(active["progress"]["phase"], "inspecting");
        assert!(engine.cancel_capability_analysis(&job_id));
        release.send(()).unwrap();

        let cancelled = wait_for_completed_status(&engine, &job_id);
        assert_eq!(cancelled["progress"]["cancelled"], true);
        assert!(cancelled["result"].is_null());
    }

    #[test]
    fn async_capability_job_rejects_result_when_snapshot_changes() {
        let (engine, started, release) = blocking_engine();
        let job_id = start_capability_job(&engine);
        started.recv().unwrap();

        let mut replacement = minimal_snapshot();
        replacement.snapshot_id = "replacement-snap".to_string();
        engine.set_last_snapshot(replacement);
        release.send(()).unwrap();

        let completed = wait_for_completed_status(&engine, &job_id);
        assert!(completed["result"].is_null());
        let error = completed["progress"]["error"].as_str().unwrap();
        let error: serde_json::Value = serde_json::from_str(error).unwrap();
        assert_eq!(error["code"], "snapshot_mismatch");
    }

    #[test]
    fn build_ai_candidates_json_caps_aggregates_and_lists_build_artifacts() {
        let engine = VolwardEngine::new();
        let mut snapshot = minimal_snapshot();
        snapshot.entries.push(StorageEntry {
            id: "e-node".to_string(),
            display_name: "node_modules".to_string(),
            path_or_uri: "/Users/x/app/node_modules".to_string(),
            size_bytes: 4096,
            category: EntryCategory::BuildArtifact,
            risk_level: RiskLevel::Low,
            source_type: SourceType::Directory,
            deletable: true,
            reason: "build artifact".to_string(),
            modified_at_ms: None,
        });
        // 250 unclassified siblings fold into one aggregate candidate.
        let children: Vec<ScanTreeNode> = (0..250)
            .map(|i| ScanTreeNode {
                name: format!("blob_{i}.dat"),
                path: format!("/Users/x/scratch/blob_{i}.dat"),
                is_dir: false,
                size_bytes: 1,
                entry_id: None,
                children: vec![],
            })
            .collect();
        snapshot.tree.children.push(ScanTreeNode {
            name: "scratch".to_string(),
            path: "/Users/x/scratch".to_string(),
            is_dir: true,
            size_bytes: 250,
            entry_id: None,
            children,
        });
        engine.set_last_snapshot(snapshot);

        let json = engine.build_ai_candidates_json("test-snap");
        let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid json: {json}");
        let candidates = parsed["unknown_candidates"].as_array().expect("candidates");
        assert_eq!(candidates.len(), 1, "{json}");
        assert_eq!(candidates[0]["path"], "/Users/x/scratch");
        assert_eq!(
            candidates[0]["member_paths"].as_array().map(Vec::len),
            Some(200),
            "{json}"
        );
        assert_eq!(
            candidates[0]["delete_target"],
            "volward-ai-aggregate:v1:/Users/x/scratch"
        );
        assert!(candidates[0].get("delete_member_paths").is_none(), "{json}");
        assert_eq!(parsed["truncated"], false);
        assert_eq!(parsed["total_raw_count"], 250);
        assert_eq!(parsed["candidates_total_before_cap"], 1);

        let pre = parsed["pre_classified"].as_array().expect("pre_classified");
        assert!(
            pre.iter()
                .any(|e| e["path"] == "/Users/x/app/node_modules" && e["confidence"] == "high"),
            "{json}"
        );

        let token = candidates[0]["delete_target"].as_str().unwrap().to_string();
        let report = engine.delete_entries_json("test-snap", vec![token], true);
        assert!(report.contains(r#""deleted_count":250"#), "{report}");
        assert!(report.contains(r#""freed_bytes":250"#), "{report}");
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
            modified_at_ms: None,
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
