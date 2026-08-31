use std::collections::HashMap;

use crate::ai_candidates::ai_cleanup_hint_for_path;
use crate::capability::{
    AnalysisConfidence, AnalysisGroup, AnalysisItem, AnalysisOptions, AnalysisPreview,
    AnalysisSummary, Capability, CapabilityAnalysisResult, CapabilityLevel, DeletionPlan,
    Recommendation,
};
use crate::capability_registry::{CapabilityAnalysisError, CapabilityAnalyzer};
use crate::classify::Classifier;
use crate::index::{path_is_at_or_below, CapabilityFileRecord, SnapshotIndex};
use crate::model::EntryCategory;
use crate::CAPABILITY_SCHEMA_VERSION;

pub const CLEANUP_CANDIDATES_ANALYZER_VERSION: &str = "cleanup_candidates-v1";

const CLEANUP_CATEGORIES: [&str; 3] = ["Cache", "Temp", "BuildArtifact"];

/// Evidence-based cleanup analysis for cache / temp / build-artifact files.
/// Reuses `Classifier` and the AI cleanup hints; protected paths are blocked;
/// directory names never become deletion targets (only member files do).
pub struct CleanupCandidateAnalyzer {
    classifier: Classifier,
}

impl CleanupCandidateAnalyzer {
    pub fn new(classifier: Classifier) -> Self {
        Self { classifier }
    }
}

impl CapabilityAnalyzer for CleanupCandidateAnalyzer {
    fn capability(&self) -> Capability {
        Capability::CleanupCandidates
    }

    fn analyze(
        &self,
        index: &SnapshotIndex,
        normalized_root: &str,
        options: &AnalysisOptions,
    ) -> Result<CapabilityAnalysisResult, CapabilityAnalysisError> {
        let page_size = options.page_size as usize;
        let mut items = Vec::new();
        let mut blocked_targets = Vec::new();
        let mut target_paths = Vec::new();
        let mut target_bytes = 0u64;
        let mut next_cursor = None;
        let mut truncated = false;
        let mut file_cursor = options.cursor.clone();
        let mut last_consumed: Option<String> = None;

        loop {
            let (records, next) = index.capability_files_page(file_cursor.as_deref(), page_size);
            let mut stop = false;
            for record in records {
                if items.len() >= page_size {
                    next_cursor = last_consumed.clone();
                    truncated = true;
                    stop = true;
                    break;
                }
                last_consumed = Some(record.path.clone());
                if !path_is_at_or_below(&record.path, normalized_root) {
                    continue;
                }
                let hint = ai_cleanup_hint_for_path(&record.path);
                let category = cleanup_category(&record);
                let classified = self
                    .classifier
                    .classify_path(&record.path, record.size_bytes, false, "cleanup");
                if matches!(classified.as_ref().map(|e| e.category), Some(EntryCategory::System)) {
                    blocked_targets.push(record.path);
                    continue;
                }
                if category.is_none() && hint.is_none() {
                    continue;
                }

                let mut evidence = Vec::new();
                if let Some(category) = category {
                    evidence.push(format!("category:{category}"));
                }
                if let Some(hint) = hint.as_ref() {
                    evidence.push(format!("hint:{}", hint.source));
                    evidence.push(format!("retention_days:{}", hint.retention_days));
                }
                match record.modified_at_ms {
                    Some(modified_at_ms) => {
                        evidence.push(format!("modified_at_ms:{modified_at_ms}"));
                    }
                    None => evidence.push("modified_at:unavailable".to_string()),
                }

                let (recommendation, confidence, reason, deletable) =
                    match (category, hint.as_ref().map(|h| h.source)) {
                        (Some(category), _) if category == "BuildArtifact" => (
                            Recommendation::SafeToRemove,
                            AnalysisConfidence::High,
                            "cleanup:build_artifact".to_string(),
                            true,
                        ),
                        (Some(_), _) => (
                            Recommendation::SafeToRemove,
                            AnalysisConfidence::High,
                            "cleanup:cache_or_temp".to_string(),
                            true,
                        ),
                        (None, Some("ai_generated_output")) => (
                            Recommendation::ReviewNeeded,
                            AnalysisConfidence::Medium,
                            "cleanup:ai_generated_output".to_string(),
                            false,
                        ),
                        (None, Some(_)) => (
                            Recommendation::ReviewNeeded,
                            AnalysisConfidence::Medium,
                            "cleanup:ai_tool_hint".to_string(),
                            false,
                        ),
                        _ => (
                            Recommendation::ReviewNeeded,
                            AnalysisConfidence::Low,
                            "cleanup:unclassified".to_string(),
                            false,
                        ),
                    };

                if deletable {
                    target_paths.push(record.path.clone());
                    target_bytes += record.size_bytes;
                }
                items.push(AnalysisItem {
                    id: record.path.clone(),
                    path: record.path.clone(),
                    display_name: name_of(&record.path),
                    size_bytes: record.size_bytes,
                    is_directory: false,
                    modified_at_ms: record.modified_at_ms,
                    recommendation,
                    confidence,
                    reason,
                    evidence,
                    delete_target: if deletable {
                        Some(record.path.clone())
                    } else {
                        None
                    },
                    preview: Some(AnalysisPreview {
                        kind: "file".to_string(),
                        locatable: true,
                    }),
                });
            }
            if stop {
                break;
            }
            match next {
                Some(cursor) => file_cursor = Some(cursor),
                None => break,
            }
        }

        let groups = group_items(&items, normalized_root);
        let item_count = items.len() as u64;
        let total_bytes = items.iter().map(|item| item.size_bytes).sum();
        let safe_count = items
            .iter()
            .filter(|item| item.recommendation == Recommendation::SafeToRemove)
            .count() as u64;
        Ok(CapabilityAnalysisResult {
            schema_version: CAPABILITY_SCHEMA_VERSION,
            capability: Capability::CleanupCandidates,
            snapshot_id: index.snapshot_id.clone(),
            root_path: normalized_root.to_string(),
            analyzer_version: CLEANUP_CANDIDATES_ANALYZER_VERSION.to_string(),
            generated_at_ms: index.scanned_at_ms,
            capability_level: CapabilityLevel::FullPath,
            summary: AnalysisSummary {
                item_count,
                total_bytes,
                safe_count,
                review_count: item_count - safe_count,
                kept_count: 0,
                truncated,
            },
            groups,
            next_cursor,
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

fn cleanup_category(record: &CapabilityFileRecord) -> Option<&'static str> {
    record
        .category
        .as_deref()
        .and_then(|category| CLEANUP_CATEGORIES.iter().copied().find(|c| *c == category))
}

fn group_items(items: &[AnalysisItem], normalized_root: &str) -> Vec<AnalysisGroup> {
    let mut groups: Vec<AnalysisGroup> = Vec::new();
    let mut by_key: HashMap<String, usize> = HashMap::new();
    for item in items {
        let dir = direct_child_of(&item.path, normalized_root);
        let key = format!("group:{dir}");
        let index = match by_key.get(&key) {
            Some(&index) => index,
            None => {
                let title = name_of(&dir);
                groups.push(AnalysisGroup::new(key.clone(), dir, title, Vec::new()));
                let index = groups.len() - 1;
                by_key.insert(key, index);
                index
            }
        };
        groups[index].items.push(item.clone());
    }
    for group in &mut groups {
        group.items.sort_by(|a, b| {
            b.size_bytes
                .cmp(&a.size_bytes)
                .then_with(|| a.path.cmp(&b.path))
        });
        let item_count = group.items.len() as u64;
        group.item_count = item_count;
        group.total_bytes = group.items.iter().map(|item| item.size_bytes).sum();
        group.safe_count = group
            .items
            .iter()
            .filter(|item| item.recommendation == Recommendation::SafeToRemove)
            .count() as u64;
        group.review_count = group
            .items
            .iter()
            .filter(|item| item.recommendation == Recommendation::ReviewNeeded)
            .count() as u64;
        group.kept_count = group
            .items
            .iter()
            .filter(|item| item.recommendation == Recommendation::Keep)
            .count() as u64;
        group.default_expanded = (1..=2).contains(&item_count);
    }
    groups
}

fn direct_child_of(path: &str, root: &str) -> String {
    let path = path.replace('\\', "/");
    let root = root.replace('\\', "/");
    let root = root.trim_end_matches('/');
    let prefix = if root.is_empty() { "/" } else { root };
    let rest = path
        .strip_prefix(prefix)
        .map(|rest| rest.trim_start_matches('/'))
        .unwrap_or(path.as_str());
    if rest.is_empty() || !rest.contains('/') {
        return if root.is_empty() { "/".to_string() } else { root.to_string() };
    }
    let child = rest.split('/').next().unwrap_or("");
    format!("{root}/{child}")
}

fn name_of(path: &str) -> String {
    path.rsplit('/')
        .next()
        .filter(|name| !name.is_empty())
        .unwrap_or(path)
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::index::SnapshotIndexBuilder;
    use crate::model::{EntryCategory, RiskLevel, ScanStats, SourceType, StorageEntry};

    fn entry(path: &str, size: u64, category: EntryCategory, deletable: bool) -> StorageEntry {
        StorageEntry {
            id: format!("id:{path}"),
            display_name: path.rsplit('/').next().unwrap_or(path).to_string(),
            path_or_uri: path.to_string(),
            size_bytes: size,
            category,
            risk_level: RiskLevel::Low,
            source_type: SourceType::File,
            deletable,
            reason: "test".to_string(),
            modified_at_ms: None,
        }
    }

    fn analyzer(protected: &[&str]) -> CleanupCandidateAnalyzer {
        CleanupCandidateAnalyzer::new(Classifier::new(
            protected.iter().map(|p| p.to_string()).collect(),
        ))
    }

    fn fixture_index() -> SnapshotIndex {
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.ensure_dir("/root/project");
        builder.ensure_dir("/root/project/node_modules");
        builder.insert_entry(entry(
            "/root/project/node_modules/pkg/index.js",
            3_000_000,
            EntryCategory::BuildArtifact,
            true,
        ));
        builder.insert_entry(entry(
            "/root/project/cache.bin",
            2_000_000,
            EntryCategory::Cache,
            true,
        ));
        builder.insert_entry(entry(
            "/root/tmp.log",
            1_000_000,
            EntryCategory::Temp,
            true,
        ));
        builder.insert_entry(entry(
            "/root/project/source.rs",
            500_000,
            EntryCategory::Unknown,
            false,
        ));
        // AI tool cache path that generic cache rules may not classify.
        builder.record_file_size("/root/project/.cache/cursor/CachedData/x.bin", 900_000);
        builder.finish(
            "snapshot-1".to_string(),
            1,
            1,
            "Done".to_string(),
            ScanStats::default(),
        )
    }

    fn analyze(
        analyzer: &CleanupCandidateAnalyzer,
        index: &SnapshotIndex,
    ) -> CapabilityAnalysisResult {
        analyzer
            .analyze(index, "/root", &AnalysisOptions::default())
            .expect("cleanup analysis")
    }

    #[test]
    fn cache_temp_and_build_artifact_are_safe_targets_with_evidence() {
        let result = analyze(&analyzer(&[]), &fixture_index());
        assert_eq!(result.summary.item_count, 4);
        assert_eq!(result.summary.safe_count, 3);
        assert_eq!(result.deletion_plan.target_count, 3);
        assert_eq!(result.deletion_plan.target_bytes, 6_000_000);
        assert!(result.deletion_plan.requires_confirmation);

        let node_modules = result
            .groups
            .iter()
            .find(|g| g.group_path == "/root/project")
            .expect("project group");
        let build = node_modules
            .items
            .iter()
            .find(|item| item.path.ends_with("index.js"))
            .expect("build artifact item");
        assert_eq!(build.recommendation, Recommendation::SafeToRemove);
        assert!(build.evidence.iter().any(|e| e == "category:BuildArtifact"));
        assert!(build.evidence.iter().any(|e| e == "modified_at:unavailable"));
        assert_eq!(build.delete_target.as_deref(), Some(build.path.as_str()));
    }

    #[test]
    fn ai_tool_cache_paths_are_flagged_with_hint_evidence() {
        let result = analyze(&analyzer(&[]), &fixture_index());
        let ai_item = result
            .groups
            .iter()
            .flat_map(|g| g.items.iter())
            .find(|item| item.path.contains(".cache/cursor"))
            .expect("ai tool cache item");
        assert!(ai_item.evidence.iter().any(|e| e.starts_with("hint:")));
        assert!(ai_item.evidence.iter().any(|e| e.starts_with("retention_days:")));
    }

    #[test]
    fn protected_paths_are_blocked_not_targeted() {
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.ensure_dir("/root/System");
        builder.insert_entry(entry(
            "/root/System/Library/Caches/secret.bin",
            5_000_000,
            EntryCategory::Cache,
            true,
        ));
        let index = builder.finish(
            "snapshot-1".to_string(),
            1,
            1,
            "Done".to_string(),
            ScanStats::default(),
        );

        let result = analyze(&analyzer(&["/root/System"]), &index);
        assert_eq!(result.summary.item_count, 0);
        assert_eq!(result.deletion_plan.target_count, 0);
        assert_eq!(result.deletion_plan.blocked_targets.len(), 1);
        assert_eq!(
            result.deletion_plan.blocked_targets[0],
            "/root/System/Library/Caches/secret.bin"
        );
    }

    #[test]
    fn parent_directory_never_becomes_a_target() {
        let result = analyze(&analyzer(&[]), &fixture_index());
        let node_modules_dir = "/root/project/node_modules";
        assert!(
            result
                .deletion_plan
                .targets
                .iter()
                .all(|target| target != node_modules_dir),
            "directory names must resolve to member files"
        );
        assert!(
            result
                .deletion_plan
                .targets
                .iter()
                .any(|target| target.starts_with(node_modules_dir))
        );
    }

    #[test]
    fn unclassified_ordinary_files_are_not_cleanup_candidates() {
        let result = analyze(&analyzer(&[]), &fixture_index());
        assert!(
            result
                .groups
                .iter()
                .flat_map(|g| g.items.iter())
                .all(|item| item.path != "/root/project/source.rs")
        );
    }
}
