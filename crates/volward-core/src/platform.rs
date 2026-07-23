use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};

use crate::manifest::DirFingerprint;
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

pub struct WalkOptions<'a> {
    pub baseline_fingerprints: Option<&'a HashMap<String, DirFingerprint>>,
}

pub trait PlatformStorage: Send + Sync {
    fn probe_capabilities(&self) -> PlatformCapabilities;

    fn is_deep_scan_ready(&self) -> bool;

    fn discover_roots(&self, user_selected: &[String]) -> Result<Vec<ScanRoot>, PlatformError>;

    /// Returns the number of paths skipped (permission / I/O errors).
    fn walk_entries(
        &self,
        roots: &[ScanRoot],
        options: WalkOptions<'_>,
        cancel: &AtomicBool,
        on_entry: &mut dyn FnMut(RawFsEntry) -> WalkAction,
    ) -> Result<u64, PlatformError>;

    fn trash_paths(&self, paths: &[String]) -> Result<DeleteReport, PlatformError>;

    fn volume_stats(&self, root: &ScanRoot) -> Result<VolumeStats, PlatformError>;

    fn open_permission_settings(&self) -> Result<(), PlatformError> {
        Err(PlatformError::Unsupported("open_permission_settings"))
    }
}

pub fn is_cancelled(cancel: &AtomicBool) -> bool {
    cancel.load(Ordering::Relaxed)
}
