//! Pre-AI coverage funnel helpers (Phase 2). See `docs/superpowers/specs/2026-09-20-ai-coverage-phase2-tree-design.md`.

use std::collections::HashMap;

use crate::ai_candidates::{
    ai_cleanup_hint_for_path, hint_source_skips_ai, pre_classified_from_heuristics,
    pre_classified_from_hint, pre_classified_from_kb, pre_classified_under_index_prefix,
    AiCleanupHint, PreClassifiedEntry,
};
use crate::ai_coverage_propagate::CoverageLocalVerdict;
use crate::directory_role::collect_project_anchor_paths;
use crate::index::SnapshotIndex;
use crate::model::EntryCategory;
use crate::os_knowledge::OsKnowledgeBase;

/// Unclassified file path → deepest matching project anchor directory (if any).
pub type CoverageFunnelContextMap = HashMap<String, Option<String>>;

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

#[derive(Clone)]
pub enum CoverageFileResolution {
    LocalSafe(PreClassifiedEntry),
    LocalKeep {
        reason: String,
        confidence: &'static str,
    },
    TailCandidate {
        cleanup_hint: Option<AiCleanupHint>,
    },
    TreeCandidate,
}

#[derive(Debug, Clone, Default)]
pub struct CoverageFunnelContext {
    pub exclusion_prefixes: Vec<String>,
    pub protected_prefixes: Vec<String>,
    pub personal_prefixes: Vec<String>,
    pub project_ancestor: Option<String>,
}

impl CoverageFunnelContext {
    pub fn with_exclusion_prefixes(prefixes: &[String]) -> Self {
        Self {
            exclusion_prefixes: prefixes.to_vec(),
            ..Default::default()
        }
    }
}

impl CoverageFileResolution {
    pub fn into_ai_routing(self, path: &str, size_bytes: u64) -> crate::UnclassifiedAiRouting {
        use crate::UnclassifiedAiRouting;
        match self {
            CoverageFileResolution::LocalSafe(entry) => UnclassifiedAiRouting::Local(entry),
            CoverageFileResolution::LocalKeep { reason, confidence } => {
                UnclassifiedAiRouting::Local(PreClassifiedEntry {
                    path: path.to_string(),
                    size_bytes,
                    is_dir: false,
                    category: EntryCategory::Unknown,
                    confidence: confidence.to_string(),
                    reason,
                    deletable: false,
                })
            }
            CoverageFileResolution::TailCandidate { cleanup_hint } => {
                UnclassifiedAiRouting::SendToAi { cleanup_hint }
            }
            CoverageFileResolution::TreeCandidate => {
                UnclassifiedAiRouting::SendToAi { cleanup_hint: None }
            }
        }
    }
}

/// Single gate for whether an unclassified file should reach tree/tail AI (Phase 2 funnel).
pub fn resolve_unclassified_for_coverage(
    path: &str,
    size_bytes: u64,
    kb: &OsKnowledgeBase,
    ctx: &CoverageFunnelContext,
) -> CoverageFileResolution {
    if let Some(known) = kb.classify_path(path) {
        if known.deletable {
            if let Some(entry) = pre_classified_from_kb(path, size_bytes, kb) {
                return CoverageFileResolution::LocalSafe(entry);
            }
        } else {
            return CoverageFileResolution::LocalKeep {
                reason: known.reason,
                confidence: if known.confidence == crate::Confidence::High {
                    "high"
                } else {
                    "medium"
                },
            };
        }
    }
    if let Some(entry) =
        pre_classified_under_index_prefix(path, size_bytes, &ctx.exclusion_prefixes, kb)
    {
        return CoverageFileResolution::LocalSafe(entry);
    }
    if let Some(hint) = ai_cleanup_hint_for_path(path) {
        if hint_source_skips_ai(hint.source) {
            if let Some(entry) = pre_classified_from_hint(path, size_bytes, hint) {
                return CoverageFileResolution::LocalSafe(entry);
            }
        } else if hint.source == "ai_generated_output" {
            return CoverageFileResolution::TailCandidate {
                cleanup_hint: Some(hint),
            };
        }
    }
    if let Some(entry) = pre_classified_from_heuristics(path, size_bytes) {
        return CoverageFileResolution::LocalSafe(entry);
    }
    if path_under_any_prefix(path, &ctx.protected_prefixes) {
        return CoverageFileResolution::LocalKeep {
            reason: "Protected system path prefix.".to_string(),
            confidence: "high",
        };
    }
    if path_under_any_prefix(path, &ctx.personal_prefixes) {
        return CoverageFileResolution::LocalKeep {
            reason: "Personal folder (Documents/Desktop) excluded from AI.".to_string(),
            confidence: "medium",
        };
    }
    if ctx.project_ancestor.is_some() {
        if is_likely_source_file(path) {
            return CoverageFileResolution::LocalKeep {
                reason: "Source file under detected project root.".to_string(),
                confidence: "high",
            };
        }
        if let Some(hint) = ai_cleanup_hint_for_path(path) {
            if hint.source == "ai_generated_output" {
                return CoverageFileResolution::TailCandidate {
                    cleanup_hint: Some(hint),
                };
            }
        }
        return CoverageFileResolution::LocalKeep {
            reason: "File under detected project root.".to_string(),
            confidence: "high",
        };
    }
    if let Some(hint) = ai_cleanup_hint_for_path(path) {
        return CoverageFileResolution::TailCandidate {
            cleanup_hint: Some(hint),
        };
    }
    CoverageFileResolution::TreeCandidate
}

fn path_under_any_prefix(path: &str, prefixes: &[String]) -> bool {
    path_under_longest_prefix(path, prefixes).is_some()
}

fn is_likely_source_file(path: &str) -> bool {
    const SOURCE_EXTS: &[&str] = &[
        ".rs", ".dart", ".swift", ".go", ".py", ".js", ".ts", ".tsx", ".jsx", ".java", ".kt", ".k",
        ".c", ".cpp", ".cc", ".h", ".hpp", ".m", ".mm", ".rb", ".php", ".cs", ".scala", ".vue",
        ".svelte",
    ];
    let lower = path.to_ascii_lowercase();
    SOURCE_EXTS.iter().any(|ext| lower.ends_with(ext))
}

fn path_is_at_or_under(path: &str, root: &str) -> bool {
    if root.is_empty() {
        return false;
    }
    path == root || (path.starts_with(root) && path.as_bytes().get(root.len()) == Some(&b'/'))
}

/// Deepest project anchor on `sorted_anchors` that contains `path` (lex-sorted anchors).
pub fn deepest_project_ancestor_for_path(path: &str, sorted_anchors: &[String]) -> Option<String> {
    let path = normalize_path(path);
    if sorted_anchors.is_empty() {
        return None;
    }
    let mut lo = 0usize;
    let mut hi = sorted_anchors.len();
    while lo < hi {
        let mid = lo + (hi - lo) / 2;
        if sorted_anchors[mid].as_str() <= path.as_str() {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    let mut idx = lo;
    while idx > 0 {
        idx -= 1;
        if path_is_at_or_under(&path, &sorted_anchors[idx]) {
            return Some(sorted_anchors[idx].clone());
        }
    }
    None
}

/// Map each file path to its deepest project anchor (one pass over sorted paths + anchors).
pub fn build_funnel_context_for_files(
    index: &SnapshotIndex,
    file_paths: &[String],
    _kb: &OsKnowledgeBase,
    _protected_prefixes: &[String],
) -> CoverageFunnelContextMap {
    let anchors = collect_project_anchor_paths(index);
    let mut sorted_paths: Vec<String> = file_paths.to_vec();
    sorted_paths.sort();
    let mut map = CoverageFunnelContextMap::new();
    for path in sorted_paths {
        let ancestor = deepest_project_ancestor_for_path(&path, &anchors);
        map.insert(path, ancestor);
    }
    map
}

/// Project ancestry map for all unclassified files in `index`.
pub fn build_coverage_funnel_context(
    index: &SnapshotIndex,
    kb: &OsKnowledgeBase,
    protected_prefixes: &[String],
) -> CoverageFunnelContextMap {
    let paths: Vec<String> = index
        .unclassified_files()
        .into_iter()
        .map(|(path, _)| path)
        .collect();
    build_funnel_context_for_files(index, &paths, kb, protected_prefixes)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct CoverageFunnelStats {
    pub local_safe_files: u64,
    pub local_keep_files: u64,
    pub tail_files: u64,
    pub tree_pending_files: u64,
}

/// Count unclassified files by pre-AI funnel resolution (single pass over unclassified set).
pub fn compute_coverage_funnel_stats(
    index: &SnapshotIndex,
    kb: &OsKnowledgeBase,
    protected_prefixes: &[String],
    personal_prefixes: &[String],
) -> CoverageFunnelStats {
    let funnel_map = build_coverage_funnel_context(index, kb, protected_prefixes);
    let classified = index.classified_paths();
    let mut stats = CoverageFunnelStats::default();
    for (path, size_bytes) in index.unclassified_files() {
        if classified.contains(&path) {
            continue;
        }
        let project_ancestor = funnel_map.get(&path).cloned().flatten();
        let ctx = coverage_funnel_context_for_path(
            project_ancestor,
            index,
            protected_prefixes,
            personal_prefixes,
        );
        match resolve_unclassified_for_coverage(&path, size_bytes, kb, &ctx) {
            CoverageFileResolution::LocalSafe(_) => stats.local_safe_files += 1,
            CoverageFileResolution::LocalKeep { .. } => stats.local_keep_files += 1,
            CoverageFileResolution::TailCandidate { .. } => stats.tail_files += 1,
            CoverageFileResolution::TreeCandidate => stats.tree_pending_files += 1,
        }
    }
    stats
}

fn local_coverage_source(path: &str, kb: &OsKnowledgeBase) -> String {
    if kb.classify_path(path).is_some() {
        "local:kb".to_string()
    } else {
        "local:funnel".to_string()
    }
}

fn local_verdict_from_safe(entry: PreClassifiedEntry, kb: &OsKnowledgeBase) -> CoverageLocalVerdict {
    CoverageLocalVerdict {
        path: entry.path.clone(),
        size_bytes: entry.size_bytes,
        verdict: "safe_to_remove".to_string(),
        confidence: entry.confidence,
        reason: entry.reason,
        coverage_source: local_coverage_source(&entry.path, kb),
    }
}

fn local_verdict_from_keep(
    path: String,
    size_bytes: u64,
    reason: String,
    confidence: &str,
    kb: &OsKnowledgeBase,
) -> CoverageLocalVerdict {
    CoverageLocalVerdict {
        path: path.clone(),
        size_bytes,
        verdict: "keep".to_string(),
        confidence: confidence.to_string(),
        reason,
        coverage_source: local_coverage_source(&path, kb),
    }
}

/// Collect funnel-resolved local verdicts for all unclassified files (single pass).
pub fn collect_local_coverage_verdicts(
    index: &SnapshotIndex,
    kb: &OsKnowledgeBase,
    protected_prefixes: &[String],
    personal_prefixes: &[String],
) -> Vec<CoverageLocalVerdict> {
    let funnel_map = build_coverage_funnel_context(index, kb, protected_prefixes);
    let classified = index.classified_paths();
    let mut out = Vec::new();
    for (path, size_bytes) in index.unclassified_files() {
        if classified.contains(&path) {
            continue;
        }
        let project_ancestor = funnel_map.get(&path).cloned().flatten();
        let ctx = coverage_funnel_context_for_path(
            project_ancestor,
            index,
            protected_prefixes,
            personal_prefixes,
        );
        match resolve_unclassified_for_coverage(&path, size_bytes, kb, &ctx) {
            CoverageFileResolution::LocalSafe(entry) => {
                out.push(local_verdict_from_safe(entry, kb));
            }
            CoverageFileResolution::LocalKeep { reason, confidence } => {
                out.push(local_verdict_from_keep(
                    path, size_bytes, reason, confidence, kb,
                ));
            }
            CoverageFileResolution::TailCandidate { .. } | CoverageFileResolution::TreeCandidate => {}
        }
    }
    out.sort_by(|a, b| a.path.cmp(&b.path));
    out
}

/// Build per-file [`CoverageFunnelContext`] using shared index-level prefix lists.
pub fn coverage_funnel_context_for_path(
    project_ancestor: Option<String>,
    index: &SnapshotIndex,
    protected_prefixes: &[String],
    personal_prefixes: &[String],
) -> CoverageFunnelContext {
    CoverageFunnelContext {
        exclusion_prefixes: coverage_local_exclusion_prefixes(index),
        protected_prefixes: protected_prefixes.to_vec(),
        personal_prefixes: personal_prefixes.to_vec(),
        project_ancestor,
    }
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

    fn test_kb() -> OsKnowledgeBase {
        OsKnowledgeBase::from_yaml("version: 1\nmacos: []\nwindows: []\nlinux: []", "macos")
            .unwrap()
    }

    #[test]
    fn build_funnel_nested_projects_pick_deepest_anchor() {
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.ensure_dir("/root/a/pkg/src");
        builder.record_file_size("/root/a/Cargo.toml", 10);
        builder.record_file_size("/root/a/pkg/Cargo.toml", 10);
        builder.record_file_size("/root/a/pkg/src/x.rs", 100);
        let index = finish(builder);
        let map = build_coverage_funnel_context(&index, &test_kb(), &[]);
        assert_eq!(
            map.get("/root/a/pkg/src/x.rs"),
            Some(&Some("/root/a/pkg".to_string()))
        );
        assert_ne!(
            map.get("/root/a/pkg/src/x.rs"),
            Some(&Some("/root/a".to_string()))
        );
    }

    #[test]
    fn build_funnel_project_like_anchor_covers_subtree() {
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.ensure_dir("/root/myapp/src");
        builder.record_file_size("/root/myapp/README.md", 50);
        builder.record_file_size("/root/myapp/src/lib.rs", 80);
        let index = finish(builder);
        let map = build_coverage_funnel_context(&index, &test_kb(), &[]);
        assert_eq!(
            map.get("/root/myapp/src/lib.rs"),
            Some(&Some("/root/myapp".to_string()))
        );
    }

    #[test]
    fn build_funnel_file_outside_project_anchor_is_none() {
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.ensure_dir("/root/random");
        builder.record_file_size("/root/random/notes.txt", 10);
        let index = finish(builder);
        let map = build_coverage_funnel_context(&index, &test_kb(), &[]);
        assert_eq!(map.get("/root/random/notes.txt"), Some(&None));
    }

    #[ignore]
    #[test]
    fn build_funnel_many_paths_stays_correct() {
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.ensure_dir("/root/proj/src");
        builder.record_file_size("/root/proj/Cargo.toml", 1);
        for i in 0..10_000 {
            builder.record_file_size(&format!("/root/proj/src/f{i}.rs"), 1);
        }
        let index = finish(builder);
        let paths: Vec<String> = index
            .unclassified_files()
            .into_iter()
            .map(|(p, _)| p)
            .collect();
        let map = build_funnel_context_for_files(&index, &paths, &test_kb(), &[]);
        assert_eq!(map.len(), 10_000);
        assert_eq!(
            map.get("/root/proj/src/f0.rs"),
            Some(&Some("/root/proj".to_string()))
        );
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

        let kb = crate::os_knowledge::OsKnowledgeBase::from_yaml(
            "version: 1\nmacos: []\nwindows: []\nlinux: []",
            "macos",
        )
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
    fn collect_local_coverage_verdicts_only_local_buckets() {
        let mut builder = SnapshotIndexBuilder::new("/Users/x");
        builder.insert_entry(classified_entry(
            "/Users/x/Library/Caches/myapp/anchor.bin",
            1,
            EntryCategory::Cache,
        ));
        builder.record_file_size("/Users/x/Library/Caches/myapp/sibling.bin", 100);
        builder.record_file_size("/Users/x/MyProj/Cargo.toml", 10);
        builder.record_file_size("/Users/x/loose.dat", 5);
        let index = finish(builder);
        let kb = test_kb();
        let stats = compute_coverage_funnel_stats(&index, &kb, &[], &[]);
        let verdicts = collect_local_coverage_verdicts(&index, &kb, &[], &[]);
        let local_count = stats.local_safe_files + stats.local_keep_files;
        assert_eq!(verdicts.len() as u64, local_count, "{stats:?}");
        assert!(verdicts.iter().all(|v| {
            v.verdict == "safe_to_remove" || v.verdict == "keep"
        }));
    }

    #[test]
    fn compute_coverage_funnel_stats_counts_each_bucket() {
        let mut builder = SnapshotIndexBuilder::new("/Users/x");
        builder.insert_entry(classified_entry(
            "/Users/x/Library/Caches/myapp/anchor.bin",
            1,
            EntryCategory::Cache,
        ));
        builder.record_file_size("/Users/x/Library/Caches/myapp/sibling.bin", 100);
        builder.record_file_size("/Users/x/MyProj/Cargo.toml", 10);
        builder.record_file_size("/Users/x/MyProj/src/main.rs", 20);
        builder.record_file_size("/Users/x/loose.dat", 5);
        builder.record_file_size("/Users/x/project/llm-output/note.md", 5);
        let index = finish(builder);
        let kb = test_kb();
        let stats = compute_coverage_funnel_stats(&index, &kb, &[], &[]);
        assert!(stats.local_safe_files >= 1, "{stats:?}");
        assert!(stats.local_keep_files >= 1, "{stats:?}");
        assert!(stats.tail_files >= 1, "{stats:?}");
        assert!(stats.tree_pending_files >= 1, "{stats:?}");
    }

    #[test]
    fn ai_generated_output_routes_to_tail_not_tree() {
        let kb = crate::os_knowledge::OsKnowledgeBase::from_yaml(
            "version: 1\nmacos: []\nwindows: []\nlinux: []",
            "macos",
        )
        .unwrap();
        let path = "/Users/x/project/llm-output/note.md";
        let resolution =
            resolve_unclassified_for_coverage(path, 5, &kb, &CoverageFunnelContext::default());
        assert!(matches!(
            resolution,
            CoverageFileResolution::TailCandidate { .. }
        ));
    }

    #[test]
    fn personal_prefix_keeps_without_ai() {
        let kb = crate::os_knowledge::OsKnowledgeBase::from_yaml(
            "version: 1\nmacos: []\nwindows: []\nlinux: []",
            "macos",
        )
        .unwrap();
        let mut ctx = CoverageFunnelContext::default();
        ctx.personal_prefixes.push("/Users/x/Documents".to_string());
        let resolution =
            resolve_unclassified_for_coverage("/Users/x/Documents/notes.txt", 10, &kb, &ctx);
        assert!(matches!(
            resolution,
            CoverageFileResolution::LocalKeep { .. }
        ));
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
