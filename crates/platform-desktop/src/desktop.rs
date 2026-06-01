use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;

use jwalk::WalkDir;
use volward_core::model::{
    CapabilityLevel, DeleteReport, PlatformCapabilities, RawFsEntry, ScanRoot, VolumeStats,
};
use volward_core::platform::{is_cancelled, PlatformError, PlatformStorage, WalkAction};

const MAX_DEPTH: usize = 8;

pub struct DesktopPlatform {
    protected_prefixes: Vec<String>,
}

impl Default for DesktopPlatform {
    fn default() -> Self {
        Self::new()
    }
}

impl DesktopPlatform {
    pub fn new() -> Self {
        let mut protected = vec![
            "/System".to_string(),
            "/private/var/db".to_string(),
            "/usr".to_string(),
            "/bin".to_string(),
            "/sbin".to_string(),
        ];
        if let Some(home) = dirs::home_dir() {
            protected.push(home.join(".ssh").to_string_lossy().to_string());
        }
        Self {
            protected_prefixes: protected,
        }
    }

    pub fn protected_prefixes(&self) -> &[String] {
        &self.protected_prefixes
    }

    fn fda_probe_path() -> Option<PathBuf> {
        dirs::home_dir().map(|h| h.join("Library/Safari/Bookmarks.plist"))
    }

    fn has_full_disk_access() -> bool {
        let Some(probe) = Self::fda_probe_path() else {
            return false;
        };
        fs::metadata(&probe).map(|m| m.is_file()).unwrap_or(false)
    }
}

impl PlatformStorage for DesktopPlatform {
    fn probe_capabilities(&self) -> PlatformCapabilities {
        let fda = Self::has_full_disk_access();
        let mut hints = Vec::new();
        if !fda {
            hints.push(
                "Grant Full Disk Access in System Settings → Privacy & Security → Full Disk Access."
                    .to_string(),
            );
        }
        PlatformCapabilities {
            level: CapabilityLevel::FullPath,
            can_delete: true,
            can_traverse_system_paths: fda,
            permission_hints: hints,
        }
    }

    fn is_deep_scan_ready(&self) -> bool {
        Self::has_full_disk_access()
    }

    fn discover_roots(&self, user_selected: &[String]) -> Result<Vec<ScanRoot>, PlatformError> {
        let mut roots = Vec::new();
        for p in user_selected {
            let path = PathBuf::from(p);
            if path.exists() {
                roots.push(ScanRoot {
                    path: path.to_string_lossy().to_string(),
                    label: path
                        .file_name()
                        .map(|n| n.to_string_lossy().to_string())
                        .unwrap_or_else(|| "Selected".to_string()),
                });
            }
        }
        if roots.is_empty() {
            if let Some(home) = dirs::home_dir() {
                roots.push(ScanRoot {
                    path: home.to_string_lossy().to_string(),
                    label: "Home".to_string(),
                });
            }
        }
        Ok(roots)
    }

    fn walk_entries(
        &self,
        roots: &[ScanRoot],
        cancel: &AtomicBool,
        on_entry: &mut dyn FnMut(RawFsEntry) -> WalkAction,
    ) -> Result<(), PlatformError> {
        for root in roots {
            if is_cancelled(cancel) {
                return Err(PlatformError::Cancelled);
            }
            let root_path = Path::new(&root.path);
            if !root_path.exists() {
                continue;
            }
            for entry in WalkDir::new(root_path)
                .skip_hidden(false)
                .follow_links(false)
                .max_depth(MAX_DEPTH)
                .into_iter()
                .filter_map(|e| e.ok())
            {
                if is_cancelled(cancel) {
                    return Err(PlatformError::Cancelled);
                }
                let path = entry.path();
                let path_str = path.to_string_lossy().to_string();
                if self
                    .protected_prefixes
                    .iter()
                    .any(|pfx| path_str.starts_with(pfx))
                {
                    continue;
                }
                let meta = match entry.metadata() {
                    Ok(m) => m,
                    Err(_) => continue,
                };
                let is_dir = meta.is_dir();
                let size_bytes = if is_dir { 0 } else { meta.len() };
                match on_entry(RawFsEntry {
                    path: path_str,
                    is_dir,
                    size_bytes,
                }) {
                    WalkAction::Stop => return Ok(()),
                    WalkAction::SkipSubtree => continue,
                    WalkAction::Continue => {}
                }
            }
        }
        Ok(())
    }

    fn trash_paths(&self, paths: &[String]) -> Result<DeleteReport, PlatformError> {
        let mut deleted_count = 0usize;
        let mut failed_paths = Vec::new();
        for p in paths {
            match trash::delete(p) {
                Ok(_) => deleted_count += 1,
                Err(_) => failed_paths.push(p.clone()),
            }
        }
        Ok(DeleteReport {
            deleted_count,
            failed_paths,
            freed_bytes: 0,
        })
    }

    fn open_permission_settings(&self) -> Result<(), PlatformError> {
        #[cfg(target_os = "macos")]
        {
            std::process::Command::new("open")
                .arg("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
                .spawn()
                .map(|_| ())
                .map_err(PlatformError::Io)
        }
        #[cfg(not(target_os = "macos"))]
        {
            Err(PlatformError::Unsupported("open_permission_settings"))
        }
    }

    fn volume_stats(&self, root: &ScanRoot) -> Result<VolumeStats, PlatformError> {
        let path = Path::new(&root.path);
        let mut total = 0u64;
        let mut available = 0u64;
        #[cfg(unix)]
        {
            use std::ffi::CString;
            use std::mem::MaybeUninit;
            let path_str = path.to_str().ok_or_else(|| {
                PlatformError::Io(std::io::Error::new(
                    std::io::ErrorKind::InvalidInput,
                    "non-utf8 path",
                ))
            })?;
            let c_path = CString::new(path_str).map_err(|_| {
                PlatformError::Io(std::io::Error::new(
                    std::io::ErrorKind::InvalidInput,
                    "path contains nul",
                ))
            })?;
            let mut stat: MaybeUninit<libc::statfs> = MaybeUninit::uninit();
            let rc = unsafe { libc::statfs(c_path.as_ptr().cast(), stat.as_mut_ptr()) };
            if rc == 0 {
                let stat = unsafe { stat.assume_init() };
                let bsize = stat.f_bsize as u64;
                total = stat.f_blocks as u64 * bsize;
                available = stat.f_bavail as u64 * bsize;
            }
        }
        Ok(VolumeStats {
            total_bytes: total,
            available_bytes: available,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use volward_core::platform::PlatformStorage;

    #[test]
    fn discovers_home_when_empty_selection() {
        let p = DesktopPlatform::new();
        let roots = p.discover_roots(&[]).unwrap();
        assert!(!roots.is_empty());
        assert!(roots[0].path.contains("Users") || roots[0].label == "Home");
    }
}
