use serde::Serialize;

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

#[cfg(test)]
mod tests {
    use super::*;

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
