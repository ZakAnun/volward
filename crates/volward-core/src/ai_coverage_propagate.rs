//! Tree directory verdict propagation to unclassified files (Phase 2 §5.2).

use std::io::Write;

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
    let Some(rule) = DirPropagation::new(dir_path, verdict, confidence, role) else {
        return Vec::new();
    };
    let mut out = Vec::new();
    index.visit_unclassified_files_under(&rule.dir_path, |path, size_bytes| {
        out.push(CoverageLocalVerdict {
            path: path.to_string(),
            size_bytes,
            verdict: rule.verdict.to_string(),
            confidence: "high".to_string(),
            reason: rule.reason.to_string(),
            coverage_source: rule.coverage_source.clone(),
        });
    });
    out.sort_unstable_by(|a, b| a.path.cmp(&b.path));
    out
}

/// Same verdicts as [`apply_dir_verdict`], streamed as JSONL rows (unsorted)
/// without materializing the subtree. Returns the number of rows written.
pub fn write_dir_verdict_jsonl<W: Write>(
    index: &SnapshotIndex,
    dir_path: &str,
    verdict: &str,
    confidence: &str,
    role: DirectoryRole,
    out: &mut W,
) -> std::io::Result<usize> {
    let Some(rule) = DirPropagation::new(dir_path, verdict, confidence, role) else {
        return Ok(0);
    };
    let mut written = 0usize;
    let mut failure: Option<std::io::Error> = None;
    index.visit_unclassified_files_under(&rule.dir_path, |path, size_bytes| {
        if failure.is_some() {
            return;
        }
        let row = JsonlRow {
            path,
            size_bytes,
            verdict: rule.verdict,
            confidence: "high",
            reason: rule.reason,
            coverage_source: &rule.coverage_source,
        };
        let result = serde_json::to_writer(&mut *out, &row)
            .map_err(std::io::Error::from)
            .and_then(|()| out.write_all(b"\n"));
        match result {
            Ok(()) => written += 1,
            Err(e) => failure = Some(e),
        }
    });
    match failure {
        Some(e) => Err(e),
        None => Ok(written),
    }
}

#[derive(Serialize)]
struct JsonlRow<'a> {
    path: &'a str,
    size_bytes: u64,
    verdict: &'a str,
    confidence: &'a str,
    reason: &'a str,
    coverage_source: &'a str,
}

struct DirPropagation {
    dir_path: String,
    verdict: &'static str,
    reason: &'static str,
    coverage_source: String,
}

impl DirPropagation {
    fn new(dir_path: &str, verdict: &str, confidence: &str, role: DirectoryRole) -> Option<Self> {
        if confidence != "high" {
            return None;
        }
        let dir_path = normalize_path(dir_path);
        if dir_path.is_empty() {
            return None;
        }
        let (verdict, reason) = match verdict {
            "safe_to_remove"
                if matches!(role, DirectoryRole::ProjectRoot | DirectoryRole::ProjectLike) =>
            {
                return None;
            }
            "safe_to_remove" => (
                "safe_to_remove",
                "Inherited safe_to_remove from parent directory AI verdict.",
            ),
            "keep" => ("keep", "Inherited keep from parent directory AI verdict."),
            _ => return None,
        };
        let coverage_source = format!("dir_propagate:{dir_path}");
        Some(Self {
            dir_path,
            verdict,
            reason,
            coverage_source,
        })
    }
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

    #[test]
    fn propagate_ignores_prefix_siblings_and_accepts_trailing_slash() {
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.record_file_size("/root/storage/a.dat", 1);
        builder.record_file_size("/root/storage/deep/x/y/b.dat", 2);
        builder.record_file_size("/root/storage2/c.dat", 3);
        builder.record_file_size("/root/storage.bak", 4);
        let index = finish(builder);

        let verdicts = apply_dir_verdict(
            &index,
            "/root/storage/",
            "keep",
            "high",
            DirectoryRole::Unknown,
        );

        let paths: Vec<&str> = verdicts.iter().map(|v| v.path.as_str()).collect();
        assert_eq!(paths, vec!["/root/storage/a.dat", "/root/storage/deep/x/y/b.dat"]);
        assert_eq!(verdicts[0].coverage_source, "dir_propagate:/root/storage");
    }

    #[test]
    fn jsonl_writer_matches_apply_dir_verdict() {
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.record_file_size("/root/cache/a \"q\".bin", 7);
        builder.record_file_size("/root/cache/sub/b.bin", 9);
        builder.record_file_size("/root/proj/c.rs", 1);
        let index = finish(builder);

        let expected = apply_dir_verdict(&index, "/root/cache", "safe_to_remove", "high", DirectoryRole::CacheLike);
        let mut buf = Vec::new();
        let n = write_dir_verdict_jsonl(
            &index,
            "/root/cache",
            "safe_to_remove",
            "high",
            DirectoryRole::CacheLike,
            &mut buf,
        )
        .unwrap();
        assert_eq!(n, expected.len());

        let mut rows: Vec<serde_json::Value> = String::from_utf8(buf)
            .unwrap()
            .lines()
            .map(|line| serde_json::from_str(line).unwrap())
            .collect();
        rows.sort_by(|a, b| a["path"].as_str().cmp(&b["path"].as_str()));
        let expected: Vec<serde_json::Value> =
            expected.iter().map(|v| serde_json::to_value(v).unwrap()).collect();
        assert_eq!(rows, expected);

        let mut none = Vec::new();
        let n = write_dir_verdict_jsonl(&index, "/root/proj", "safe_to_remove", "high", DirectoryRole::ProjectRoot, &mut none)
            .unwrap();
        assert_eq!(n, 0);
        assert!(none.is_empty());
    }

    #[test]
    fn propagate_subtree_walk_matches_full_scan_filter() {
        use crate::model::EntryCategory;

        let mut builder = SnapshotIndexBuilder::new("/root");
        for d in 0..6 {
            for f in 0..5 {
                builder.record_file_size(&format!("/root/d{d}/s{}/f{f}.bin", f % 2), (d * 10 + f) as u64);
            }
        }
        builder.insert_entry(classified_entry("/root/d1/s0/indexed.js", 9, EntryCategory::BuildArtifact));
        let index = finish(builder);

        for dir in ["/root/d1", "/root/d1/s0", "/root/d3/s1", "/root"] {
            let got: Vec<String> = apply_dir_verdict(&index, dir, "keep", "high", DirectoryRole::Unknown)
                .into_iter()
                .map(|v| v.path)
                .collect();
            let mut expected: Vec<String> = index
                .unclassified_files()
                .into_iter()
                .map(|(p, _)| p)
                .filter(|p| p.starts_with(&format!("{dir}/")))
                .collect();
            expected.sort();
            assert_eq!(got, expected, "dir={dir}");
        }
    }
}
