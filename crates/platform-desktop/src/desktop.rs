use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

use jwalk::{DirEntry, Error, WalkDir};
use volward_core::manifest::DirFingerprint;
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

fn entry_mtime_secs(path: &Path) -> i64 {
    let Ok(metadata) = fs::metadata(path) else {
        return 0;
    };
    let mut max = metadata.modified().map(system_time_secs).unwrap_or(0);
    if metadata.is_dir() {
        if let Ok(read_dir) = fs::read_dir(path) {
            for entry in read_dir.flatten() {
                if let Ok(child_meta) = entry.metadata() {
                    if child_meta.is_file() {
                        max = max.max(child_meta.modified().map(system_time_secs).unwrap_or(0));
                    }
                }
            }
        }
    }
    max
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
        let mut protected = vec![
            "/System".to_string(),
            "/private/var/db".to_string(),
            "/private/var/vm".to_string(),
            "/usr".to_string(),
            "/bin".to_string(),
            "/sbin".to_string(),
            "/dev".to_string(),
            "/cores".to_string(),
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
}

impl PlatformStorage for DesktopPlatform {
    fn probe_capabilities(&self) -> PlatformCapabilities {
        let fda = Self::has_full_disk_access();
        let mut hints = Vec::new();
        if !fda {
            hints.push(
                "Enable Full Disk Access for Volward in System Settings → Privacy & Security → Full Disk Access to scan ~/Library caches and app data."
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
        options: WalkOptions<'_>,
        cancel: &AtomicBool,
        on_entry: &mut dyn FnMut(RawFsEntry) -> WalkAction,
    ) -> Result<u64, PlatformError> {
        let mut paths_skipped = 0u64;
        let baseline_fingerprints = options.baseline_fingerprints.cloned().map(Arc::new);
        for root in roots {
            if is_cancelled(cancel) {
                return Err(PlatformError::Cancelled);
            }
            let root_path = Path::new(&root.path);
            if !root_path.exists() {
                continue;
            }
            let dir_fingerprints_cache =
                Arc::new(Mutex::new(HashMap::<PathBuf, DirFingerprint>::new()));
            let skipped_subtree_roots = Arc::new(Mutex::new(HashSet::<String>::new()));
            for entry in WalkDir::new(root_path)
                .skip_hidden(false)
                .follow_links(false)
                .sort(false)
                .process_read_dir({
                    let protected = self.protected_prefixes.clone();
                    let dir_fingerprints_cache = dir_fingerprints_cache.clone();
                    let skipped_subtree_roots = skipped_subtree_roots.clone();
                    let baseline_fingerprints = baseline_fingerprints.clone();
                    move |_depth, path, _state, children| {
                        let current_fingerprint = dir_fingerprint_from_read_dir(path, children);
                        if let Ok(mut cache) = dir_fingerprints_cache.lock() {
                            cache.insert(path.to_path_buf(), current_fingerprint.clone());
                        }
                        let path_str = path.to_string_lossy().to_string();
                        let unchanged = baseline_fingerprints
                            .as_ref()
                            .and_then(|fingerprints| fingerprints.get(&path_str))
                            .is_some_and(|baseline| baseline.matches(&current_fingerprint));
                        if unchanged {
                            if let Ok(mut skipped) = skipped_subtree_roots.lock() {
                                skipped.insert(path_str);
                            }
                            for child in children.iter_mut().flatten() {
                                child.read_children_path = None;
                            }
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
                let path_str = path.to_string_lossy().to_string();
                let is_below_skipped_root =
                    skipped_subtree_roots.lock().ok().is_some_and(|skipped| {
                        skipped
                            .iter()
                            .any(|root| is_strict_descendant(&path_str, root))
                    });
                if is_below_skipped_root {
                    continue;
                }
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
                let size_bytes = if is_dir { 0 } else { metadata.len() };
                let dir_fingerprint = if is_dir {
                    dir_fingerprints_cache
                        .lock()
                        .ok()
                        .and_then(|cache| cache.get(&path).cloned())
                        .or_else(|| {
                            Some(DirFingerprint {
                                mtime_secs: metadata.modified().map(system_time_secs).unwrap_or(0),
                                children_count: 0,
                                max_child_mtime_secs: 0,
                            })
                        })
                } else {
                    None
                };
                match on_entry(RawFsEntry {
                    path: path_str,
                    is_dir,
                    size_bytes,
                    dir_fingerprint,
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
                std::io::Error::new(std::io::ErrorKind::Other, "open settings failed")
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
                path: entry_path.to_string_lossy().to_string(),
                is_dir,
                size_bytes: if is_dir { 0 } else { metadata.len() },
                dir_fingerprint: None,
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

fn is_strict_descendant(path: &str, root: &str) -> bool {
    if path == root || !path.starts_with(root) {
        return false;
    }
    root == "/" || path.as_bytes().get(root.len()) == Some(&b'/')
}

#[cfg(test)]
mod tests {
    use super::*;
    use volward_core::platform::{PlatformStorage, WalkOptions};
    use volward_core::{Classifier, ScanOrchestrator};

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
    fn entry_mtime_includes_nested_file_changes() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let base = std::env::temp_dir().join(format!(
            "volward-entry-mtime-{}-{unique}",
            std::process::id()
        ));
        let nested = base.join("Caches");
        fs::create_dir_all(&nested).expect("mkdir");
        fs::write(nested.join("f.bin"), b"1").expect("write");
        let before = entry_mtime_secs(&nested);
        std::thread::sleep(std::time::Duration::from_secs(1));
        fs::write(nested.join("f.bin"), b"modified").expect("rewrite");
        let after = entry_mtime_secs(&nested);
        assert!(
            after > before,
            "nested file mtime should propagate (before={before}, after={after})"
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
            .any(|warning| warning.contains("reused 1 unchanged directories")));

        fs::write(root_path.join("new-after-modify.txt"), b"new file")
            .expect("add file to invalidate root fingerprint");
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
            "directory structure change should invalidate reuse (second={}, third={})",
            second.stats.paths_seen,
            third.stats.paths_seen
        );

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
        assert_eq!(file_entry.size_bytes, 5);
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
}
