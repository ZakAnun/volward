use std::sync::atomic::{AtomicBool, Ordering};

use crate::model::{DeleteReport, PlatformCapabilities, RawFsEntry, ScanRoot, VolumeStats};

#[derive(Debug, thiserror::Error)]
pub enum PlatformError {
    #[error("permission denied: {path}")]
    PermissionDenied { path: String },
    #[error("cancelled")]
    Cancelled,
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("unsupported: {0}")]
    Unsupported(&'static str),
}

pub enum WalkAction {
    Continue,
    SkipSubtree,
    Stop,
}

pub trait PlatformStorage: Send + Sync {
    fn probe_capabilities(&self) -> PlatformCapabilities;

    fn is_deep_scan_ready(&self) -> bool;

    fn discover_roots(&self, user_selected: &[String]) -> Result<Vec<ScanRoot>, PlatformError>;

    fn walk_entries(
        &self,
        roots: &[ScanRoot],
        cancel: &AtomicBool,
        on_entry: &mut dyn FnMut(RawFsEntry) -> WalkAction,
    ) -> Result<(), PlatformError>;

    fn trash_paths(&self, paths: &[String]) -> Result<DeleteReport, PlatformError>;

    fn volume_stats(&self, root: &ScanRoot) -> Result<VolumeStats, PlatformError>;
}

pub fn is_cancelled(cancel: &AtomicBool) -> bool {
    cancel.load(Ordering::Relaxed)
}
