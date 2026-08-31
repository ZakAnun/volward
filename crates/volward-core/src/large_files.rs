use std::collections::HashMap;

use crate::capability::{
    AnalysisConfidence, AnalysisGroup, AnalysisItem, AnalysisOptions, AnalysisPreview,
    AnalysisSummary, Capability, CapabilityAnalysisResult, CapabilityLevel, DeletionPlan,
    Recommendation,
};
use crate::capability_registry::{CapabilityAnalysisError, CapabilityAnalyzer};
use crate::index::{path_is_at_or_below, CapabilityFileRecord, SnapshotIndex};
use crate::CAPABILITY_SCHEMA_VERSION;

pub const LARGE_FILES_ANALYZER_VERSION: &str = "large_files-v1";

/// Index-backed large-file analysis. Only reads path and size records; never
/// recommends automatic deletion.
#[derive(Debug, Clone, Copy, Default)]
pub struct LargeFileAnalyzer;

impl CapabilityAnalyzer for LargeFileAnalyzer {
    fn capability(&self) -> Capability {
        Capability::LargeFiles
    }

    fn analyze(
        &self,
        index: &SnapshotIndex,
        normalized_root: &str,
        options: &AnalysisOptions,
    ) -> Result<CapabilityAnalysisResult, CapabilityAnalysisError> {
        let threshold = options.large_file_threshold_bytes;
        let page_size = options.page_size as usize;
        let mut items = Vec::new();
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
                if record.size_bytes < threshold {
                    continue;
                }
                if !path_is_at_or_below(&record.path, normalized_root) {
                    continue;
                }
                items.push(item_for(record));
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
        Ok(CapabilityAnalysisResult {
            schema_version: CAPABILITY_SCHEMA_VERSION,
            capability: Capability::LargeFiles,
            snapshot_id: index.snapshot_id.clone(),
            root_path: normalized_root.to_string(),
            analyzer_version: LARGE_FILES_ANALYZER_VERSION.to_string(),
            generated_at_ms: index.scanned_at_ms,
            capability_level: CapabilityLevel::FullPath,
            summary: AnalysisSummary {
                item_count,
                total_bytes,
                safe_count: 0,
                review_count: item_count,
                kept_count: 0,
                truncated,
            },
            groups,
            next_cursor,
            deletion_plan: DeletionPlan {
                snapshot_id: index.snapshot_id.clone(),
                target_count: 0,
                target_bytes: 0,
                targets: vec![],
                blocked_targets: vec![],
                requires_confirmation: true,
            },
            warnings: vec![],
        })
    }
}

fn item_for(record: CapabilityFileRecord) -> AnalysisItem {
    let path = record.path;
    AnalysisItem {
        id: path.clone(),
        path: path.clone(),
        display_name: name_of(&path),
        size_bytes: record.size_bytes,
        is_directory: false,
        modified_at_ms: None,
        recommendation: Recommendation::ReviewNeeded,
        confidence: AnalysisConfidence::Medium,
        reason: "large_file".to_string(),
        evidence: vec![format!("size_bytes:{}", record.size_bytes)],
        delete_target: None,
        preview: Some(AnalysisPreview {
            kind: "file".to_string(),
            locatable: true,
        }),
    }
}

fn group_items(items: &[AnalysisItem], normalized_root: &str) -> Vec<AnalysisGroup> {
    let mut groups: Vec<AnalysisGroup> = Vec::new();
    let mut by_key: HashMap<String, usize> = HashMap::new();
    for item in items {
        let dir = direct_child_of(&item.path, normalized_root);
        let bucket = extension_bucket(&item.path);
        let key = format!("group:{dir}/{bucket}");
        let index = match by_key.get(&key) {
            Some(&index) => index,
            None => {
                let dir_name = name_of(&dir);
                let title = if bucket == "general" {
                    dir_name
                } else {
                    format!("{dir_name} · {bucket}")
                };
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

/// First grouping key: the root's direct child (second path level). Files
/// directly under the root group under the root itself.
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

fn extension_bucket(path: &str) -> String {
    let name = name_of(path);
    match name.rsplit_once('.') {
        Some((_, ext)) if !ext.is_empty() => ext.to_ascii_lowercase(),
        _ => "general".to_string(),
    }
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
    use crate::model::ScanStats;

    fn fixture_index() -> SnapshotIndex {
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.ensure_dir("/root/project");
        builder.ensure_dir("/root/project/build");
        builder.ensure_dir("/root/media");
        builder.record_file_size("/root/project/build/a.zip", 60_000_000);
        builder.record_file_size("/root/project/build/b.zip", 55_000_000);
        builder.record_file_size("/root/project/readme.md", 1_000);
        builder.record_file_size("/root/media/photo.jpg", 120_000_000);
        builder.record_file_size("/root/top.bin", 200_000_000);
        builder.record_file_size("/elsewhere/not-in-root.bin", 300_000_000);
        builder.finish(
            "snapshot-1".to_string(),
            1,
            1,
            "Done".to_string(),
            ScanStats::default(),
        )
    }

    fn analyze(index: &SnapshotIndex, options: &AnalysisOptions) -> CapabilityAnalysisResult {
        LargeFileAnalyzer
            .analyze(index, "/root", options)
            .expect("large file analysis")
    }

    #[test]
    fn default_50mb_threshold_and_root_containment() {
        let result = analyze(&fixture_index(), &AnalysisOptions::default());

        // 60MB, 55MB, 120MB, 200MB qualify; 1KB readme and the
        // /elsewhere file (outside the root) do not.
        assert_eq!(result.summary.item_count, 4);
        assert_eq!(result.summary.review_count, 4);
        assert_eq!(result.summary.safe_count, 0);
        assert_eq!(result.summary.total_bytes, 435_000_000);
        assert!(result.groups.iter().all(|group| group.group_path.starts_with("/root")));
        assert!(result.groups.iter().all(|group| group.items.len() >= 1));
    }

    #[test]
    fn all_standard_presets_filter_correctly() {
        let index = fixture_index();
        for (preset, bytes, expected) in [
            (crate::LargeFileThresholdPreset::Mb50, 50_000_000, 4),
            (crate::LargeFileThresholdPreset::Mb100, 100_000_000, 2),
            (crate::LargeFileThresholdPreset::Gb1, 1_000_000_000, 0),
            (crate::LargeFileThresholdPreset::Gb5, 5_000_000_000, 0),
        ] {
            let options = AnalysisOptions {
                large_file_threshold_preset: preset,
                large_file_threshold_bytes: bytes,
                ..AnalysisOptions::default()
            };
            let result = analyze(&index, &options);
            assert_eq!(result.summary.item_count, expected, "preset {preset:?}");
        }
    }

    #[test]
    fn items_descend_by_size_within_groups() {
        let result = analyze(&fixture_index(), &AnalysisOptions::default());
        for group in &result.groups {
            let sizes: Vec<u64> = group.items.iter().map(|item| item.size_bytes).collect();
            let mut sorted = sizes.clone();
            sorted.sort_unstable_by(|a, b| b.cmp(a));
            assert_eq!(sizes, sorted, "group {}", group.group_path);
        }
    }

    #[test]
    fn groups_by_direct_child_directory_and_file_type() {
        let result = analyze(&fixture_index(), &AnalysisOptions::default());
        let paths: Vec<&String> = result.groups.iter().map(|g| &g.group_path).collect();
        assert!(paths.contains(&&"/root/project".to_string()));
        assert!(paths.contains(&&"/root/media".to_string()));
        assert!(paths.contains(&&"/root".to_string()));

        let project_zip = result
            .groups
            .iter()
            .find(|g| g.group_path == "/root/project" && g.group_id.ends_with("/zip"))
            .expect("zip bucket group");
        assert_eq!(project_zip.items.len(), 2);
        assert_eq!(project_zip.title, "project · zip");
        assert!(project_zip.items.iter().all(|item| item.reason == "large_file"));
    }

    #[test]
    fn cursor_continuation_returns_all_items_without_overlap() {
        let index = fixture_index();
        let options = AnalysisOptions {
            page_size: 2,
            ..AnalysisOptions::default()
        };
        let first = analyze(&index, &options);
        assert_eq!(first.summary.item_count, 2);
        assert!(first.summary.truncated);
        let cursor = first.next_cursor.expect("cursor");

        let second = analyze(
            &index,
            &AnalysisOptions {
                page_size: 2,
                cursor: Some(cursor),
                ..AnalysisOptions::default()
            },
        );
        assert_eq!(second.summary.item_count, 2);

        let mut paths: Vec<String> = first
            .groups
            .iter()
            .flat_map(|g| g.items.iter())
            .map(|item| item.path.clone())
            .collect();
        paths.extend(
            second
                .groups
                .iter()
                .flat_map(|g| g.items.iter())
                .map(|item| item.path.clone()),
        );
        assert_eq!(paths.len(), 4);
        let unique: std::collections::HashSet<&String> = paths.iter().collect();
        assert_eq!(unique.len(), 4, "pages must not overlap");
    }

    #[test]
    fn default_expanded_only_for_small_groups() {
        let index = fixture_index();
        let result = analyze(&index, &AnalysisOptions::default());
        for group in &result.groups {
            let expected = (1..=2).contains(&group.items.len());
            assert_eq!(group.default_expanded, expected, "group {}", group.group_path);
        }
    }
}
