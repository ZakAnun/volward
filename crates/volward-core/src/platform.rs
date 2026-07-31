use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};

use crate::manifest::DirFingerprint;
use crate::model::{
    DeleteReport, PlatformCapabilities, RawFsEntry, ScanRoot, TrashEmptyReport, VolumeStats,
};

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

    fn empty_trash(&self) -> Result<TrashEmptyReport, PlatformError> {
        Err(PlatformError::Unsupported("empty_trash"))
    }

    fn volume_stats(&self, root: &ScanRoot) -> Result<VolumeStats, PlatformError>;

    fn open_permission_settings(&self) -> Result<(), PlatformError> {
        Err(PlatformError::Unsupported("open_permission_settings"))
    }

    /// Single-level, non-recursive directory listing for instant UI preview.
    /// Directories in the result have `size_bytes = 0` (unknown — callers
    /// must not treat this as a real empty folder) and `dir_fingerprint =
    /// None`. Default implementation is "unsupported" so existing test
    /// platforms don't need changes; `DesktopPlatform` overrides it.
    fn quick_list_dir(&self, _path: &str) -> Result<Vec<RawFsEntry>, PlatformError> {
        Err(PlatformError::Unsupported("quick_list_dir"))
    }
}

pub fn is_cancelled(cancel: &AtomicBool) -> bool {
    cancel.load(Ordering::Relaxed)
}
