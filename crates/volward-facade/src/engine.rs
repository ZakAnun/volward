use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use platform_desktop::DesktopPlatform;
use volward_core::classify::Classifier;
use volward_core::delete::DeleteOrchestrator;
use volward_core::model::{
    DeleteReport, PlatformCapabilities, ScanProgress, StorageSnapshot,
};
use volward_core::rules::DesktopRules;
use volward_core::scan::ScanOrchestrator;
use volward_core::PlatformStorage;

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
    last_progress: Arc<Mutex<Option<ScanProgress>>>,
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
            last_progress: Arc::new(Mutex::new(None)),
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
        if let Ok(mut g) = self.last_snapshot.lock() {
            *g = Some(snapshot);
        }
    }

    pub fn is_scan_running(&self) -> bool {
        self.is_scanning.load(Ordering::Relaxed)
    }

    pub fn start_scan(&self, job_id: String, roots: Vec<String>) -> String {
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

        let result = orchestrator.run_scan(job_id, roots, &cancel, |progress| {
            if let Ok(mut g) = last_progress.lock() {
                *g = Some(progress);
            }
        });

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

    pub fn start_scan_async(&self, job_id: String, roots: Vec<String>) -> String {
        // Reject if a scan is already in progress.
        if self
            .is_scanning
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::Relaxed)
            .is_err()
        {
            return "error:scan already in progress".to_string();
        }

        let platform = self.platform.clone();
        let cancel = self.cancel.clone();
        let last_snapshot = self.last_snapshot.clone();
        let last_progress = self.last_progress.clone();
        let is_scanning = self.is_scanning.clone();
        let scan_handle = self._scan_handle.clone();

        let job_id_clone = job_id.clone();

        let handle = std::thread::spawn(move || {
            let classifier = load_classifier_from_arc(&platform);
            let orchestrator = ScanOrchestrator::new(platform.as_ref(), classifier);
            match orchestrator.run_scan(job_id_clone, roots, &cancel, |progress| {
                if let Ok(mut g) = last_progress.lock() {
                    *g = Some(progress);
                }
            }) {
                Ok(snapshot) => {
                    if let Ok(mut g) = last_snapshot.lock() {
                        *g = Some(snapshot);
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
        let snapshot = self
            .get_last_snapshot()
            .ok_or_else(|| "No snapshot loaded".to_string())?;
        if snapshot.snapshot_id != snapshot_id {
            return Err("Snapshot expired or mismatch".to_string());
        }
        DeleteOrchestrator::delete_entries(&snapshot, &entry_ids, dry_run, &*self.platform)
            .map_err(|e| e.to_string())
    }

    pub fn probe_capabilities_json(&self) -> String {
        serde_json::to_string(&self.probe_capabilities()).unwrap_or_else(|_| "{}".to_string())
    }

    pub fn get_last_snapshot_json(&self) -> Option<String> {
        self.get_last_snapshot()
            .and_then(|s| serde_json::to_string(&s).ok())
    }

    pub fn get_last_progress_json(&self) -> Option<String> {
        self.get_last_progress()
            .and_then(|p| serde_json::to_string(&p).ok())
    }

    pub fn set_last_snapshot_json(&self, json: &str) -> Result<(), String> {
        let snapshot: StorageSnapshot =
            serde_json::from_str(json).map_err(|e| format!("invalid snapshot json: {e}"))?;
        self.set_last_snapshot(snapshot);
        Ok(())
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
