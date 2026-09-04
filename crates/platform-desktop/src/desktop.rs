use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
#[cfg(target_os = "macos")]
use std::process::Command;
use std::sync::atomic::AtomicBool;
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

use jwalk::{DirEntry, Error, Parallelism, WalkDir};
use volward_core::model::allocated_file_size;
use volward_core::manifest::DirFingerprint;
use volward_core::model::TrashEmptyReport;
use volward_core::model::{
    CapabilityLevel, DeleteReport, PlatformCapabilities, RawFsEntry, ScanRoot, VolumeStats,
};
use volward_core::platform::{
    is_cancelled, PlatformError, PlatformStorage, WalkAction, WalkOptions,
};

use crate::walk_prune::{is_protected_path, prune_child_directories};

fn system_time_secs(time: SystemTime) -> i64 {
    match time.duration_since(UNIX_EPOCH) {
        Ok(duration) => duration.as_secs().min(i64::MAX as u64) as i64,
        Err(error) => -(error.duration().as_secs().min(i64::MAX as u64) as i64),
    }
}

fn normalize_path_string(path: &str) -> String {
    let normalized = path.replace('\\', "/");
    if normalized.len() > 1 && normalized.ends_with('/') && !is_windows_drive_root(&normalized) {
        normalized[..normalized.len() - 1].to_string()
    } else {
        normalized
    }
}

fn is_windows_drive_root(path: &str) -> bool {
    let bytes = path.as_bytes();
    bytes.len() == 3 && bytes[1] == b':' && bytes[2] == b'/' && bytes[0].is_ascii_alphabetic()
}

fn normalize_protected_prefixes(prefixes: Vec<String>) -> Vec<String> {
    prefixes
        .into_iter()
        .map(|p| normalize_path_string(&p))
        .filter(|p| !p.is_empty())
        .fold(Vec::<String>::new(), |mut acc, p| {
            if !acc
                .iter()
                .any(|existing| protected_prefixes_equal(existing, &p))
            {
                acc.push(p);
            }
            acc
        })
}

fn protected_prefixes_equal(left: &str, right: &str) -> bool {
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

#[cfg(any(windows, test))]
fn windows_protected_prefixes_from_env(get_env: impl Fn(&str) -> Option<String>) -> Vec<String> {
    let mut protected = Vec::new();
    for key in ["SystemRoot", "WINDIR", "ProgramFiles", "ProgramFiles(x86)"] {
        if let Some(value) = get_env(key) {
            protected.push(value);
        }
    }
    for fallback in ["C:/Windows", "C:/Program Files", "C:/Program Files (x86)"] {
        if !protected
            .iter()
            .any(|path| protected_prefixes_equal(&normalize_path_string(path), fallback))
        {
            protected.push(fallback.to_string());
        }
    }
    normalize_protected_prefixes(protected)
}

#[cfg(windows)]
fn windows_protected_prefixes() -> Vec<String> {
    windows_protected_prefixes_from_env(|key| std::env::var(key).ok())
}

fn dir_fingerprint_from_read_dir(
    path: &Path,
    children: &[Result<DirEntry<((), ())>, Error>],
) -> DirFingerprint {
    let children_count = children.len().min(u32::MAX as usize) as u32;
    let mtime_secs = fs::metadata(path)
        .ok()
        .and_then(|metadata| metadata.modified().ok())
        .map(system_time_secs)
        .unwrap_or(0);
    let mut max_child_mtime_secs = 0i64;
    for child in children.iter().flatten() {
        max_child_mtime_secs = max_child_mtime_secs.max(entry_mtime_secs(&child.path()));
    }
    DirFingerprint {
        mtime_secs,
        children_count,
        max_child_mtime_secs,
    }
}

/// Identity of a file for hard-link deduplication (`device, inode`). Only
/// files with more than one link are tracked: files with `nlink == 1` cannot
/// have another directory entry pointing at the same inode, so remembering
/// them would waste memory on large scans.
#[cfg(unix)]
fn hardlink_dedup_key(metadata: &std::fs::Metadata) -> Option<(u64, u64)> {
    use std::os::unix::fs::MetadataExt;
    if metadata.nlink() > 1 {
        Some((metadata.dev(), metadata.ino()))
    } else {
        None
    }
}

#[cfg(not(unix))]
fn hardlink_dedup_key(_metadata: &std::fs::Metadata) -> Option<(u64, u64)> {
    None
}

fn entry_mtime_secs(path: &Path) -> i64 {
    fs::metadata(path)
        .ok()
        .and_then(|metadata| metadata.modified().ok())
        .map(system_time_secs)
        .unwrap_or(0)
}

fn has_child_directory(children: &[Result<DirEntry<((), ())>, Error>]) -> bool {
    children
        .iter()
        .flatten()
        .any(|child| child.file_type().is_dir())
}

fn scan_parallelism() -> usize {
    const DEFAULT_MAX_THREADS: usize = 8;
    if let Ok(raw) = std::env::var("VOLWARD_SCAN_THREADS") {
        if let Ok(value) = raw.parse::<usize>() {
            return value.clamp(1, 32);
        }
    }
    std::thread::available_parallelism()
        .map(|value| value.get().clamp(2, DEFAULT_MAX_THREADS))
        .unwrap_or(4)
}

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
        let mut protected = Vec::new();
        #[cfg(target_os = "macos")]
        {
            protected.extend([
                "/System".to_string(),
                "/private/var/db".to_string(),
                "/private/var/vm".to_string(),
                "/usr".to_string(),
                "/bin".to_string(),
                "/sbin".to_string(),
                "/dev".to_string(),
                "/cores".to_string(),
            ]);
        }
        #[cfg(target_os = "linux")]
        {
            protected.extend([
                "/proc".to_string(),
                "/sys".to_string(),
                "/dev".to_string(),
                "/run".to_string(),
            ]);
        }
        #[cfg(windows)]
        {
            protected.extend(windows_protected_prefixes());
        }
        if let Some(home) = dirs::home_dir() {
            protected.push(normalize_path_string(&home.join(".ssh").to_string_lossy()));
        }
        protected = normalize_protected_prefixes(protected);
        Self {
            protected_prefixes: protected,
        }
    }

    pub fn protected_prefixes(&self) -> &[String] {
        &self.protected_prefixes
    }

    fn fda_probe_paths() -> Vec<PathBuf> {
        let mut probes = Vec::new();
        if let Some(home) = dirs::home_dir() {
            probes.extend(Self::home_fda_probe_paths(&home));
        }
        probes.push(PathBuf::from(
            "/Library/Application Support/com.apple.TCC/TCC.db",
        ));
        probes
    }

    fn home_fda_probe_paths(home: &Path) -> Vec<PathBuf> {
        vec![
            home.join("Library/Safari/Bookmarks.plist"),
            home.join("Library/Messages/chat.db"),
            home.join("Library/Application Support/com.apple.TCC/TCC.db"),
        ]
    }

    fn can_read_probe(path: &Path) -> bool {
        let Ok(mut file) = fs::File::open(path) else {
            return false;
        };
        let mut byte = [0u8; 1];
        file.read(&mut byte).is_ok()
    }

    /// macOS only registers an app in the FDA list after a real read attempt
    /// (metadata/stat alone does not trigger TCC). See Apple Developer Forums #757768.
    fn touch_fda_probe() {
        for probe in Self::fda_probe_paths() {
            let _ = Self::can_read_probe(&probe);
        }
    }

    fn has_full_disk_access() -> bool {
        Self::fda_probe_paths()
            .iter()
            .any(|probe| Self::can_read_probe(probe))
    }

    #[cfg(target_os = "macos")]
    fn deep_scan_ready() -> bool {
        Self::has_full_disk_access()
    }

    #[cfg(not(target_os = "macos"))]
    fn deep_scan_ready() -> bool {
        true
    }

    #[cfg(target_os = "macos")]
    fn permission_hints(deep_scan_ready: bool) -> Vec<String> {
        if deep_scan_ready {
            Vec::new()
        } else {
            vec![
                "Enable Full Disk Access for Volward in System Settings → Privacy & Security → Full Disk Access to scan ~/Library caches and app data."
                    .to_string(),
            ]
        }
    }

    #[cfg(not(target_os = "macos"))]
    fn permission_hints(_deep_scan_ready: bool) -> Vec<String> {
        Vec::new()
    }
}

impl PlatformStorage for DesktopPlatform {
    fn probe_capabilities(&self) -> PlatformCapabilities {
        let deep_scan_ready = Self::deep_scan_ready();
        PlatformCapabilities {
            level: CapabilityLevel::FullPath,
            can_delete: true,
            can_traverse_system_paths: deep_scan_ready,
            permission_hints: Self::permission_hints(deep_scan_ready),
        }
    }

    fn is_deep_scan_ready(&self) -> bool {
        Self::deep_scan_ready()
    }

    fn discover_roots(&self, user_selected: &[String]) -> Result<Vec<ScanRoot>, PlatformError> {
        let mut roots = Vec::new();
        for p in user_selected {
            let path = PathBuf::from(p);
            if path.exists() {
                roots.push(ScanRoot {
                    path: normalize_path_string(&path.to_string_lossy()),
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
                    path: normalize_path_string(&home.to_string_lossy()),
                    label: "Home".to_string(),
                });
            }
        }
        Ok(roots)
    }

    fn walk_entries(
        &self,
        roots: &[ScanRoot],
        options: WalkOptions<'_>,
        cancel: &AtomicBool,
        on_entry: &mut dyn FnMut(RawFsEntry) -> WalkAction,
    ) -> Result<u64, PlatformError> {
        let mut paths_skipped = 0u64;
        let baseline_fingerprints = options.baseline_fingerprints.cloned().map(Arc::new);
        let mut seen_hardlinks = HashSet::<(u64, u64)>::new();
        for root in roots {
            if is_cancelled(cancel) {
                return Err(PlatformError::Cancelled);
            }
            let root_path = Path::new(&root.path);
            if !root_path.exists() {
                continue;
            }
            let dir_fingerprints_cache =
                Arc::new(Mutex::new(HashMap::<PathBuf, Option<DirFingerprint>>::new()));
            for entry in WalkDir::new(root_path)
                .parallelism(Parallelism::RayonNewPool(scan_parallelism()))
                .skip_hidden(false)
                .follow_links(false)
                .sort(false)
                .process_read_dir({
                    let protected = self.protected_prefixes.clone();
                    let dir_fingerprints_cache = dir_fingerprints_cache.clone();
                    let baseline_fingerprints = baseline_fingerprints.clone();
                    move |_depth, path, _state, children| {
                        let current_fingerprint = dir_fingerprint_from_read_dir(path, children);
                        let path_str = path.to_string_lossy().to_string();
                        let unchanged = baseline_fingerprints
                            .as_ref()
                            .and_then(|fingerprints| fingerprints.get(&path_str))
                            .is_some_and(|baseline| baseline.matches(&current_fingerprint));
                        let subtree_skipped = unchanged && !has_child_directory(children);
                        if let Ok(mut cache) = dir_fingerprints_cache.lock() {
                            cache.insert(
                                path.to_path_buf(),
                                (!unchanged || subtree_skipped).then_some(current_fingerprint),
                            );
                        }
                        if subtree_skipped {
                            children.clear();
                        }
                        prune_child_directories(children, &protected);
                    }
                })
                .into_iter()
            {
                if is_cancelled(cancel) {
                    return Err(PlatformError::Cancelled);
                }
                let entry = match entry {
                    Ok(e) => e,
                    Err(_) => {
                        paths_skipped += 1;
                        continue;
                    }
                };
                let path = entry.path();
                let path_str = normalize_path_string(&path.to_string_lossy());
                if is_protected_path(&path, &self.protected_prefixes) {
                    continue;
                }
                let is_dir = entry.file_type().is_dir();
                let metadata = match entry.metadata() {
                    Ok(metadata) => metadata,
                    Err(_) => {
                        paths_skipped += 1;
                        continue;
                    }
                };
                let mut size_bytes = 0u64;
                if !is_dir {
                    size_bytes = allocated_file_size(&metadata);
                    if let Some(key) = hardlink_dedup_key(&metadata) {
                        if !seen_hardlinks.insert(key) {
                            // Another directory entry already contributed the
                            // allocated bytes for this inode. Keep the alias
                            // visible for browsing/deletion but do not count
                            // its space again in any aggregate.
                            size_bytes = 0;
                        }
                    }
                }
                let dir_fingerprint = if is_dir {
                    if let Ok(cache) = dir_fingerprints_cache.lock() {
                        if let Some(cached) = cache.get(&path) {
                            cached.clone()
                        } else {
                            Some(DirFingerprint {
                                mtime_secs: metadata.modified().map(system_time_secs).unwrap_or(0),
                                children_count: 0,
                                max_child_mtime_secs: 0,
                            })
                        }
                    } else {
                        Some(DirFingerprint {
                            mtime_secs: metadata.modified().map(system_time_secs).unwrap_or(0),
                            children_count: 0,
                            max_child_mtime_secs: 0,
                        })
                    }
                } else {
                    None
                };
                match on_entry(RawFsEntry {
                    path: path_str,
                    is_dir,
                    size_bytes,
                    dir_fingerprint,
                    modified_at_ms: if is_dir {
                        None
                    } else {
                        metadata
                            .modified()
                            .ok()
                            .map(system_time_secs)
                            .map(|secs| secs.saturating_mul(1000))
                    },
                }) {
                    WalkAction::Stop => return Ok(paths_skipped),
                    WalkAction::SkipSubtree => continue,
                    WalkAction::Continue => {}
                }
            }
        }
        Ok(paths_skipped)
    }

    fn trash_paths(&self, paths: &[String]) -> Result<DeleteReport, PlatformError> {
        let mut deleted_count = 0usize;
        let mut failed_paths = Vec::new();
        for p in paths {
            if is_protected_path(Path::new(p), &self.protected_prefixes) {
                failed_paths.push(p.clone());
                continue;
            }
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

    fn is_path_protected(&self, path: &str) -> bool {
        is_protected_path(Path::new(path), &self.protected_prefixes)
    }

    fn empty_trash(&self) -> Result<TrashEmptyReport, PlatformError> {
        #[cfg(target_os = "macos")]
        {
            let output = Command::new("osascript")
                .args(["-e", "tell application \"Finder\" to empty the trash"])
                .output()
                .map_err(PlatformError::Io)?;
            if output.status.success() {
                return Ok(TrashEmptyReport { cleared_count: 0 });
            }
            let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
            Err(PlatformError::Io(std::io::Error::other(format!(
                "osascript empty trash failed: {stderr}"
            ))))
        }

        #[cfg(not(target_os = "macos"))]
        {
            let items = trash::os_limited::list().map_err(|e| {
                PlatformError::Io(std::io::Error::new(
                    std::io::ErrorKind::Other,
                    e.to_string(),
                ))
            })?;
            let cleared_count = items.len();
            if cleared_count == 0 {
                return Ok(TrashEmptyReport { cleared_count: 0 });
            }
            trash::os_limited::purge_all(items).map_err(|e| {
                PlatformError::Io(std::io::Error::new(
                    std::io::ErrorKind::Other,
                    e.to_string(),
                ))
            })?;
            Ok(TrashEmptyReport { cleared_count })
        }
    }

    fn open_permission_settings(&self) -> Result<(), PlatformError> {
        #[cfg(target_os = "macos")]
        {
            Self::touch_fda_probe();
            const URLS: &[&str] = &[
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            ];
            let mut last_err = None;
            for url in URLS {
                match std::process::Command::new("open").arg(url).spawn() {
                    Ok(_) => return Ok(()),
                    Err(e) => last_err = Some(e),
                }
            }
            Err(PlatformError::Io(last_err.unwrap_or_else(|| {
                std::io::Error::other("open settings failed")
            })))
        }
        #[cfg(not(target_os = "macos"))]
        {
            Err(PlatformError::Unsupported("open_permission_settings"))
        }
    }

    fn quick_list_dir(&self, path: &str) -> Result<Vec<RawFsEntry>, PlatformError> {
        let dir_path = Path::new(path);
        let read_dir = fs::read_dir(dir_path)?;
        let mut out = Vec::new();
        for entry in read_dir {
            let entry = match entry {
                Ok(e) => e,
                Err(_) => continue,
            };
            let entry_path = entry.path();
            if is_protected_path(&entry_path, &self.protected_prefixes) {
                continue;
            }
            let metadata = match entry.metadata() {
                Ok(m) => m,
                Err(_) => continue,
            };
            let is_dir = metadata.is_dir();
            out.push(RawFsEntry {
                path: normalize_path_string(&entry_path.to_string_lossy()),
                is_dir,
                size_bytes: if is_dir { 0 } else { allocated_file_size(&metadata) },
                dir_fingerprint: None,
                modified_at_ms: if is_dir {
                    None
                } else {
                    metadata
                        .modified()
                        .ok()
                        .map(system_time_secs)
                        .map(|secs| secs.saturating_mul(1000))
                },
            });
        }
        Ok(out)
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
                total = stat.f_blocks * bsize;
                available = stat.f_bavail * bsize;
            }
        }
        #[cfg(windows)]
        {
            use std::os::windows::ffi::OsStrExt;
            use windows_sys::Win32::Storage::FileSystem::GetDiskFreeSpaceExW;

            let mut wide: Vec<u16> = path.as_os_str().encode_wide().collect();
            wide.push(0);
            let mut free_available = 0u64;
            let mut total_bytes = 0u64;
            let mut total_free = 0u64;
            let ok = unsafe {
                GetDiskFreeSpaceExW(
                    wide.as_ptr(),
                    &mut free_available,
                    &mut total_bytes,
                    &mut total_free,
                )
            };
            if ok == 0 {
                return Err(PlatformError::Io(std::io::Error::last_os_error()));
            }
            total = total_bytes;
            available = free_available;
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
    use volward_core::platform::{PlatformStorage, WalkOptions};
    use volward_core::{Classifier, ScanOrchestrator};

    #[test]
    fn protected_prefixes_include_platform_defaults() {
        let p = DesktopPlatform::new();
        let prefixes = p.protected_prefixes();
        #[cfg(windows)]
        {
            assert!(prefixes
                .iter()
                .any(|x| x == "C:/Windows" || x.ends_with("/Windows")));
        }
        #[cfg(target_os = "linux")]
        {
            assert!(prefixes.iter().any(|x| x == "/proc"));
            assert!(prefixes.iter().any(|x| x == "/sys"));
        }
        #[cfg(target_os = "macos")]
        {
            assert!(prefixes.iter().any(|x| x == "/System"));
        }
    }

    #[test]
    fn windows_protected_prefixes_use_environment_roots() {
        let prefixes = windows_protected_prefixes_from_env(|key| match key {
            "SystemRoot" => Some(r"D:\Windows".to_string()),
            "ProgramFiles" => Some(r"D:\Apps\Program Files".to_string()),
            "ProgramFiles(x86)" => Some(r"D:\Apps\Program Files (x86)".to_string()),
            _ => None,
        });

        assert!(prefixes.iter().any(|path| path == "D:/Windows"));
        assert!(prefixes.iter().any(|path| path == "D:/Apps/Program Files"));
        assert!(prefixes
            .iter()
            .any(|path| path == "D:/Apps/Program Files (x86)"));
        assert!(prefixes.iter().any(|path| path == "C:/Windows"));
        assert!(prefixes.iter().any(|path| path == "C:/Program Files"));
        assert!(prefixes.iter().any(|path| path == "C:/Program Files (x86)"));
    }

    #[test]
    fn protected_prefix_normalization_deduplicates_windows_case() {
        let prefixes = normalize_protected_prefixes(vec![
            r"C:\Windows".to_string(),
            "c:/windows".to_string(),
            "/System".to_string(),
            "/System".to_string(),
        ]);

        assert_eq!(
            prefixes
                .iter()
                .filter(|path| path.eq_ignore_ascii_case("C:/Windows"))
                .count(),
            1
        );
        assert_eq!(prefixes.iter().filter(|path| *path == "/System").count(), 1);
    }

    #[test]
    fn deep_scan_capability_is_platform_specific() {
        let p = DesktopPlatform::new();
        let caps = p.probe_capabilities();
        #[cfg(target_os = "macos")]
        {
            assert_eq!(caps.can_traverse_system_paths, p.is_deep_scan_ready());
            assert_eq!(caps.permission_hints.is_empty(), p.is_deep_scan_ready(),);
        }
        #[cfg(not(target_os = "macos"))]
        {
            assert!(p.is_deep_scan_ready());
            assert!(caps.can_traverse_system_paths);
            assert!(caps.permission_hints.is_empty());
        }
    }

    #[test]
    fn discovers_home_when_empty_selection() {
        let p = DesktopPlatform::new();
        let roots = p.discover_roots(&[]).unwrap();
        assert!(!roots.is_empty());
        assert!(roots[0].path.contains("Users") || roots[0].label == "Home");
    }

    #[test]
    fn full_disk_access_probe_uses_multiple_protected_files() {
        let home = PathBuf::from("/Users/example");
        let probes = DesktopPlatform::home_fda_probe_paths(&home);

        assert!(probes
            .iter()
            .any(|path| path.ends_with("Library/Safari/Bookmarks.plist")));
        assert!(probes
            .iter()
            .any(|path| path.ends_with("Library/Messages/chat.db")));
        assert!(probes
            .iter()
            .any(|path| path.ends_with("Library/Application Support/com.apple.TCC/TCC.db")));
    }

    #[test]
    fn full_disk_access_probe_reads_existing_file_only() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let base =
            std::env::temp_dir().join(format!("volward-fda-probe-{}-{unique}", std::process::id()));
        fs::create_dir_all(&base).expect("mkdir");
        let readable = base.join("probe.db");
        fs::write(&readable, b"ok").expect("write probe");

        assert!(DesktopPlatform::can_read_probe(&readable));
        assert!(!DesktopPlatform::can_read_probe(&base.join("missing.db")));

        fs::remove_dir_all(base).expect("cleanup");
    }

    #[test]
    fn walk_emits_directory_fingerprint_from_read_dir() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock after epoch")
            .as_nanos();
        let root_path = std::env::temp_dir().join(format!(
            "volward-fingerprint-{}-{unique}",
            std::process::id()
        ));
        fs::create_dir_all(root_path.join("subdir")).expect("create test directories");
        fs::write(root_path.join("one.txt"), b"1").expect("write first file");
        fs::write(root_path.join("two.txt"), b"2").expect("write second file");

        let platform = DesktopPlatform::new();
        let roots = vec![ScanRoot {
            path: root_path.to_string_lossy().to_string(),
            label: "test".to_string(),
        }];
        let cancel = AtomicBool::new(false);
        let mut root_fingerprint = None;
        platform
            .walk_entries(
                &roots,
                WalkOptions {
                    baseline_fingerprints: None,
                },
                &cancel,
                &mut |entry| {
                    if entry.path == roots[0].path {
                        root_fingerprint = entry.dir_fingerprint;
                    }
                    WalkAction::Continue
                },
            )
            .expect("walk should succeed");

        let fingerprint = root_fingerprint.expect("root fingerprint should be emitted");
        assert!(fingerprint.mtime_secs > 0);
        assert_eq!(fingerprint.children_count, 3);

        fs::remove_dir_all(root_path).expect("remove test directory");
    }

    #[test]
    fn entry_mtime_tracks_direct_entry_changes() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let base = std::env::temp_dir().join(format!(
            "volward-entry-mtime-{}-{unique}",
            std::process::id()
        ));
        fs::create_dir_all(&base).expect("mkdir");
        let file = base.join("f.bin");
        fs::write(&file, b"1").expect("write");
        let before = entry_mtime_secs(&file);
        std::thread::sleep(std::time::Duration::from_secs(1));
        fs::write(&file, b"modified").expect("rewrite");
        let after = entry_mtime_secs(&file);
        assert!(
            after > before,
            "direct file mtime should update (before={before}, after={after})"
        );
        fs::remove_dir_all(base).expect("cleanup");
    }

    #[test]
    fn incremental_scan_reuses_unchanged_real_subtree() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock after epoch")
            .as_nanos();
        let base_path = std::env::temp_dir().join(format!(
            "volward-incremental-{}-{unique}",
            std::process::id()
        ));
        let root_path = base_path.join("root");
        let cache_path = base_path.join("cache");
        fs::create_dir_all(root_path.join("Caches")).expect("create test directories");
        fs::write(root_path.join("one.txt"), b"one").expect("write root file");
        fs::write(root_path.join("Caches/two.bin"), b"two").expect("write cache file");

        let platform = DesktopPlatform::new();
        let orchestrator =
            ScanOrchestrator::with_cache_dir(&platform, Classifier::default(), &cache_path);
        let selected = vec![root_path.to_string_lossy().to_string()];
        let cancel = AtomicBool::new(false);
        let first = orchestrator
            .run_scan(
                "real-full".to_string(),
                selected.clone(),
                false,
                &cancel,
                |_| {},
                |_snapshot| {},
            )
            .expect("full scan should succeed");
        let second = orchestrator
            .run_scan(
                "real-incremental".to_string(),
                selected.clone(),
                true,
                &cancel,
                |_| {},
                |_snapshot| {},
            )
            .expect("incremental scan should succeed");

        assert!(first.stats.paths_seen > second.stats.paths_seen);
        assert_eq!(first.tree.size_bytes, second.tree.size_bytes);
        assert!(!first.entries.is_empty());
        assert_eq!(first.entries.len(), second.entries.len());
        assert_eq!(first.entries[0].path_or_uri, second.entries[0].path_or_uri);
        assert!(second
            .warnings
            .iter()
            .any(|warning| warning.contains("Incremental scan reused")));

        std::thread::sleep(std::time::Duration::from_secs(1));
        fs::write(root_path.join("Caches/two.bin"), vec![0u8; 12_000])
            .expect("modify file inside reused subtree");
        let third = orchestrator
            .run_scan(
                "real-incremental-after-modify".to_string(),
                selected,
                true,
                &cancel,
                |_| {},
                |_snapshot| {},
            )
            .expect("incremental scan after file change should succeed");
        assert!(
            third.stats.paths_seen > second.stats.paths_seen,
            "subdirectory file change should invalidate reuse (second={}, third={})",
            second.stats.paths_seen,
            third.stats.paths_seen
        );
        assert!(third.tree.size_bytes > first.tree.size_bytes);

        fs::remove_dir_all(base_path).expect("remove test directory");
    }

    #[test]
    fn quick_list_dir_lists_only_one_level() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let root_path =
            std::env::temp_dir().join(format!("volward-quicklist-{}-{unique}", std::process::id()));
        fs::create_dir_all(root_path.join("sub/nested")).expect("mkdir");
        fs::write(root_path.join("top.txt"), b"hello").expect("write top file");
        fs::write(root_path.join("sub/nested/deep.txt"), b"deep").expect("write nested file");

        let platform = DesktopPlatform::new();
        let entries = platform
            .quick_list_dir(&root_path.to_string_lossy())
            .expect("quick list should succeed");

        assert_eq!(
            entries.len(),
            2,
            "should only see top-level entries, not nested/deep.txt"
        );
        let file_entry = entries
            .iter()
            .find(|e| e.path.ends_with("top.txt"))
            .expect("top.txt listed");
        assert!(!file_entry.is_dir);
        assert!(file_entry.size_bytes >= 5, "physical size underflows logical");
        #[cfg(unix)]
        assert_eq!(file_entry.size_bytes % 512, 0, "sizes are block-aligned");
        let dir_entry = entries
            .iter()
            .find(|e| e.path.ends_with("sub"))
            .expect("sub dir listed");
        assert!(dir_entry.is_dir);
        assert_eq!(dir_entry.size_bytes, 0);

        fs::remove_dir_all(root_path).expect("cleanup");
    }

    #[test]
    fn quick_list_dir_returns_error_for_missing_path() {
        let platform = DesktopPlatform::new();
        let result = platform.quick_list_dir("/definitely/does/not/exist/volward-test");
        assert!(result.is_err());
    }

    #[cfg(unix)]
    #[test]
    fn full_scan_counts_hardlinked_inode_once() {
        use volward_core::classify::Classifier;
        use volward_core::model::allocated_file_size;

        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let base_path =
            std::env::temp_dir().join(format!("volward-hardlink-{}-{unique}", std::process::id()));
        let original = base_path.join("original.bin");
        let alias_dir = base_path.join("alias");
        fs::create_dir_all(&alias_dir).expect("mkdir alias dir");
        fs::write(&original, b"shared content").expect("write original");
        let alias = alias_dir.join("copy.bin");
        fs::hard_link(&original, &alias).expect("create hard link");

        let expected_once = allocated_file_size(&fs::metadata(&original).unwrap());
        let platform = DesktopPlatform::new();
        let orchestrator = ScanOrchestrator::with_cache_dir(
            &platform,
            Classifier::default(),
            base_path.join("cache"),
        );
        let selected = vec![base_path.to_string_lossy().to_string()];
        let cancel = AtomicBool::new(false);
        let snapshot = orchestrator
            .run_scan(
                "hardlink-scan".to_string(),
                selected,
                false,
                &cancel,
                |_| {},
                |_snapshot| {},
            )
            .expect("scan should succeed");

        assert_eq!(snapshot.stats.files_seen, 2);
        assert_eq!(snapshot.tree.size_bytes, expected_once);

        fs::remove_dir_all(&base_path).expect("cleanup");
    }
}
