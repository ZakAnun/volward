use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use platform_desktop::DesktopPlatform;
use volward_core::classify::Classifier;
use volward_core::model::{
    DeleteReport, PlatformCapabilities, ScanProgress, StorageSnapshot,
};
use volward_core::scan::ScanOrchestrator;
use volward_core::PlatformStorage;

pub struct VolwardEngine {
    platform: DesktopPlatform,
    cancel: Arc<AtomicBool>,
    last_snapshot: Arc<Mutex<Option<StorageSnapshot>>>,
    last_progress: Arc<Mutex<Option<ScanProgress>>>,
}

impl Default for VolwardEngine {
    fn default() -> Self {
        Self::new()
    }
}

impl VolwardEngine {
    pub fn new() -> Self {
        Self {
            platform: DesktopPlatform::new(),
            cancel: Arc::new(AtomicBool::new(false)),
            last_snapshot: Arc::new(Mutex::new(None)),
            last_progress: Arc::new(Mutex::new(None)),
        }
    }

    pub fn probe_capabilities(&self) -> PlatformCapabilities {
        self.platform.probe_capabilities()
    }

    pub fn is_deep_scan_ready(&self) -> bool {
        self.platform.is_deep_scan_ready()
    }

    pub fn start_scan(&self, job_id: String, roots: Vec<String>) -> String {
        self.cancel.store(false, Ordering::Relaxed);
        let classifier = Classifier::new(self.platform.protected_prefixes().to_vec());
        let orchestrator = ScanOrchestrator::new(&self.platform, classifier);
        let cancel = self.cancel.clone();
        let last_snapshot = self.last_snapshot.clone();
        let last_progress = self.last_progress.clone();

        match orchestrator.run_scan(job_id, roots, &cancel, |progress| {
            if let Ok(mut g) = last_progress.lock() {
                *g = Some(progress);
            }
        }) {
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

    pub fn cancel_scan(&self) {
        self.cancel.store(true, Ordering::Relaxed);
    }

    pub fn get_last_snapshot(&self) -> Option<StorageSnapshot> {
        self.last_snapshot.lock().ok().and_then(|g| g.clone())
    }

    pub fn get_last_progress(&self) -> Option<ScanProgress> {
        self.last_progress.lock().ok().and_then(|g| g.clone())
    }

    pub fn delete_to_trash(&self, paths: Vec<String>) -> DeleteReport {
        self.platform
            .trash_paths(&paths)
            .unwrap_or(DeleteReport {
                deleted_count: 0,
                failed_paths: paths,
            })
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

    pub fn delete_to_trash_json(&self, paths: Vec<String>) -> String {
        serde_json::to_string(&self.delete_to_trash(paths)).unwrap_or_else(|_| "{}".to_string())
    }
}
