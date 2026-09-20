//! Pre-AI coverage funnel helpers (Phase 2). See `docs/superpowers/specs/2026-09-20-ai-coverage-phase2-tree-design.md`.

use crate::ai_candidates::{
    ai_cleanup_hint_for_path, hint_source_skips_ai, pre_classified_from_heuristics,
    pre_classified_from_hint, pre_classified_from_kb, pre_classified_under_index_prefix,
    AiCleanupHint, PreClassifiedEntry,
};
use crate::index::SnapshotIndex;
use crate::model::EntryCategory;
use crate::os_knowledge::OsKnowledgeBase;

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
            CoverageFileResolution::TreeCandidate => UnclassifiedAiRouting::SendToAi {
                cleanup_hint: None,
            },
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
    fn ai_generated_output_routes_to_tail_not_tree() {
        let kb =
            crate::os_knowledge::OsKnowledgeBase::from_yaml("version: 1\nmacos: []\nwindows: []\nlinux: []", "macos")
                .unwrap();
        let path = "/Users/x/project/llm-output/note.md";
        let resolution = resolve_unclassified_for_coverage(path, 5, &kb, &CoverageFunnelContext::default());
        assert!(matches!(
            resolution,
            CoverageFileResolution::TailCandidate { .. }
        ));
    }

    #[test]
    fn personal_prefix_keeps_without_ai() {
        let kb =
            crate::os_knowledge::OsKnowledgeBase::from_yaml("version: 1\nmacos: []\nwindows: []\nlinux: []", "macos")
                .unwrap();
        let mut ctx = CoverageFunnelContext::default();
        ctx.personal_prefixes.push("/Users/x/Documents".to_string());
        let resolution = resolve_unclassified_for_coverage(
            "/Users/x/Documents/notes.txt",
            10,
            &kb,
            &ctx,
        );
        assert!(matches!(resolution, CoverageFileResolution::LocalKeep { .. }));
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
