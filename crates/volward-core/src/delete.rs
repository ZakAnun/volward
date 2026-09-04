use crate::index::SnapshotEntryRecord;
use crate::model::{allocated_file_size, DeleteReport, StorageSnapshot, TrashEmptyReport};
use crate::platform::{PlatformError, PlatformStorage};

pub struct DeleteOrchestrator;

impl DeleteOrchestrator {
    pub fn delete_entries(
        snapshot: &StorageSnapshot,
        entry_ids: &[String],
        dry_run: bool,
        platform: &dyn PlatformStorage,
    ) -> Result<DeleteReport, PlatformError> {
        if snapshot.snapshot_id.is_empty() {
            return Err(PlatformError::Unsupported("empty snapshot_id"));
        }

        let mut paths = Vec::new();

        for id in entry_ids {
            let Some(entry) = snapshot.entries.iter().find(|e| e.id == *id) else {
                continue;
            };
            paths.push((entry.path_or_uri.clone(), entry.size_bytes));
        }

        Self::delete_paths(paths, Some(&snapshot.tree.path), dry_run, platform)
    }

    pub fn delete_index_entries(
        snapshot_id: &str,
        entries: &[SnapshotEntryRecord],
        dry_run: bool,
        platform: &dyn PlatformStorage,
    ) -> Result<DeleteReport, PlatformError> {
        if snapshot_id.is_empty() {
            return Err(PlatformError::Unsupported("empty snapshot_id"));
        }

        let mut paths = Vec::new();

        for entry in entries {
            paths.push((entry.path.clone(), entry.size_bytes));
        }

        Self::delete_paths(paths, None, dry_run, platform)
    }

    pub fn delete_explicit_paths(
        paths: Vec<(String, u64)>,
        root: Option<&str>,
        dry_run: bool,
        platform: &dyn PlatformStorage,
    ) -> Result<DeleteReport, PlatformError> {
        Self::delete_paths(paths, root, dry_run, platform)
    }

    fn delete_paths(
        paths: Vec<(String, u64)>,
        root: Option<&str>,
        dry_run: bool,
        platform: &dyn PlatformStorage,
    ) -> Result<DeleteReport, PlatformError> {
        let mut blocked_paths = Vec::new();
        let mut safe_paths = Vec::new();
        for (path, size) in paths {
            if platform.is_path_protected(&path) {
                blocked_paths.push(path);
            } else {
                safe_paths.push((path, size));
            }
        }

        // Revalidate every target against the current filesystem before
        // reporting dry-run counts (and again before the trash move below):
        // missing files, size changes, and root/symlink escapes are all
        // rejected as failed targets rather than silently deleted.
        let mut failed_paths = Vec::new();
        let mut validated = Vec::new();
        for (path, size) in safe_paths {
            match revalidate(&path, size, root) {
                Ok(()) => validated.push((path, size)),
                Err(reason) => failed_paths.push(format!("{path} ({reason})")),
            }
        }

        let freed_bytes = validated
            .iter()
            .map(|(_, size)| *size)
            .fold(0u64, u64::saturating_add);
        if dry_run {
            return Ok(DeleteReport {
                deleted_count: validated.len(),
                failed_paths: blocked_paths
                    .into_iter()
                    .chain(failed_paths)
                    .collect(),
                freed_bytes,
            });
        }

        if validated.is_empty() {
            return Ok(DeleteReport {
                deleted_count: 0,
                failed_paths: blocked_paths.into_iter().chain(failed_paths).collect(),
                freed_bytes: 0,
            });
        }

        // Second revalidation pass immediately before the trash move.
        let mut pre_trash_failures = Vec::new();
        let mut trash_candidates = Vec::new();
        for (path, size) in &validated {
            match revalidate(path, *size, root) {
                Ok(()) => trash_candidates.push(path.clone()),
                Err(reason) => pre_trash_failures.push(format!("{path} ({reason})")),
            }
        }
        if trash_candidates.is_empty() {
            return Ok(DeleteReport {
                deleted_count: 0,
                failed_paths: blocked_paths
                    .into_iter()
                    .chain(failed_paths)
                    .chain(pre_trash_failures)
                    .collect(),
                freed_bytes: 0,
            });
        }

        let report = platform.trash_paths(&trash_candidates)?;
        let all_failed: Vec<String> = blocked_paths
            .into_iter()
            .chain(failed_paths)
            .chain(pre_trash_failures)
            .chain(report.failed_paths.iter().cloned())
            .collect();
        let actual_freed = validated
            .iter()
            .filter(|(path, _)| !all_failed.iter().any(|failed| failed.starts_with(path)))
            .map(|(_, size)| *size)
            .fold(0u64, u64::saturating_add);

        Ok(DeleteReport {
            deleted_count: report.deleted_count,
            failed_paths: all_failed,
            freed_bytes: actual_freed,
        })
    }

    pub fn empty_trash(platform: &dyn PlatformStorage) -> Result<TrashEmptyReport, PlatformError> {
        platform.empty_trash()
    }
}

/// Revalidates a target immediately before deletion: it must still exist,
/// its size must match the snapshot record (when known), and its canonical
/// path must stay inside the user-selected root (rejecting symlink escapes).
fn revalidate(path: &str, expected_size: u64, root: Option<&str>) -> Result<(), String> {
    let metadata = std::fs::metadata(path).map_err(|error| format!("missing:{error}"))?;
    // Sizes recorded in snapshots are physical allocated bytes (du
    // semantics), not logical lengths — compare like for like.
    if !metadata.is_dir()
        && expected_size > 0
        && allocated_file_size(&metadata) != expected_size
    {
        return Err(format!(
            "size_changed:expected {} got {}",
            expected_size,
            allocated_file_size(&metadata)
        ));
    }
    if let Some(root) = root {
        let canonical = std::fs::canonicalize(path)
            .map_err(|error| format!("unresolvable:{error}"))?;
        let canonical_root =
            std::fs::canonicalize(root).map_err(|error| format!("unresolvable_root:{error}"))?;
        if !canonical.starts_with(&canonical_root) {
            return Err("outside_root".to_string());
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{
        CapabilityLevel, EntryCategory, RiskLevel, ScanStats, ScanTreeNode, SourceType,
        StorageEntry, StorageSnapshot,
    };
    use std::collections::HashSet;
    use std::sync::atomic::AtomicBool;
    use tempfile::TempDir;

    struct MockPlatform {
        trashed: std::sync::Mutex<Vec<String>>,
        trash_cleared_count: usize,
        fail_paths: HashSet<String>,
    }

    impl MockPlatform {
        fn new() -> Self {
            Self {
                trashed: std::sync::Mutex::new(Vec::new()),
                trash_cleared_count: 2,
                fail_paths: HashSet::new(),
            }
        }

        fn failing(paths: Vec<String>) -> Self {
            Self {
                trashed: std::sync::Mutex::new(Vec::new()),
                trash_cleared_count: 2,
                fail_paths: paths.into_iter().collect(),
            }
        }
    }

    impl PlatformStorage for MockPlatform {
        fn probe_capabilities(&self) -> crate::model::PlatformCapabilities {
            crate::model::PlatformCapabilities {
                level: CapabilityLevel::FullPath,
                can_delete: true,
                can_traverse_system_paths: true,
                permission_hints: vec![],
            }
        }

        fn is_deep_scan_ready(&self) -> bool {
            true
        }

        fn discover_roots(
            &self,
            _user_selected: &[String],
        ) -> Result<Vec<crate::model::ScanRoot>, PlatformError> {
            Ok(vec![])
        }

        fn walk_entries(
            &self,
            _roots: &[crate::model::ScanRoot],
            _options: crate::platform::WalkOptions<'_>,
            _cancel: &AtomicBool,
            _on_entry: &mut dyn FnMut(crate::model::RawFsEntry) -> crate::platform::WalkAction,
        ) -> Result<u64, PlatformError> {
            Ok(0)
        }

        fn trash_paths(&self, paths: &[String]) -> Result<DeleteReport, PlatformError> {
            let mut trashed = self.trashed.lock().unwrap();
            let mut failed_paths = Vec::new();
            for p in paths {
                if self.fail_paths.contains(p) {
                    failed_paths.push(p.clone());
                } else {
                    trashed.push(p.clone());
                }
            }
            Ok(DeleteReport {
                deleted_count: paths.len() - failed_paths.len(),
                failed_paths,
                freed_bytes: 0,
            })
        }

        fn is_path_protected(&self, path: &str) -> bool {
            path.starts_with("/System")
        }

        fn empty_trash(&self) -> Result<TrashEmptyReport, PlatformError> {
            Ok(TrashEmptyReport {
                cleared_count: self.trash_cleared_count,
            })
        }

        fn volume_stats(
            &self,
            _root: &crate::model::ScanRoot,
        ) -> Result<crate::model::VolumeStats, PlatformError> {
            Ok(crate::model::VolumeStats {
                total_bytes: 0,
                available_bytes: 0,
            })
        }
    }

    fn temp_snapshot(temp: &TempDir) -> StorageSnapshot {
        let root = temp.path().to_string_lossy().to_string();
        let cache = temp.path().join("cache.bin");
        std::fs::write(&cache, vec![0u8; 40]).unwrap();
        let movie = temp.path().join("movie.mov");
        std::fs::write(&movie, vec![0u8; 120]).unwrap();
        let cache_bytes = allocated_file_size(&std::fs::metadata(&cache).unwrap());
        let movie_bytes = allocated_file_size(&std::fs::metadata(&movie).unwrap());
        StorageSnapshot {
            snapshot_id: "snap-1".to_string(),
            scanned_at_ms: 0,
            capability: CapabilityLevel::FullPath,
            volume_total_bytes: 0,
            volume_used_bytes: 0,
            reclaimable_estimate_bytes: 100,
            tree: ScanTreeNode {
                name: "tmp".to_string(),
                path: root.clone(),
                is_dir: true,
                size_bytes: cache_bytes + movie_bytes,
                entry_id: None,
                children: vec![ScanTreeNode {
                    name: "cache.bin".to_string(),
                    path: format!("{root}/cache.bin"),
                    is_dir: false,
                    size_bytes: cache_bytes,
                    entry_id: Some("e1".to_string()),
                    children: vec![],
                }, ScanTreeNode {
                    name: "movie.mov".to_string(),
                    path: format!("{root}/movie.mov"),
                    is_dir: false,
                    size_bytes: movie_bytes,
                    entry_id: Some("e3".to_string()),
                    children: vec![],
                }],
            },
            stats: ScanStats {
                paths_seen: 2,
                dirs_seen: 1,
                files_seen: 1,
                files_in_snapshot: 1,
                paths_skipped: 0,
                truncated: false,
                incomplete_reason: None,
            },
            warnings: vec![],
            entries: vec![
                StorageEntry {
                    id: "e1".to_string(),
                    display_name: "cache.bin".to_string(),
                    path_or_uri: format!("{root}/cache.bin"),
                    size_bytes: cache_bytes,
                    category: EntryCategory::Cache,
                    risk_level: RiskLevel::Low,
                    source_type: SourceType::File,
                    deletable: true,
                    reason: "cache".to_string(),
                    modified_at_ms: None,
                },
                StorageEntry {
                    id: "e2".to_string(),
                    display_name: "system".to_string(),
                    path_or_uri: "/System/foo".to_string(),
                    size_bytes: 999,
                    category: EntryCategory::System,
                    risk_level: RiskLevel::High,
                    source_type: SourceType::File,
                    deletable: false,
                    reason: "protected".to_string(),
                    modified_at_ms: None,
                },
                StorageEntry {
                    id: "e3".to_string(),
                    display_name: "movie.mov".to_string(),
                    path_or_uri: format!("{root}/movie.mov"),
                    size_bytes: movie_bytes,
                    category: EntryCategory::Media,
                    risk_level: RiskLevel::High,
                    source_type: SourceType::File,
                    deletable: false,
                    reason: "media".to_string(),
                    modified_at_ms: None,
                },
            ],
        }
    }

    fn written_allocated(path: &std::path::Path) -> u64 {
        allocated_file_size(&std::fs::metadata(path).unwrap())
    }

    #[test]
    fn dry_run_does_not_trash() {
        let temp = TempDir::new().unwrap();
        let platform = MockPlatform::new();
        let snap = temp_snapshot(&temp);
        let report = DeleteOrchestrator::delete_entries(
            &snap,
            &["e1".to_string(), "e2".to_string()],
            true,
            &platform,
        )
        .unwrap();
        assert_eq!(report.deleted_count, 1);
        assert_eq!(
            report.freed_bytes,
            written_allocated(&temp.path().join("cache.bin"))
        );
        assert!(platform.trashed.lock().unwrap().is_empty());
    }

    #[test]
    fn delete_trashes_deletable_paths() {
        let temp = TempDir::new().unwrap();
        let platform = MockPlatform::new();
        let snap = temp_snapshot(&temp);
        let report =
            DeleteOrchestrator::delete_entries(&snap, &["e1".to_string()], false, &platform)
                .unwrap();
        assert_eq!(report.deleted_count, 1);
        assert_eq!(
            report.freed_bytes,
            written_allocated(&temp.path().join("cache.bin"))
        );
        assert_eq!(
            *platform.trashed.lock().unwrap(),
            vec![temp.path().join("cache.bin").to_string_lossy().to_string()]
        );
    }

    #[test]
    fn delete_allows_explicit_non_protected_media() {
        let temp = TempDir::new().unwrap();
        let platform = MockPlatform::new();
        let snap = temp_snapshot(&temp);
        let report =
            DeleteOrchestrator::delete_entries(&snap, &["e3".to_string()], false, &platform)
                .unwrap();
        assert_eq!(report.deleted_count, 1);
        assert_eq!(
            report.freed_bytes,
            written_allocated(&temp.path().join("movie.mov"))
        );
        assert_eq!(
            *platform.trashed.lock().unwrap(),
            vec![temp.path().join("movie.mov").to_string_lossy().to_string()]
        );
    }

    #[test]
    fn dry_run_rejects_missing_and_size_changed_targets() {
        let temp = TempDir::new().unwrap();
        let platform = MockPlatform::new();
        let root = temp.path().to_string_lossy().to_string();
        let stable = temp.path().join("stable.bin");
        std::fs::write(&stable, vec![0u8; 10]).unwrap();
        let changed = temp.path().join("changed.bin");
        std::fs::write(&changed, vec![0u8; 10]).unwrap();
        let changed_scan_time_bytes = written_allocated(&changed);
        std::fs::write(&changed, vec![0u8; 9000]).unwrap();
        let missing = temp.path().join("missing.bin");

        let report = DeleteOrchestrator::delete_explicit_paths(
            vec![
                (stable.to_string_lossy().to_string(), written_allocated(&stable)),
                (
                    changed.to_string_lossy().to_string(),
                    changed_scan_time_bytes,
                ),
                (missing.to_string_lossy().to_string(), 10),
            ],
            Some(&root),
            true,
            &platform,
        )
        .unwrap();

        assert_eq!(report.deleted_count, 1, "only the unchanged file counts");
        assert!(
            report
                .failed_paths
                .iter()
                .any(|failed| failed.contains("size_changed"))
        );
        assert!(
            report
                .failed_paths
                .iter()
                .any(|failed| failed.contains("missing"))
        );
        assert!(platform.trashed.lock().unwrap().is_empty());
    }

    #[test]
    fn root_escape_and_symlink_escape_are_rejected() {
        let temp = TempDir::new().unwrap();
        let platform = MockPlatform::new();
        let root = temp.path().join("root");
        std::fs::create_dir_all(&root).unwrap();
        let outside = temp.path().join("outside.bin");
        std::fs::write(&outside, vec![0u8; 8]).unwrap();
        let outside_str = outside.to_string_lossy().to_string();
        let root_str = root.to_string_lossy().to_string();
        let outside_bytes = written_allocated(&outside);

        let report = DeleteOrchestrator::delete_explicit_paths(
            vec![(outside_str.clone(), outside_bytes)],
            Some(&root_str),
            true,
            &platform,
        )
        .unwrap();
        assert_eq!(report.deleted_count, 0);
        assert!(report.failed_paths.iter().any(|f| f.contains("outside_root")));

        #[cfg(unix)]
        {
            let link = root.join("escape.link");
            std::os::unix::fs::symlink(&outside, &link).unwrap();
            let report = DeleteOrchestrator::delete_explicit_paths(
                vec![(link.to_string_lossy().to_string(), outside_bytes)],
                Some(&root_str),
                true,
                &platform,
            )
            .unwrap();
            assert_eq!(report.deleted_count, 0);
            assert!(report.failed_paths.iter().any(|f| f.contains("outside_root")));
        }
    }

    #[test]
    fn partial_trash_failures_are_reported_as_retry_targets() {
        let temp = TempDir::new().unwrap();
        let root = temp.path().to_string_lossy().to_string();
        let ok = temp.path().join("ok.bin");
        let fail = temp.path().join("fail.bin");
        std::fs::write(&ok, vec![0u8; 5]).unwrap();
        std::fs::write(&fail, vec![0u8; 7]).unwrap();
        let fail_str = fail.to_string_lossy().to_string();
        let platform = MockPlatform::failing(vec![fail_str.clone()]);

        let report = DeleteOrchestrator::delete_explicit_paths(
            vec![
                (ok.to_string_lossy().to_string(), written_allocated(&ok)),
                (fail_str.clone(), written_allocated(&fail)),
            ],
            Some(&root),
            false,
            &platform,
        )
        .unwrap();

        assert_eq!(report.deleted_count, 1);
        assert_eq!(platform.trashed.lock().unwrap().len(), 1);
        assert!(
            report.failed_paths.iter().any(|failed| failed == &fail_str),
            "failed paths are the retry targets"
        );
    }

    #[test]
    fn empty_trash_delegates_to_platform() {
        let platform = MockPlatform::new();
        let report = DeleteOrchestrator::empty_trash(&platform).unwrap();
        assert_eq!(report.cleared_count, 2);
    }
}
