use crate::model::{DeleteReport, StorageSnapshot};
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
        let mut freed_bytes = 0u64;

        for id in entry_ids {
            let Some(entry) = snapshot.entries.iter().find(|e| e.id == *id) else {
                continue;
            };
            if !entry.deletable {
                continue;
            }
            paths.push(entry.path_or_uri.clone());
            freed_bytes = freed_bytes.saturating_add(entry.size_bytes);
        }

        if dry_run {
            return Ok(DeleteReport {
                deleted_count: paths.len(),
                failed_paths: Vec::new(),
                freed_bytes,
            });
        }

        if paths.is_empty() {
            return Ok(DeleteReport {
                deleted_count: 0,
                failed_paths: Vec::new(),
                freed_bytes: 0,
            });
        }

        let report = platform.trash_paths(&paths)?;
        let actual_freed = snapshot
            .entries
            .iter()
            .filter(|e| {
                paths.contains(&e.path_or_uri) && !report.failed_paths.contains(&e.path_or_uri)
            })
            .map(|e| e.size_bytes)
            .sum();

        Ok(DeleteReport {
            deleted_count: report.deleted_count,
            failed_paths: report.failed_paths,
            freed_bytes: actual_freed,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{
        CapabilityLevel, EntryCategory, RiskLevel, ScanStats, ScanTreeNode, SourceType,
        StorageEntry, StorageSnapshot,
    };
    use std::sync::atomic::AtomicBool;

    struct MockPlatform {
        trashed: std::sync::Mutex<Vec<String>>,
    }

    impl MockPlatform {
        fn new() -> Self {
            Self {
                trashed: std::sync::Mutex::new(Vec::new()),
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
            for p in paths {
                trashed.push(p.clone());
            }
            Ok(DeleteReport {
                deleted_count: paths.len(),
                failed_paths: vec![],
                freed_bytes: 0,
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

    fn sample_snapshot() -> StorageSnapshot {
        StorageSnapshot {
            snapshot_id: "snap-1".to_string(),
            scanned_at_ms: 0,
            capability: CapabilityLevel::FullPath,
            volume_total_bytes: 0,
            volume_used_bytes: 0,
            reclaimable_estimate_bytes: 100,
            tree: ScanTreeNode {
                name: "tmp".to_string(),
                path: "/tmp".to_string(),
                is_dir: true,
                size_bytes: 40,
                entry_id: None,
                children: vec![ScanTreeNode {
                    name: "cache.bin".to_string(),
                    path: "/tmp/cache.bin".to_string(),
                    is_dir: false,
                    size_bytes: 40,
                    entry_id: Some("e1".to_string()),
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
                    path_or_uri: "/tmp/cache.bin".to_string(),
                    size_bytes: 40,
                    category: EntryCategory::Cache,
                    risk_level: RiskLevel::Low,
                    source_type: SourceType::File,
                    deletable: true,
                    reason: "cache".to_string(),
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
                },
            ],
        }
    }

    #[test]
    fn dry_run_does_not_trash() {
        let platform = MockPlatform::new();
        let snap = sample_snapshot();
        let report = DeleteOrchestrator::delete_entries(
            &snap,
            &["e1".to_string(), "e2".to_string()],
            true,
            &platform,
        )
        .unwrap();
        assert_eq!(report.deleted_count, 1);
        assert_eq!(report.freed_bytes, 40);
        assert!(platform.trashed.lock().unwrap().is_empty());
    }

    #[test]
    fn delete_trashes_deletable_paths() {
        let platform = MockPlatform::new();
        let snap = sample_snapshot();
        let report =
            DeleteOrchestrator::delete_entries(&snap, &["e1".to_string()], false, &platform)
                .unwrap();
        assert_eq!(report.deleted_count, 1);
        assert_eq!(report.freed_bytes, 40);
        assert_eq!(
            *platform.trashed.lock().unwrap(),
            vec!["/tmp/cache.bin".to_string()]
        );
    }
}
