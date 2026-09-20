//! Pre-AI coverage funnel helpers (Phase 2). See `docs/superpowers/specs/2026-09-20-ai-coverage-phase2-tree-design.md`.

use crate::index::SnapshotIndex;

const EXCLUSION_DIR_NAMES: &[&str] = &[
    "node_modules",
    "Caches",
    "caches",
    "cache",
    ".cache",
    "tmp",
    "temp",
    "Temp",
    "target",
    "build",
    "Build",
    "dist",
    "out",
    "DerivedData",
    "__pycache__",
    ".gradle",
    ".npm",
    ".yarn",
];

/// Directory prefixes under which unclassified files are treated as locally safe (scan Tier-1/2 hits).
pub fn coverage_local_exclusion_prefixes(index: &SnapshotIndex) -> Vec<String> {
    let mut prefixes: Vec<String> = Vec::new();
    for category in ["BuildArtifact", "Cache", "Temp"] {
        for entry in index.entries_with_category(category) {
            for ancestor in exclusion_prefix_chain(&entry.path) {
                if !prefixes.iter().any(|p| p == &ancestor) {
                    prefixes.push(ancestor);
                }
            }
        }
    }
    prefixes.sort_by(|a, b| b.len().cmp(&a.len()).then(a.cmp(b)));
    prefixes
}

/// Longest matching exclusion prefix for `path`, if any. `prefixes` should be sorted len-desc (see [`coverage_local_exclusion_prefixes`]).
pub fn path_under_longest_prefix<'a>(path: &str, prefixes: &'a [String]) -> Option<&'a str> {
    let normalized = normalize_path(path);
    for prefix in prefixes {
        if path_is_at_or_under(&normalized, prefix) {
            return Some(prefix.as_str());
        }
    }
    None
}

fn exclusion_prefix_chain(classified_path: &str) -> Vec<String> {
    let mut chain = Vec::new();
    let mut current = parent_dir(classified_path);
    while let Some(dir) = current {
        chain.push(dir.clone());
        if !should_extend_exclusion_chain(&dir) {
            break;
        }
        current = parent_dir(&dir);
    }
    chain
}

fn should_extend_exclusion_chain(dir_path: &str) -> bool {
    let normalized = normalize_path(dir_path);
    let name = normalized.rsplit('/').next().unwrap_or(normalized.as_str());
    let lower = name.to_ascii_lowercase();
    if EXCLUSION_DIR_NAMES
        .iter()
        .any(|marker| lower == marker.to_ascii_lowercase())
    {
        return true;
    }
    let lower_path = normalized.to_ascii_lowercase();
    lower_path.contains("/caches/")
        || lower_path.contains("/cache/")
        || lower_path.contains(".cache/")
        || lower_path.contains("/tmp/")
        || lower_path.contains("/temp/")
        || lower_path.contains("/node_modules/")
        || lower_path.contains("/target/")
        || lower_path.contains("/build/")
}

fn parent_dir(path: &str) -> Option<String> {
    let normalized = normalize_path(path);
    if normalized.is_empty() {
        return None;
    }
    match normalized.rfind('/') {
        None => None,
        Some(0) => Some("/".to_string()),
        Some(idx) if idx > 0 => Some(normalized[..idx].to_string()),
        _ => None,
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

fn path_is_at_or_under(path: &str, root: &str) -> bool {
    if root.is_empty() {
        return false;
    }
    path == root
        || (path.starts_with(root)
            && path.as_bytes().get(root.len()) == Some(&b'/'))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::index::SnapshotIndexBuilder;
    use crate::model::{EntryCategory, RiskLevel, ScanStats, SourceType, StorageEntry};

    fn classified_entry(path: &str, size: u64, category: EntryCategory) -> StorageEntry {
        StorageEntry {
            id: format!("id:{path}"),
            display_name: path.rsplit('/').next().unwrap_or(path).to_string(),
            path_or_uri: path.to_string(),
            size_bytes: size,
            category,
            risk_level: RiskLevel::Low,
            source_type: SourceType::File,
            deletable: true,
            reason: "test".to_string(),
            modified_at_ms: None,
        }
    }

    fn finish(builder: SnapshotIndexBuilder) -> SnapshotIndex {
        builder.finish(
            "snap".to_string(),
            1,
            1,
            "Done".to_string(),
            ScanStats::default(),
        )
    }

    #[test]
    fn siblings_under_node_modules_both_match_parent_prefix() {
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.ensure_dir("/root/app/node_modules/pkg");
        builder.insert_entry(classified_entry(
            "/root/app/node_modules/pkg/index.js",
            100,
            EntryCategory::BuildArtifact,
        ));
        builder.record_file_size("/root/app/node_modules/other/x.js", 50);
        let index = finish(builder);

        let prefixes = coverage_local_exclusion_prefixes(&index);
        assert!(
            prefixes.iter().any(|p| p.ends_with("node_modules")),
            "prefixes={prefixes:?}"
        );

        let sibling = "/root/app/node_modules/other/x.js";
        assert!(path_under_longest_prefix(sibling, &prefixes).is_some());

        let kb =
            crate::os_knowledge::OsKnowledgeBase::from_yaml("version: 1\nmacos: []\nwindows: []\nlinux: []", "macos")
                .unwrap();
        let wired = crate::indexed_local_exclusion_prefixes(&index);
        match crate::resolve_unclassified_for_ai(sibling, 50, &kb, &wired) {
            crate::UnclassifiedAiRouting::Local(_) => {}
            crate::UnclassifiedAiRouting::SendToAi { .. } => {
                panic!("sibling should be local via exclusion prefix")
            }
        }
    }

    #[test]
    fn longest_prefix_wins_over_shorter_parent() {
        let prefixes = vec![
            "/root/app/node_modules".to_string(),
            "/root/app/node_modules/pkg".to_string(),
        ];
        let sorted = {
            let mut p = prefixes;
            p.sort_by(|a, b| b.len().cmp(&a.len()).then(a.cmp(b)));
            p
        };
        assert_eq!(
            path_under_longest_prefix("/root/app/node_modules/pkg/a.js", &sorted),
            Some("/root/app/node_modules/pkg")
        );
    }
}
