//! Tree directory verdict propagation to unclassified files (Phase 2 §5.2).

use serde::Serialize;

use crate::directory_role::DirectoryRole;
use crate::index::SnapshotIndex;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct CoverageLocalVerdict {
    pub path: String,
    pub size_bytes: u64,
    pub verdict: String,
    pub confidence: String,
    pub reason: String,
    pub coverage_source: String,
}

/// Apply a high-confidence directory AI verdict to unclassified files under `dir_path`.
///
/// - `safe_to_remove` + high on non-project roles → local safe for subtree files.
/// - `safe_to_remove` + high on project roles → empty (caller must `drill_down`).
/// - `keep` + high → local keep for subtree files.
/// - Already classified index paths are skipped (S0 funnel gate).
pub fn apply_dir_verdict(
    index: &SnapshotIndex,
    dir_path: &str,
    verdict: &str,
    confidence: &str,
    role: DirectoryRole,
) -> Vec<CoverageLocalVerdict> {
    if confidence != "high" {
        return Vec::new();
    }
    let dir_path = normalize_path(dir_path);
    let coverage_source = format!("dir_propagate:{dir_path}");
    match verdict {
        "safe_to_remove" if matches!(role, DirectoryRole::ProjectRoot | DirectoryRole::ProjectLike) => {
            Vec::new()
        }
        "safe_to_remove" => collect_unclassified_under(
            index,
            &dir_path,
            "safe_to_remove",
            "Inherited safe_to_remove from parent directory AI verdict.",
            &coverage_source,
        ),
        "keep" => collect_unclassified_under(
            index,
            &dir_path,
            "keep",
            "Inherited keep from parent directory AI verdict.",
            &coverage_source,
        ),
        _ => Vec::new(),
    }
}

fn collect_unclassified_under(
    index: &SnapshotIndex,
    dir_path: &str,
    verdict: &str,
    reason: &str,
    coverage_source: &str,
) -> Vec<CoverageLocalVerdict> {
    let classified = index.classified_paths();
    let mut out = Vec::new();
    for (path, size_bytes) in index.unclassified_files() {
        if classified.contains(&path) {
            continue;
        }
        if !path_is_at_or_under(&path, dir_path) {
            continue;
        }
        out.push(CoverageLocalVerdict {
            path,
            size_bytes,
            verdict: verdict.to_string(),
            confidence: "high".to_string(),
            reason: reason.to_string(),
            coverage_source: coverage_source.to_string(),
        });
    }
    out.sort_by(|a, b| a.path.cmp(&b.path));
    out
}

fn path_is_at_or_under(path: &str, root: &str) -> bool {
    let path = normalize_path(path);
    let root = normalize_path(root);
    if root.is_empty() {
        return false;
    }
    path == root || (path.starts_with(&root) && path.as_bytes().get(root.len()) == Some(&b'/'))
}

fn normalize_path(path: &str) -> String {
    let normalized = path.replace('\\', "/");
    if normalized.len() > 1 && normalized.ends_with('/') {
        normalized[..normalized.len() - 1].to_string()
    } else {
        normalized
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::index::SnapshotIndexBuilder;
    use crate::model::ScanStats;

    fn finish(builder: SnapshotIndexBuilder) -> SnapshotIndex {
        builder.finish(
            "snap-propagate".to_string(),
            1,
            1,
            "Done".to_string(),
            ScanStats::default(),
        )
    }

    #[test]
    fn propagate_storage_dir_safe_marks_unclassified_children() {
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.ensure_dir("/root/storage/nested");
        builder.record_file_size("/root/storage/a.dat", 100);
        builder.record_file_size("/root/storage/nested/b.dat", 50);
        builder.record_file_size("/root/other/outside.dat", 10);
        let index = finish(builder);

        let verdicts = apply_dir_verdict(
            &index,
            "/root/storage",
            "safe_to_remove",
            "high",
            DirectoryRole::StorageLike,
        );

        let paths: Vec<&str> = verdicts.iter().map(|v| v.path.as_str()).collect();
        assert_eq!(paths, vec!["/root/storage/a.dat", "/root/storage/nested/b.dat"]);
        assert!(verdicts.iter().all(|v| v.verdict == "safe_to_remove"));
        assert!(verdicts.iter().all(|v| v.confidence == "high"));
        assert_eq!(
            verdicts[0].coverage_source,
            "dir_propagate:/root/storage"
        );
    }

    #[test]
    fn propagate_project_dir_safe_returns_empty_for_drill_down() {
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.ensure_dir("/root/proj/src");
        builder.record_file_size("/root/proj/Cargo.toml", 10);
        builder.record_file_size("/root/proj/src/main.rs", 200);
        let index = finish(builder);

        let verdicts = apply_dir_verdict(
            &index,
            "/root/proj",
            "safe_to_remove",
            "high",
            DirectoryRole::ProjectRoot,
        );

        assert!(verdicts.is_empty());
    }

    #[test]
    fn propagate_keep_high_marks_children_keep() {
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.ensure_dir("/root/archive");
        builder.record_file_size("/root/archive/old.bin", 300);
        let index = finish(builder);

        let verdicts = apply_dir_verdict(
            &index,
            "/root/archive",
            "keep",
            "high",
            DirectoryRole::Unknown,
        );

        assert_eq!(verdicts.len(), 1);
        assert_eq!(verdicts[0].path, "/root/archive/old.bin");
        assert_eq!(verdicts[0].verdict, "keep");
    }

    fn classified_entry(path: &str, size: u64, category: crate::model::EntryCategory) -> crate::model::StorageEntry {
        crate::model::StorageEntry {
            id: format!("id:{path}"),
            display_name: path.rsplit('/').next().unwrap_or(path).to_string(),
            path_or_uri: path.to_string(),
            size_bytes: size,
            category,
            risk_level: crate::model::RiskLevel::Low,
            source_type: crate::model::SourceType::File,
            deletable: true,
            reason: "test".to_string(),
            modified_at_ms: None,
        }
    }

    #[test]
    fn propagate_skips_classified_index_paths() {
        use crate::model::EntryCategory;

        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.ensure_dir("/root/storage");
        builder.insert_entry(classified_entry(
            "/root/storage/indexed.js",
            80,
            EntryCategory::BuildArtifact,
        ));
        builder.record_file_size("/root/storage/other.js", 40);
        let index = finish(builder);

        let verdicts = apply_dir_verdict(
            &index,
            "/root/storage",
            "safe_to_remove",
            "high",
            DirectoryRole::StorageLike,
        );

        assert_eq!(verdicts.len(), 1);
        assert_eq!(verdicts[0].path, "/root/storage/other.js");
    }
}
