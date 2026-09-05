use std::collections::HashMap;

use serde::Serialize;

use crate::index::SnapshotIndex;
use crate::os_knowledge::OsKnowledgeBase;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum AiCoverageRowKind {
    File,
    Group,
}

#[derive(Debug, Clone, Serialize)]
pub struct AiCoverageRow {
    pub row_index: u64,
    pub kind: AiCoverageRowKind,
    pub path: String,
    pub size_bytes: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub member_count: Option<u64>,
}

pub const AI_COVERAGE_PLAN_VERSION: u64 = 1;

#[derive(Debug, Clone)]
pub struct AiCoveragePlan {
    pub plan_version: u64,
    pub snapshot_id: String,
    pub root_path: String,
    pub total_unclassified: u64,
    pub pre_classified_count: u64,
    pub group_rows: u64,
    pub file_rows: u64,
    pub rows: Vec<AiCoverageRow>,
}

impl AiCoveragePlan {
    pub fn page(&self, cursor: u64, page_size: usize) -> (Vec<AiCoverageRow>, Option<u64>) {
        if page_size == 0 || self.rows.is_empty() {
            return (Vec::new(), None);
        }
        let start = (cursor as usize).min(self.rows.len());
        let end = (start + page_size).min(self.rows.len());
        let next = if end < self.rows.len() {
            Some(end as u64)
        } else {
            None
        };
        (self.rows[start..end].to_vec(), next)
    }
}

fn group_key_for_path(path: &str) -> Option<String> {
    let normalized = path.replace('\\', "/");
    let hint = crate::ai_candidates::ai_cleanup_hint_for_path(&normalized)?;
    match hint.source {
        "system_temp" => parent_dir(&normalized),
        "ai_tool_cache" => crate::ai_candidates::ai_tool_group_root(&normalized),
        _ => None,
    }
}

fn parent_dir(path: &str) -> Option<String> {
    let normalized = path.trim_end_matches('/');
    if normalized.is_empty() {
        return None;
    }
    match normalized.rfind('/') {
        Some(0) => Some("/".to_string()),
        Some(idx) if idx > 0 => Some(normalized[..idx].to_string()),
        _ => None,
    }
}

pub fn build_ai_coverage_plan(index: &SnapshotIndex, kb: &OsKnowledgeBase) -> AiCoveragePlan {
    let classified = index.classified_paths();
    let mut group_sizes: HashMap<String, u64> = HashMap::new();
    let mut group_counts: HashMap<String, u64> = HashMap::new();
    let mut file_rows = Vec::<(String, u64)>::new();
    let mut pre_classified_count = 0u64;

    for (path, size_bytes) in index.unclassified_files() {
        if classified.contains(&path) {
            continue;
        }
        if kb.classify_path(&path).is_some() {
            pre_classified_count += 1;
            continue;
        }
        if let Some(group) = group_key_for_path(&path) {
            *group_sizes.entry(group.clone()).or_insert(0) += size_bytes;
            *group_counts.entry(group).or_insert(0) += 1;
        } else {
            file_rows.push((path, size_bytes));
        }
    }

    let mut rows = Vec::with_capacity(group_sizes.len() + file_rows.len());
    for (path, size_bytes) in group_sizes {
        let member_count = group_counts.remove(&path).unwrap_or(0);
        rows.push(AiCoverageRow {
            row_index: 0,
            kind: AiCoverageRowKind::Group,
            path,
            size_bytes,
            member_count: Some(member_count),
        });
    }
    for (path, size_bytes) in file_rows {
        rows.push(AiCoverageRow {
            row_index: 0,
            kind: AiCoverageRowKind::File,
            path,
            size_bytes,
            member_count: None,
        });
    }
    rows.sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes).then(a.path.cmp(&b.path)));
    for (index, row) in rows.iter_mut().enumerate() {
        row.row_index = index as u64;
    }

    let total_unclassified = rows
        .iter()
        .map(|row| row.member_count.unwrap_or(1))
        .sum::<u64>();
    let group_rows = rows
        .iter()
        .filter(|row| row.kind == AiCoverageRowKind::Group)
        .count() as u64;
    let file_rows_count = rows.len() as u64 - group_rows;

    AiCoveragePlan {
        plan_version: AI_COVERAGE_PLAN_VERSION,
        snapshot_id: index.snapshot_id.clone(),
        root_path: index.root_path.clone(),
        total_unclassified,
        pre_classified_count,
        group_rows,
        file_rows: file_rows_count,
        rows,
    }
}

pub fn coverage_group_member_paths(
    index: &SnapshotIndex,
    kb: &OsKnowledgeBase,
    group_path: &str,
) -> Vec<(String, u64)> {
    let classified = index.classified_paths();
    index
        .unclassified_files()
        .into_iter()
        .filter(|(path, _)| {
            !classified.contains(path)
                && kb.classify_path(path).is_none()
                && group_key_for_path(path).as_deref() == Some(group_path)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::index::SnapshotIndexBuilder;
    use crate::model::ScanStats;
    use crate::os_knowledge::OsKnowledgeBase;

    fn kb_empty() -> OsKnowledgeBase {
        OsKnowledgeBase::from_yaml("version: 1\nmacos: []\nwindows: []\nlinux: []", "macos")
            .unwrap()
    }

    fn build_index(root: &str, files: &[(&str, u64)]) -> SnapshotIndex {
        let mut builder = SnapshotIndexBuilder::new(root);
        for (path, size) in files {
            builder.record_file_size(path, *size);
        }
        builder.finish(
            "snap-plan".to_string(),
            1,
            1,
            "Done".to_string(),
            ScanStats::default(),
        )
    }

    #[test]
    fn plan_covers_every_unclassified_file_exactly_once() {
        let root = "/Users/x";
        let files = [
            ("/Users/x/one.bin", 100u64),
            ("/Users/x/Library/Caches/cursor/a.bin", 10u64),
            ("/Users/x/Library/Caches/cursor/b.bin", 20u64),
            ("/Users/x/Documents/notes.txt", 30u64),
        ];
        let index = build_index(root, &files);
        let plan = build_ai_coverage_plan(&index, &kb_empty());

        assert_eq!(plan.total_unclassified, 4);
        assert_eq!(plan.group_rows, 1);
        assert_eq!(plan.file_rows, 2);
        assert_eq!(plan.rows.len(), 3);
        let group = plan
            .rows
            .iter()
            .find(|r| r.kind == AiCoverageRowKind::Group)
            .expect("cursor group");
        assert_eq!(group.path, "/Users/x/Library/Caches/cursor");
        assert_eq!(group.size_bytes, 30);
        assert_eq!(group.member_count, Some(2));
    }

    #[test]
    fn plan_skips_kb_preclassified_files_and_counts_them() {
        let root = "/Users/x";
        let yaml = include_str!("../../../rules/os_knowledge.yaml");
        let kb = OsKnowledgeBase::from_yaml(yaml, "macos").unwrap();
        let files = [
            ("/Users/x/project/node_modules/lodash/index.js", 5000u64),
            ("/Users/x/plain.bin", 10u64),
        ];
        let index = build_index(root, &files);
        let plan = build_ai_coverage_plan(&index, &kb);
        assert_eq!(plan.pre_classified_count, 1);
        assert_eq!(plan.total_unclassified, 1);
        assert_eq!(plan.rows.len(), 1);
        assert_eq!(plan.rows[0].path, "/Users/x/plain.bin");
    }

    #[test]
    fn rows_sort_by_size_desc_then_path_asc() {
        let root = "/Users/x";
        let files = [
            ("/Users/x/a.bin", 1u64),
            ("/Users/x/b.bin", 10u64),
            ("/Users/x/Library/Caches/cursor/one", 100u64),
            ("/Users/x/Library/Caches/cursor/two", 100u64),
        ];
        let index = build_index(root, &files);
        let plan = build_ai_coverage_plan(&index, &kb_empty());
        let paths: Vec<&str> = plan.rows.iter().map(|r| r.path.as_str()).collect();
        assert_eq!(
            paths,
            vec![
                "/Users/x/Library/Caches/cursor",
                "/Users/x/b.bin",
                "/Users/x/a.bin",
            ]
        );
        assert_eq!(plan.rows[0].member_count, Some(2));
    }

    #[test]
    fn group_member_resolution_returns_all_members_without_cap() {
        let root = "/Users/x";
        let mut files = Vec::new();
        for i in 0..250 {
            files.push((
                format!("/Users/x/Library/Caches/cursor/f{i}.dat"),
                (i + 1) as u64,
            ));
        }
        files.push((
            "/Users/x/Library/Caches/cursor/Code/nested.dat".to_string(),
            1,
        ));
        let refs: Vec<(&str, u64)> = files.iter().map(|(p, s)| (p.as_str(), *s)).collect();
        let index = build_index(root, &refs);
        let kb = kb_empty();
        let members = coverage_group_member_paths(&index, &kb, "/Users/x/Library/Caches/cursor");
        assert_eq!(members.len(), 251);
    }

    #[test]
    fn page_slices_and_reports_next_cursor() {
        let rows: Vec<AiCoverageRow> = (0..5)
            .map(|i| AiCoverageRow {
                row_index: i,
                kind: AiCoverageRowKind::File,
                path: format!("/f{i}"),
                size_bytes: 10,
                member_count: None,
            })
            .collect();
        let plan = AiCoveragePlan {
            plan_version: AI_COVERAGE_PLAN_VERSION,
            snapshot_id: "s".to_string(),
            root_path: "/".to_string(),
            total_unclassified: 5,
            pre_classified_count: 0,
            group_rows: 0,
            file_rows: 5,
            rows,
        };
        let (first, next) = plan.page(0, 2);
        assert_eq!(first.len(), 2);
        assert_eq!(first[0].path, "/f0");
        assert_eq!(next, Some(2));
        let (second, done) = plan.page(2, 2);
        assert_eq!(second.len(), 2);
        assert_eq!(done, Some(4));
        let (last, none) = plan.page(4, 2);
        assert_eq!(last.len(), 1);
        assert_eq!(none, None);
    }

    #[test]
    fn page_out_of_range_returns_empty_without_looping() {
        let plan = AiCoveragePlan {
            plan_version: AI_COVERAGE_PLAN_VERSION,
            snapshot_id: "s".to_string(),
            root_path: "/".to_string(),
            total_unclassified: 0,
            pre_classified_count: 0,
            group_rows: 0,
            file_rows: 0,
            rows: vec![],
        };
        let (rows, next) = plan.page(99, 40);
        assert!(rows.is_empty());
        assert_eq!(next, None);
    }

    #[test]
    fn system_temp_and_ai_tool_cache_group_but_ai_output_does_not() {
        assert_eq!(
            group_key_for_path("/private/var/folders/ab/cd/T/app/tmp.bin"),
            Some("/private/var/folders/ab/cd/T/app".to_string())
        );
        assert_eq!(
            group_key_for_path(
                "/Users/x/Library/Application Support/Cursor/CachedData/blob"
            ),
            Some("/Users/x/Library/Application Support/Cursor".to_string())
        );
        assert_eq!(
            group_key_for_path("/Users/x/Library/Caches/cursor/Code/User/settings/tmp"),
            Some("/Users/x/Library/Caches/cursor".to_string())
        );
        assert_eq!(
            group_key_for_path("/Users/x/Projects/chat-export/notes.md"),
            None
        );
    }

    #[test]
    fn parent_dir_is_basic_and_handles_root() {
        assert_eq!(parent_dir("/a/b.txt"), Some("/a".to_string()));
        assert_eq!(parent_dir("/a"), Some("/".to_string()));
        assert_eq!(parent_dir("a.txt"), None);
    }
}
