use std::collections::HashMap;
use std::fs::File;
use std::io::Read;
use std::path::Path;

use sha2::{Digest, Sha256};

use crate::capability::{
    group_items_by_direct_child, AnalysisConfidence, AnalysisItem, AnalysisOptions,
    AnalysisPreview, AnalysisSummary, Capability, CapabilityAnalysisResult, CapabilityLevel,
    DeletionPlan, Recommendation,
};
use crate::capability_registry::{CapabilityAnalysisError, CapabilityAnalyzer, CapabilityProgressSink};
use crate::index::{path_is_at_or_below, CapabilityFileRecord, SnapshotIndex};
use crate::{CapabilityAnalysisPhase, CAPABILITY_SCHEMA_VERSION};

pub const DUPLICATE_FILES_ANALYZER_VERSION: &str = "duplicate_files-v1";

/// Bytes hashed in the cheap pre-filter stage before full-content hashing.
const PARTIAL_HASH_BYTES: usize = 8 * 1024;
/// Bounded streaming buffer for full-content hashing.
const HASH_BUFFER_BYTES: usize = 256 * 1024;

/// Exact-duplicate analysis: size pre-grouping → partial hash → full hash.
/// Only full-content equality forms a duplicate set. Every set keeps at
/// least one file; all other members stay `reviewNeeded` until the user
/// explicitly selects them. No file contents are returned — only hash
/// evidence.
pub struct DuplicateFileAnalyzer {
    protected_prefixes: Vec<String>,
}

impl DuplicateFileAnalyzer {
    pub fn new(protected_prefixes: Vec<String>) -> Self {
        Self { protected_prefixes }
    }

    fn is_protected(&self, path: &str) -> bool {
        self.protected_prefixes
            .iter()
            .any(|prefix| path_is_at_or_below(path, prefix))
    }
}

impl CapabilityAnalyzer for DuplicateFileAnalyzer {
    fn capability(&self) -> Capability {
        Capability::DuplicateFiles
    }

    fn analyze(
        &self,
        index: &SnapshotIndex,
        normalized_root: &str,
        _options: &AnalysisOptions,
        progress: &dyn CapabilityProgressSink,
    ) -> Result<CapabilityAnalysisResult, CapabilityAnalysisError> {
        let mut candidates: Vec<CapabilityFileRecord> = Vec::new();
        let mut blocked_targets = Vec::new();
        let mut file_cursor: Option<String> = None;
        loop {
            let (records, next) = index.capability_files_page(file_cursor.as_deref(), usize::MAX);
            for record in records {
                if !path_is_at_or_below(&record.path, normalized_root) {
                    continue;
                }
                if self.is_protected(&record.path) {
                    blocked_targets.push(record.path);
                    continue;
                }
                // Zero-byte files are trivially identical; including them
                // would flood every duplicate set with noise.
                if record.size_bytes == 0 {
                    continue;
                }
                candidates.push(record);
            }
            match next {
                Some(cursor) => file_cursor = Some(cursor),
                None => break,
            }
        }

        let mut by_size: HashMap<u64, Vec<CapabilityFileRecord>> = HashMap::new();
        for record in candidates {
            by_size.entry(record.size_bytes).or_default().push(record);
        }

        let mut items: Vec<AnalysisItem> = Vec::new();
        let mut target_paths = Vec::new();
        let mut target_bytes = 0u64;
        let total_files = by_size.values().map(|group| group.len() as u64).sum::<u64>();
        let mut processed = 0u64;

        for (_, size_group) in by_size {
            if size_group.len() < 2 {
                continue;
            }
            let mut by_partial: HashMap<String, Vec<CapabilityFileRecord>> = HashMap::new();
            for record in size_group {
                if progress.is_cancelled() {
                    return Err(CapabilityAnalysisError::new(
                        "cancelled",
                        "duplicate analysis cancelled",
                    ));
                }
                processed += 1;
                progress.report(
                    CapabilityAnalysisPhase::Hashing,
                    processed,
                    total_files,
                    Some(record.path.clone()),
                );
                if let Some(hash) = partial_hash(&record.path) {
                    by_partial.entry(hash).or_default().push(record);
                }
            }

            for (_, partial_group) in by_partial {
                if partial_group.len() < 2 {
                    continue;
                }
                let mut by_full: HashMap<String, Vec<CapabilityFileRecord>> = HashMap::new();
                for record in partial_group {
                    if progress.is_cancelled() {
                        return Err(CapabilityAnalysisError::new(
                            "cancelled",
                            "duplicate analysis cancelled",
                        ));
                    }
                    if let Some(hash) = full_hash(&record.path) {
                        by_full.entry(hash).or_default().push(record);
                    }
                }
                for (full_hash_hex, duplicate_group) in by_full {
                    if duplicate_group.len() < 2 {
                        continue;
                    }
                    let keep_index = keep_index(&duplicate_group);
                    for (position, record) in duplicate_group.into_iter().enumerate() {
                        let keep = position == keep_index;
                        if !keep {
                            target_paths.push(record.path.clone());
                            target_bytes += record.size_bytes;
                        }
                        items.push(AnalysisItem {
                            id: record.path.clone(),
                            path: record.path.clone(),
                            display_name: file_name(&record.path),
                            size_bytes: record.size_bytes,
                            is_directory: false,
                            modified_at_ms: record.modified_at_ms,
                            recommendation: if keep {
                                Recommendation::Keep
                            } else {
                                Recommendation::ReviewNeeded
                            },
                            confidence: AnalysisConfidence::High,
                            reason: "duplicate".to_string(),
                            evidence: vec![
                                format!("size_bytes:{}", record.size_bytes),
                                format!("full_hash:{full_hash_hex}"),
                            ],
                            delete_target: if keep {
                                None
                            } else {
                                Some(record.path.clone())
                            },
                            preview: Some(AnalysisPreview {
                                kind: "file".to_string(),
                                locatable: true,
                            }),
                        });
                    }
                }
            }
        }

        progress.report(
            CapabilityAnalysisPhase::BuildingResult,
            total_files,
            total_files,
            None,
        );
        let groups = group_items_by_direct_child(&items, normalized_root);
        let item_count = items.len() as u64;
        let total_bytes = items.iter().map(|item| item.size_bytes).sum();
        let kept_count = items
            .iter()
            .filter(|item| item.recommendation == Recommendation::Keep)
            .count() as u64;
        let review_count = items
            .iter()
            .filter(|item| item.recommendation == Recommendation::ReviewNeeded)
            .count() as u64;

        Ok(CapabilityAnalysisResult {
            schema_version: CAPABILITY_SCHEMA_VERSION,
            capability: Capability::DuplicateFiles,
            snapshot_id: index.snapshot_id.clone(),
            root_path: normalized_root.to_string(),
            analyzer_version: DUPLICATE_FILES_ANALYZER_VERSION.to_string(),
            generated_at_ms: index.scanned_at_ms,
            capability_level: CapabilityLevel::FullPath,
            summary: AnalysisSummary {
                item_count,
                total_bytes,
                safe_count: 0,
                review_count,
                kept_count,
                truncated: false,
            },
            groups,
            next_cursor: None,
            deletion_plan: DeletionPlan {
                snapshot_id: index.snapshot_id.clone(),
                target_count: target_paths.len() as u64,
                target_bytes,
                targets: target_paths,
                blocked_targets,
                requires_confirmation: true,
            },
            warnings: vec![],
        })
    }
}

/// Deterministic keep rule: shallowest path depth, then lexicographically
/// smallest path, then newest mtime. All other members remain review-needed.
fn keep_index(group: &[CapabilityFileRecord]) -> usize {
    group
        .iter()
        .enumerate()
        .min_by(|(_, a), (_, b)| {
            let a_depth = a.path.matches('/').count();
            let b_depth = b.path.matches('/').count();
            a_depth
                .cmp(&b_depth)
                .then_with(|| a.path.cmp(&b.path))
                .then_with(|| b.modified_at_ms.cmp(&a.modified_at_ms))
        })
        .map(|(position, _)| position)
        .unwrap_or(0)
}

fn partial_hash(path: &str) -> Option<String> {
    let mut file = File::open(Path::new(path)).ok()?;
    let mut hasher = Sha256::new();
    let mut buffer = [0u8; 4096];
    let mut remaining = PARTIAL_HASH_BYTES;
    while remaining > 0 {
        let chunk = remaining.min(buffer.len());
        let read = file.read(&mut buffer[..chunk]).ok()?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
        remaining -= read;
    }
    Some(hex(&hasher.finalize()))
}

fn full_hash(path: &str) -> Option<String> {
    let mut file = File::open(Path::new(path)).ok()?;
    let mut hasher = Sha256::new();
    let mut buffer = vec![0u8; HASH_BUFFER_BYTES];
    loop {
        let read = file.read(&mut buffer).ok()?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Some(hex(&hasher.finalize()))
}

fn hex(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        out.push_str(&format!("{byte:02x}"));
    }
    out
}

fn file_name(path: &str) -> String {
    path.rsplit('/')
        .next()
        .filter(|name| !name.is_empty())
        .unwrap_or(path)
        .to_string()
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicBool, Ordering};

    use tempfile::TempDir;

    use super::*;
    use crate::capability_registry::NoopProgressSink;
    use crate::index::SnapshotIndexBuilder;
    use crate::model::ScanStats;
    use crate::CapabilityProgressSink;

    struct CancellingSink {
        cancelled: AtomicBool,
    }

    impl CancellingSink {
        fn new() -> Self {
            Self {
                cancelled: AtomicBool::new(false),
            }
        }
    }

    impl CapabilityProgressSink for CancellingSink {
        fn report(
            &self,
            _phase: CapabilityAnalysisPhase,
            _processed: u64,
            _total: u64,
            _current_path: Option<String>,
        ) {
            self.cancelled.store(true, Ordering::Relaxed);
        }

        fn is_cancelled(&self) -> bool {
            self.cancelled.load(Ordering::Relaxed)
        }
    }

    fn write(temp: &TempDir, relative: &str, bytes: &[u8]) -> String {
        let path = temp.path().join(relative);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, bytes).unwrap();
        path.to_string_lossy().to_string()
    }

    fn index_for(root: &str, files: &[String]) -> SnapshotIndex {
        let mut builder = SnapshotIndexBuilder::new(root);
        for path in files {
            let size = std::fs::metadata(path).unwrap().len();
            builder.record_file_size(path, size);
        }
        builder.finish(
            "snapshot-1".to_string(),
            1,
            1,
            "Done".to_string(),
            ScanStats::default(),
        )
    }

    fn analyze(
        analyzer: &DuplicateFileAnalyzer,
        index: &SnapshotIndex,
        root: &str,
    ) -> CapabilityAnalysisResult {
        analyzer
            .analyze(
                index,
                root,
                &AnalysisOptions::default(),
                &NoopProgressSink,
            )
            .expect("duplicate analysis")
    }

    #[test]
    fn groups_different_name_same_content_and_keeps_one() {
        let temp = TempDir::new().unwrap();
        let root = temp.path().to_string_lossy().to_string();
        let a = write(&temp, "src/a.txt", b"identical content here");
        let b = write(&temp, "backup/b.txt", b"identical content here");
        let index = index_for(&root, &[a.clone(), b.clone()]);
        let analyzer = DuplicateFileAnalyzer::new(vec![]);

        let result = analyze(&analyzer, &index, &root);

        assert_eq!(result.summary.item_count, 2);
        assert_eq!(result.summary.kept_count, 1);
        assert_eq!(result.summary.review_count, 1);
        assert_eq!(result.deletion_plan.target_count, 1);
        let kept = result
            .groups
            .iter()
            .flat_map(|g| g.items.iter())
            .find(|item| item.recommendation == Recommendation::Keep)
            .unwrap();
        // Deterministic keep rule: same depth → lexicographically smaller path.
        assert_eq!(kept.path, b);
        let review = result
            .groups
            .iter()
            .flat_map(|g| g.items.iter())
            .find(|item| item.recommendation == Recommendation::ReviewNeeded)
            .unwrap();
        assert_eq!(review.path, a);
        assert!(review.evidence.iter().any(|e| e.starts_with("full_hash:")));
        assert!(review.evidence.iter().any(|e| e.starts_with("size_bytes:")));
    }

    #[test]
    fn same_name_different_content_is_not_a_duplicate() {
        let temp = TempDir::new().unwrap();
        let root = temp.path().to_string_lossy().to_string();
        let a = write(&temp, "one/same.txt", b"content one");
        let b = write(&temp, "two/same.txt", b"content two");
        let index = index_for(&root, &[a, b]);
        let analyzer = DuplicateFileAnalyzer::new(vec![]);

        let result = analyze(&analyzer, &index, &root);

        assert_eq!(result.summary.item_count, 0);
        assert_eq!(result.deletion_plan.target_count, 0);
    }

    #[test]
    fn partial_hash_narrows_files_that_differ_beyond_the_prefix() {
        let temp = TempDir::new().unwrap();
        let root = temp.path().to_string_lossy().to_string();
        let mut prefix = vec![b'a'; 8192];
        prefix.extend(vec![b'x'; 16]);
        let a = write(&temp, "one/large.bin", &prefix);
        let mut prefix_b = vec![b'a'; 8192];
        prefix_b.extend(vec![b'y'; 16]);
        let b = write(&temp, "two/large.bin", &prefix_b);
        let index = index_for(&root, &[a, b]);
        let analyzer = DuplicateFileAnalyzer::new(vec![]);

        // First 8 KiB identical → same partial hash; full hash differs →
        // no duplicate set.
        let result = analyze(&analyzer, &index, &root);
        assert_eq!(result.summary.item_count, 0);
    }

    #[test]
    fn zero_byte_files_and_singletons_are_preserved_without_groups() {
        let temp = TempDir::new().unwrap();
        let root = temp.path().to_string_lossy().to_string();
        let empty_a = write(&temp, "a/empty.txt", b"");
        let empty_b = write(&temp, "b/empty.txt", b"");
        let unique = write(&temp, "c/unique.txt", b"only one");
        let index = index_for(&root, &[empty_a, empty_b, unique]);
        let analyzer = DuplicateFileAnalyzer::new(vec![]);

        let result = analyze(&analyzer, &index, &root);

        assert_eq!(result.summary.item_count, 0);
        assert_eq!(result.deletion_plan.target_count, 0);
    }

    #[test]
    fn protected_paths_are_blocked_not_hashed() {
        let temp = TempDir::new().unwrap();
        let root = temp.path().to_string_lossy().to_string();
        let protected = write(&temp, "System/a.bin", b"secret bytes");
        let unprotected = write(&temp, "User/a.bin", b"secret bytes");
        let index = index_for(&root, &[protected.clone(), unprotected]);
        let analyzer = DuplicateFileAnalyzer::new(vec![format!("{root}/System")]);

        let result = analyze(&analyzer, &index, &root);

        assert_eq!(result.summary.item_count, 0);
        assert_eq!(result.deletion_plan.blocked_targets, vec![protected]);
    }

    #[test]
    fn cancellation_aborts_before_emitting_targets() {
        let temp = TempDir::new().unwrap();
        let root = temp.path().to_string_lossy().to_string();
        let a = write(&temp, "one/a.bin", b"some data here");
        let b = write(&temp, "two/b.bin", b"some data here");
        let index = index_for(&root, &[a, b]);
        let analyzer = DuplicateFileAnalyzer::new(vec![]);
        let sink = CancellingSink::new();

        let error = analyzer
            .analyze(
                &index,
                &root,
                &AnalysisOptions::default(),
                &sink,
            )
            .expect_err("cancelled analysis must fail");
        assert_eq!(error.code, "cancelled");
    }
}
