use crate::model::{EntryCategory, ScanTreeNode};
use crate::os_knowledge::{Confidence, OsKnowledgeBase};
use serde::Serialize;
use std::collections::HashSet;

/// Default maximum number of candidates sent to the model / UI.
pub const DEFAULT_CANDIDATE_CAP: usize = 150;
/// Max concrete member paths retained per aggregated directory candidate.
/// Keeps the FFI JSON bounded even when a single parent has huge fan-out.
pub const DEFAULT_MAX_MEMBER_PATHS: usize = 200;
/// Max Tier-2 / KB pre-classified rows shown in the pre-check UI.
pub const DEFAULT_PRECLASSIFIED_CAP: usize = 200;
pub const AI_AGGREGATE_DELETE_TARGET_PREFIX: &str = "volward-ai-aggregate:v1:";

/// App-specific AI tool roots used by `ai_cleanup_hint_for_path` and by the
/// full-coverage group rule.
pub(crate) const AI_TOOL_APP_ROOT_PATTERNS: &[&str] = &[
    "/library/application support/cursor/",
    "/library/application support/windsurf/",
    "/library/application support/claude/",
    "/library/application support/codex/",
    "/library/caches/cursor/",
    "/library/caches/windsurf/",
    "/library/caches/claude/",
    "/library/caches/codex/",
    "/appdata/roaming/cursor/",
    "/appdata/roaming/windsurf/",
    "/appdata/roaming/claude/",
    "/appdata/roaming/codex/",
    "/appdata/local/cursor/",
    "/appdata/local/windsurf/",
    "/appdata/local/claude/",
    "/appdata/local/codex/",
    "/.config/cursor/",
    "/.config/windsurf/",
    "/.config/claude/",
    "/.config/codex/",
    "/.cache/cursor/",
    "/.cache/windsurf/",
    "/.cache/claude/",
    "/.cache/codex/",
];

/// Hidden AI tool working directories; only meaningful together with a
/// cache/temp segment (checked by `ai_cleanup_hint_for_path`).
pub(crate) const AI_TOOL_HIDDEN_MARKERS: &[&str] =
    &["/.cursor/", "/.claude/", "/.codex/", "/.windsurf/"];

/// Returns the concrete tool root directory for `path` (for example
/// `/Users/x/Library/Caches/Cursor`), so a whole tool cache tree folds into
/// one group candidate. Case-insensitive; only ASCII case folding is used so
/// byte indexes stay aligned with the original path.
pub(crate) fn ai_tool_group_root(path: &str) -> Option<String> {
    let normalized = path.replace('\\', "/");
    let lower = normalized.to_ascii_lowercase();
    let mut best_end = None;
    for marker in AI_TOOL_APP_ROOT_PATTERNS
        .iter()
        .chain(AI_TOOL_HIDDEN_MARKERS.iter())
    {
        if let Some(idx) = lower.find(marker) {
            let end = idx + marker.trim_end_matches('/').len();
            if end < normalized.len() && best_end.is_none_or(|current: usize| end > current) {
                best_end = Some(end);
            }
        }
    }
    best_end.map(|end| normalized[..end].to_string())
}

pub fn ai_aggregate_delete_target(path: &str) -> String {
    format!("{AI_AGGREGATE_DELETE_TARGET_PREFIX}{path}")
}

pub fn ai_aggregate_path_from_delete_target(target: &str) -> Option<&str> {
    target
        .strip_prefix(AI_AGGREGATE_DELETE_TARGET_PREFIX)
        .filter(|path| !path.is_empty())
}

#[derive(Debug, Clone, Serialize)]
pub struct AiCandidate {
    pub path: String,
    pub size_bytes: u64,
    pub is_dir: bool,
    pub child_count: Option<usize>,
    pub extension: Option<String>,
    /// Optional source bucket used by the UI/prompt to explain why a path is
    /// interesting for AI cleanup.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cleanup_source: Option<String>,
    /// Short evidence string shown in UI and sent to the model.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cleanup_hint: Option<String>,
    /// Conservative review window. Without mtime in the snapshot this is a
    /// policy hint, not an automatic age check.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub retention_days: Option<u32>,
    /// Files folded into this candidate by `aggregate_by_dir`. Empty for
    /// real file candidates. Deleting an aggregate MUST target these paths
    /// instead of `path`, which is only the common parent directory and may
    /// hold unrelated (classified or user) data.
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub member_paths: Vec<String>,
    /// Opaque native target used to resolve all aggregate members at deletion
    /// time without serializing every path over FFI.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub delete_target: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct PreClassifiedEntry {
    pub path: String,
    pub size_bytes: u64,
    pub is_dir: bool,
    pub category: EntryCategory,
    pub confidence: String,
    pub reason: String,
    pub deletable: bool,
}

pub struct AiCandidateSet {
    pub pre_classified: Vec<PreClassifiedEntry>,
    pub candidates: Vec<AiCandidate>,
    pub estimated_input_tokens: usize,
    /// Unclassified files discovered *before* `aggregate_by_dir` folded
    /// siblings and before `cap_top_n` truncated the list.
    pub total_raw_count: usize,
    /// Candidate count after aggregation but before `cap_top_n`.
    pub candidates_total_before_cap: usize,
    /// True when `cap_top_n` dropped candidates, so the UI can say so.
    pub truncated: bool,
    /// True when pre-classified rows were capped for UI/payload size.
    pub pre_classified_truncated: bool,
}

pub struct AiCandidateBuilder {
    pre_classified: Vec<PreClassifiedEntry>,
    raw_unknown: Vec<AiCandidate>,
    raw_file_count: usize,
    total_before_cap: Option<usize>,
}

impl AiCandidateBuilder {
    fn empty() -> Self {
        Self {
            pre_classified: vec![],
            raw_unknown: vec![],
            raw_file_count: 0,
            total_before_cap: None,
        }
    }

    pub fn from_tree(
        tree: &ScanTreeNode,
        classified: &HashSet<String>,
        kb: &OsKnowledgeBase,
    ) -> Self {
        let mut b = Self::empty();
        b.walk(tree, classified, kb, &[]);
        b.raw_file_count = b.raw_unknown.len();
        b
    }

    /// Adds an already-classified entry (e.g. a Tier-2 index hit) so the
    /// pre-check UI can offer it without another AI round-trip.
    pub fn push_pre_classified(&mut self, entry: PreClassifiedEntry) {
        self.pre_classified.push(entry);
    }

    fn walk(
        &mut self,
        node: &ScanTreeNode,
        classified: &HashSet<String>,
        kb: &OsKnowledgeBase,
        indexed_local_prefixes: &[String],
    ) {
        if classified.contains(&node.path) {
            return;
        }
        if node.is_dir && !node.children.is_empty() {
            for child in &node.children {
                self.walk(child, classified, kb, indexed_local_prefixes);
            }
            return;
        }
        if node.is_dir {
            return;
        }
        match resolve_unclassified_for_ai(&node.path, node.size_bytes, kb, indexed_local_prefixes) {
            UnclassifiedAiRouting::Local(entry) => self.pre_classified.push(entry),
            UnclassifiedAiRouting::SendToAi { cleanup_hint } => {
                let ext = std::path::Path::new(&node.path)
                    .extension()
                    .and_then(|e| e.to_str())
                    .map(|s| format!(".{s}"));
                let (cleanup_source, cleanup_hint, retention_days) = cleanup_hint
                    .map(|h| {
                        (
                            Some(h.source.to_string()),
                            Some(h.hint.to_string()),
                            Some(h.retention_days),
                        )
                    })
                    .unwrap_or((None, None, None));
                self.raw_unknown.push(AiCandidate {
                    path: node.path.clone(),
                    size_bytes: node.size_bytes,
                    is_dir: false,
                    child_count: None,
                    extension: ext,
                    cleanup_source,
                    cleanup_hint,
                    retention_days,
                    member_paths: vec![],
                    delete_target: None,
                });
            }
        }
    }

    pub fn aggregate_by_dir(mut self, threshold: usize) -> Self {
        use std::collections::HashMap;
        let mut by_parent: HashMap<String, Vec<AiCandidate>> = HashMap::new();
        let mut singletons: Vec<AiCandidate> = vec![];
        for c in self.raw_unknown.drain(..) {
            if let Some(parent) = std::path::Path::new(&c.path)
                .parent()
                .and_then(|p| p.to_str())
                .map(|s| s.to_string())
            {
                by_parent.entry(parent).or_default().push(c);
            } else {
                singletons.push(c);
            }
        }
        for (parent, mut children) in by_parent {
            if children.len() >= threshold {
                let child_count = children.len();
                let total_size: u64 = children.iter().map(|c| c.size_bytes).sum();
                let merged_cleanup_source = children.iter().find_map(|c| c.cleanup_source.clone());
                let merged_cleanup_hint = children.iter().find_map(|c| c.cleanup_hint.clone());
                let merged_retention_days = children.iter().filter_map(|c| c.retention_days).min();
                // Prefer the largest members when capping the model/UI list.
                if children.len() > DEFAULT_MAX_MEMBER_PATHS {
                    children
                        .sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes).then(a.path.cmp(&b.path)));
                    children.truncate(DEFAULT_MAX_MEMBER_PATHS);
                }
                let member_paths: Vec<String> = children.iter().map(|c| c.path.clone()).collect();
                let delete_target = ai_aggregate_delete_target(&parent);
                self.raw_unknown.push(AiCandidate {
                    path: parent,
                    size_bytes: total_size,
                    is_dir: true,
                    child_count: Some(child_count),
                    extension: None,
                    cleanup_source: merged_cleanup_source,
                    cleanup_hint: merged_cleanup_hint,
                    retention_days: merged_retention_days,
                    member_paths,
                    delete_target: Some(delete_target),
                });
            } else {
                self.raw_unknown.append(&mut children);
            }
        }
        self.raw_unknown.extend(singletons);
        self
    }

    /// Keeps only the `n` largest candidates. Everything sent to the model and
    /// rendered by the UI flows through here, so the payload stays bounded no
    /// matter how large the scan was.
    pub fn cap_top_n(mut self, n: usize) -> Self {
        self.total_before_cap = Some(self.raw_unknown.len());
        if self.raw_unknown.len() > n {
            self.raw_unknown
                .sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes).then(a.path.cmp(&b.path)));
            self.raw_unknown.truncate(n);
        }
        self
    }

    pub fn build(self) -> AiCandidateSet {
        let candidates_total_before_cap = self.total_before_cap.unwrap_or(self.raw_unknown.len());
        let truncated = candidates_total_before_cap > self.raw_unknown.len();
        let estimated_input_tokens = self.raw_unknown.len() * 8 + 200;
        AiCandidateSet {
            pre_classified: self.pre_classified,
            candidates: self.raw_unknown,
            estimated_input_tokens,
            total_raw_count: self.raw_file_count,
            candidates_total_before_cap,
            truncated,
            pre_classified_truncated: false,
        }
    }

    /// Index-mode entry point: `files` are unclassified `(path, size)` pairs
    /// (typically from `SnapshotIndex::unclassified_files()`).
    pub fn from_unclassified_files(
        files: &[(String, u64)],
        classified: &HashSet<String>,
        kb: &OsKnowledgeBase,
        indexed_local_prefixes: &[String],
    ) -> Self {
        let mut b = Self::empty();
        for (path, size) in files {
            if classified.contains(path) {
                continue;
            }
            match resolve_unclassified_for_ai(path, *size, kb, indexed_local_prefixes) {
                UnclassifiedAiRouting::Local(entry) => b.pre_classified.push(entry),
                UnclassifiedAiRouting::SendToAi { cleanup_hint } => {
                    let ext = std::path::Path::new(path)
                        .extension()
                        .and_then(|e| e.to_str())
                        .map(|s| format!(".{s}"));
                    let (cleanup_source, cleanup_hint, retention_days) = cleanup_hint
                        .map(|h| {
                            (
                                Some(h.source.to_string()),
                                Some(h.hint.to_string()),
                                Some(h.retention_days),
                            )
                        })
                        .unwrap_or((None, None, None));
                    b.raw_unknown.push(AiCandidate {
                        path: path.clone(),
                        size_bytes: *size,
                        is_dir: false,
                        child_count: None,
                        extension: ext,
                        cleanup_source,
                        cleanup_hint,
                        retention_days,
                        member_paths: vec![],
                        delete_target: None,
                    });
                }
            }
        }
        b.raw_file_count = b.raw_unknown.len();
        b
    }

    /// Adds low-confidence cleanup hints for paths still routed to the model.
    pub fn annotate_ai_cleanup_patterns(mut self) -> Self {
        for candidate in &mut self.raw_unknown {
            if candidate.cleanup_source.is_some() {
                continue;
            }
            if let Some(hint) = ai_cleanup_hint_for_path(&candidate.path) {
                if hint_source_skips_ai(hint.source) {
                    continue;
                }
                candidate.cleanup_source = Some(hint.source.to_string());
                candidate.cleanup_hint = Some(hint.hint.to_string());
                candidate.retention_days = Some(hint.retention_days);
            }
        }
        self
    }
}

#[derive(Clone, Copy)]
pub(crate) struct AiCleanupHint {
    pub(crate) source: &'static str,
    pub(crate) hint: &'static str,
    pub(crate) retention_days: u32,
}

/// High-confidence cleanup hints are resolved locally (option A) and never sent to the model.
pub fn hint_source_skips_ai(source: &str) -> bool {
    matches!(source, "system_temp" | "ai_tool_cache")
}

const GENERIC_BUILD_MARKERS: &[&str] = &[
    "/node_modules/",
    "/target/",
    "/.gradle/",
    "/build/",
    "/dist/",
    "/.next/",
    "/out/",
    "/__pycache__/",
    "/.pytest_cache/",
    "/.mypy_cache/",
    "/.turbo/",
    "/.parcel-cache/",
    "/.npm/",
    "/.yarn/",
    "/.pnpm-store/",
    "/pods/",
    "/deriveddata/",
    "/.dart_tool/",
    "/.pub-cache/",
    "/.cargo/registry/",
    "/.cargo/git/",
    "/.rustup/toolchains/",
    "/.nuget/packages/",
    "/.m2/repository/",
    "/.venv/",
    "/.tox/",
];

fn path_matches_generic_cache_or_temp(path: &str) -> bool {
    let lower = path.replace('\\', "/").to_ascii_lowercase();
    lower.contains("/caches/")
        || lower.contains("/cache/")
        || lower.contains(".cache/")
        || lower.contains("/tmp/")
        || lower.contains("/temp/")
        || lower.ends_with(".tmp")
}

fn path_matches_common_regeneratable_build(path: &str) -> bool {
    let lower = path.replace('\\', "/").to_ascii_lowercase();
    GENERIC_BUILD_MARKERS.iter().any(|marker| lower.contains(marker))
}

fn path_under_indexed_prefix(path: &str, prefixes: &[String]) -> bool {
    let normalized = path.replace('\\', "/");
    prefixes.iter().any(|prefix| {
        let prefix = prefix.replace('\\', "/");
        if prefix.is_empty() {
            return false;
        }
        normalized == prefix
            || normalized
                .strip_prefix(&prefix)
                .is_some_and(|rest| rest.starts_with('/'))
    })
}

pub(crate) fn pre_classified_from_kb(path: &str, size_bytes: u64, kb: &OsKnowledgeBase) -> Option<PreClassifiedEntry> {
    let known = kb.classify_path(path)?;
    Some(PreClassifiedEntry {
        path: path.to_string(),
        size_bytes,
        is_dir: false,
        category: known.category,
        confidence: if known.confidence == Confidence::High {
            "high".into()
        } else {
            "medium".into()
        },
        reason: known.reason,
        deletable: known.deletable,
    })
}

pub(crate) fn pre_classified_from_hint(path: &str, size_bytes: u64, hint: AiCleanupHint) -> Option<PreClassifiedEntry> {
    if !hint_source_skips_ai(hint.source) {
        return None;
    }
    let (category, deletable) = match hint.source {
        "system_temp" => (EntryCategory::Temp, true),
        "ai_tool_cache" => (EntryCategory::Cache, true),
        _ => (EntryCategory::Cache, true),
    };
    Some(PreClassifiedEntry {
        path: path.to_string(),
        size_bytes,
        is_dir: false,
        category,
        confidence: "high".to_string(),
        reason: hint.hint.to_string(),
        deletable,
    })
}

pub(crate) fn pre_classified_from_heuristics(path: &str, size_bytes: u64) -> Option<PreClassifiedEntry> {
    if path_matches_generic_cache_or_temp(path) {
        return Some(PreClassifiedEntry {
            path: path.to_string(),
            size_bytes,
            is_dir: false,
            category: EntryCategory::Cache,
            confidence: "medium".to_string(),
            reason: "Path matches cache or temp segment; safe to review locally without AI.".to_string(),
            deletable: true,
        });
    }
    if path_matches_common_regeneratable_build(path) {
        return Some(PreClassifiedEntry {
            path: path.to_string(),
            size_bytes,
            is_dir: false,
            category: EntryCategory::BuildArtifact,
            confidence: "high".to_string(),
            reason: "Common regeneratable build or dependency output; excluded from AI analysis.".to_string(),
            deletable: true,
        });
    }
    None
}

pub(crate) fn pre_classified_under_index_prefix(
    path: &str,
    size_bytes: u64,
    prefixes: &[String],
    kb: &OsKnowledgeBase,
) -> Option<PreClassifiedEntry> {
    if !path_under_indexed_prefix(path, prefixes) {
        return None;
    }
    pre_classified_from_kb(path, size_bytes, kb).or_else(|| {
        Some(PreClassifiedEntry {
            path: path.to_string(),
            size_bytes,
            is_dir: false,
            category: EntryCategory::BuildArtifact,
            confidence: "high".to_string(),
            reason: "Under a locally classified cache, temp, or build path from scan index.".to_string(),
            deletable: true,
        })
    })
}

pub enum UnclassifiedAiRouting {
    Local(PreClassifiedEntry),
    SendToAi {
        cleanup_hint: Option<AiCleanupHint>,
    },
}

/// Single gate for whether an unclassified file should be sent to the model.
pub fn resolve_unclassified_for_ai(
    path: &str,
    size_bytes: u64,
    kb: &OsKnowledgeBase,
    indexed_local_prefixes: &[String],
) -> UnclassifiedAiRouting {
    let ctx = crate::coverage_funnel::CoverageFunnelContext::with_exclusion_prefixes(indexed_local_prefixes);
    crate::coverage_funnel::resolve_unclassified_for_coverage(path, size_bytes, kb, &ctx)
        .into_ai_routing(path, size_bytes)
}

/// Prefix paths from indexed Cache / Temp / BuildArtifact entries (scan Tier-1).
pub fn indexed_local_exclusion_prefixes(
    index: &crate::index::SnapshotIndex,
) -> Vec<String> {
    crate::coverage_funnel::coverage_local_exclusion_prefixes(index)
}

pub(crate) fn ai_cleanup_hint_for_path(path: &str) -> Option<AiCleanupHint> {
    let normalized = path.replace('\\', "/");
    let lower = normalized.to_ascii_lowercase();
    let file_name = lower.rsplit('/').next().unwrap_or(lower.as_str());

    if lower.starts_with("/var/tmp/") {
        return Some(AiCleanupHint {
            source: "system_temp",
            hint: "Persistent temp location; review files that have not been needed for about 30 days.",
            retention_days: 30,
        });
    }
    if lower.starts_with("/tmp/")
        || lower.starts_with("/private/tmp/")
        || lower.contains("/appdata/local/temp/")
        || lower.contains("/windows/temp/")
        || lower.contains("/private/var/folders/")
    {
        return Some(AiCleanupHint {
            source: "system_temp",
            hint: "Temporary location; many systems treat files older than about 10 days as stale.",
            retention_days: 10,
        });
    }

    let hidden_ai_tool = lower.contains("/.cursor/")
        || lower.contains("/.windsurf/")
        || lower.contains("/.claude/")
        || lower.contains("/.codex/");
    let known_ai_tool_app_root = AI_TOOL_APP_ROOT_PATTERNS
        .iter()
        .any(|root| lower.contains(root));
    if (hidden_ai_tool || known_ai_tool_app_root)
        && (lower.contains("/cache/")
            || lower.contains("/caches/")
            || lower.contains("/cacheddata/")
            || lower.contains("/code cache/")
            || lower.contains("/gpucache/")
            || lower.contains("/logs/")
            || lower.contains("/tmp/")
            || lower.contains("/temp/"))
    {
        return Some(AiCleanupHint {
            source: "ai_tool_cache",
            hint: "Known AI/editor cache, log, or temp location; review items older than about 30 days.",
            retention_days: 30,
        });
    }

    let looks_ai_generated = lower.contains("ai-output")
        || lower.contains("ai_output")
        || lower.contains("ai-generated")
        || lower.contains("ai_generated")
        || lower.contains("generated-by-ai")
        || lower.contains("llm-output")
        || lower.contains("llm_cache")
        || lower.contains("llm-cache")
        || lower.contains("prompt-cache")
        || lower.contains("chat-export")
        || lower.contains("chat_export")
        || lower.contains("claude-output")
        || lower.contains("cursor-output")
        || lower.contains("codex-output")
        || lower.contains("/.cursor/rules/")
        || lower.contains("/.windsurf/rules/")
        || lower.contains("/.claude/tmp/")
        || lower.contains("/.codex/tmp/");

    if looks_ai_generated {
        let retention_days = if file_name.ends_with(".md") { 90 } else { 30 };
        return Some(AiCleanupHint {
            source: "ai_generated_output",
            hint: "AI-generated sidecar/output pattern; inspect before deleting because it may contain user-authored content.",
            retention_days,
        });
    }

    None
}

impl AiCandidateSet {
    /// Keeps the largest pre-classified entries so the pre-check UI stays
    /// responsive on huge scans (hundreds of GB / many build artifacts).
    pub fn cap_pre_classified_top_n(mut self, n: usize) -> Self {
        if self.pre_classified.len() <= n {
            return self;
        }
        self.pre_classified
            .sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes).then(a.path.cmp(&b.path)));
        self.pre_classified.truncate(n);
        self.pre_classified_truncated = true;
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{EntryCategory, ScanTreeNode};
    use crate::os_knowledge::OsKnowledgeBase;
    use std::collections::HashSet;

    fn leaf(path: &str, size: u64) -> ScanTreeNode {
        ScanTreeNode {
            name: path.rsplit('/').next().unwrap_or(path).to_string(),
            path: path.to_string(),
            is_dir: false,
            size_bytes: size,
            entry_id: None,
            children: vec![],
        }
    }
    fn dir_with_children(path: &str, size: u64, children: Vec<ScanTreeNode>) -> ScanTreeNode {
        ScanTreeNode {
            name: path.rsplit('/').next().unwrap_or(path).to_string(),
            path: path.to_string(),
            is_dir: true,
            size_bytes: size,
            entry_id: None,
            children,
        }
    }

    #[test]
    fn tier1_hits_are_excluded() {
        let tree = leaf("/Users/x/Library/Caches/foo.bin", 1000);
        let mut classified = HashSet::new();
        classified.insert("/Users/x/Library/Caches/foo.bin".to_string());
        let kb =
            OsKnowledgeBase::from_yaml("version: 1\nmacos: []\nwindows: []\nlinux: []", "macos")
                .unwrap();
        let set = AiCandidateBuilder::from_tree(&tree, &classified, &kb).build();
        assert!(set.candidates.is_empty());
        assert!(set.pre_classified.is_empty());
    }

    #[test]
    fn node_modules_becomes_pre_classified_not_candidate() {
        let yaml = include_str!("../../../rules/os_knowledge.yaml");
        let kb = OsKnowledgeBase::from_yaml(yaml, "macos").unwrap();
        let tree = leaf("/Users/x/Projects/app/node_modules/lodash/index.js", 5000);
        let set = AiCandidateBuilder::from_tree(&tree, &HashSet::new(), &kb).build();
        assert_eq!(set.pre_classified.len(), 1);
        assert!(set.candidates.is_empty());
    }

    #[test]
    fn aggregate_folds_large_directory() {
        let kb =
            OsKnowledgeBase::from_yaml("version: 1\nmacos: []\nwindows: []\nlinux: []", "macos")
                .unwrap();
        let children: Vec<_> = (0..25)
            .map(|i| leaf(&format!("/Users/x/big_dir/file_{i}.dat"), 100))
            .collect();
        let tree = dir_with_children("/Users/x/big_dir", 2500, children);
        let set = AiCandidateBuilder::from_tree(&tree, &HashSet::new(), &kb)
            .aggregate_by_dir(20)
            .build();
        assert_eq!(set.candidates.len(), 1);
        assert_eq!(set.candidates[0].child_count, Some(25));
        assert_eq!(set.candidates[0].member_paths.len(), 25);
        assert!(set.candidates[0]
            .member_paths
            .contains(&"/Users/x/big_dir/file_0.dat".to_string()));
        assert_eq!(set.total_raw_count, 25);
        assert!(!set.truncated);
    }

    #[test]
    fn cap_pre_classified_keeps_largest() {
        let kb =
            OsKnowledgeBase::from_yaml("version: 1\nmacos: []\nwindows: []\nlinux: []", "macos")
                .unwrap();
        let mut builder = AiCandidateBuilder::from_tree(&leaf("/tmp/x", 1), &HashSet::new(), &kb);
        for i in 0..50 {
            builder.push_pre_classified(PreClassifiedEntry {
                path: format!("/Users/x/art_{i}"),
                size_bytes: (i + 1) as u64,
                is_dir: true,
                category: EntryCategory::BuildArtifact,
                confidence: "high".into(),
                reason: "t".into(),
                deletable: true,
            });
        }
        let set = builder.build().cap_pre_classified_top_n(10);
        assert!(set.pre_classified_truncated);
        assert_eq!(set.pre_classified.len(), 10);
        assert_eq!(set.pre_classified[0].path, "/Users/x/art_49");
    }

    #[test]
    fn aggregate_caps_member_paths_to_largest() {
        let kb =
            OsKnowledgeBase::from_yaml("version: 1\nmacos: []\nwindows: []\nlinux: []", "macos")
                .unwrap();
        let children: Vec<_> = (0..250)
            .map(|i| {
                leaf(
                    &format!("/Users/x/huge_dir/file_{i:03}.dat"),
                    (i + 1) as u64,
                )
            })
            .collect();
        let tree = dir_with_children("/Users/x/huge_dir", 250 * 251 / 2, children);
        let set = AiCandidateBuilder::from_tree(&tree, &HashSet::new(), &kb)
            .aggregate_by_dir(20)
            .build();
        assert_eq!(set.candidates.len(), 1);
        assert_eq!(set.candidates[0].child_count, Some(250));
        assert_eq!(
            set.candidates[0].member_paths.len(),
            DEFAULT_MAX_MEMBER_PATHS
        );
        assert_eq!(
            set.candidates[0].delete_target.as_deref(),
            Some("volward-ai-aggregate:v1:/Users/x/huge_dir")
        );
        // Largest members kept first (file_249 = 250 bytes).
        assert!(set.candidates[0]
            .member_paths
            .contains(&"/Users/x/huge_dir/file_249.dat".to_string()));
        assert!(!set.candidates[0]
            .member_paths
            .contains(&"/Users/x/huge_dir/file_000.dat".to_string()));
        let encoded = serde_json::to_value(&set.candidates[0]).unwrap();
        assert!(encoded.get("delete_member_paths").is_none());
    }

    #[test]
    fn cap_top_n_keeps_largest_and_flags_truncation() {
        let kb =
            OsKnowledgeBase::from_yaml("version: 1\nmacos: []\nwindows: []\nlinux: []", "macos")
                .unwrap();
        let files: Vec<(String, u64)> = (0..10)
            .map(|i| (format!("/Users/x/dir_{i}/file.dat"), (i as u64 + 1) * 100))
            .collect();
        let set = AiCandidateBuilder::from_unclassified_files(&files, &HashSet::new(), &kb, &[])
            .cap_top_n(3)
            .build();
        assert_eq!(set.candidates.len(), 3);
        assert_eq!(set.candidates[0].size_bytes, 1000);
        assert_eq!(set.candidates[2].size_bytes, 800);
        assert!(set.truncated);
        assert_eq!(set.candidates_total_before_cap, 10);
        assert_eq!(set.total_raw_count, 10);
    }

    #[test]
    fn cap_top_n_below_limit_is_not_truncated() {
        let kb =
            OsKnowledgeBase::from_yaml("version: 1\nmacos: []\nwindows: []\nlinux: []", "macos")
                .unwrap();
        let files = vec![("/Users/x/a.dat".to_string(), 10u64)];
        let set = AiCandidateBuilder::from_unclassified_files(&files, &HashSet::new(), &kb, &[])
            .cap_top_n(DEFAULT_CANDIDATE_CAP)
            .build();
        assert!(!set.truncated);
        assert_eq!(set.candidates_total_before_cap, 1);
    }

    #[test]
    fn token_estimate_positive_for_nonempty() {
        let kb =
            OsKnowledgeBase::from_yaml("version: 1\nmacos: []\nwindows: []\nlinux: []", "macos")
                .unwrap();
        let tree = leaf("/Users/x/Projects/old/weird_thing.xyz", 50000);
        let set = AiCandidateBuilder::from_tree(&tree, &HashSet::new(), &kb).build();
        assert!(set.estimated_input_tokens > 0);
    }

    #[test]
    fn from_unclassified_files_aggregate_folds_siblings() {
        let kb =
            OsKnowledgeBase::from_yaml("version: 1\nmacos: []\nwindows: []\nlinux: []", "macos")
                .unwrap();
        let files: Vec<(String, u64)> = (0..25)
            .map(|i| (format!("/Users/x/big_dir/file_{i}.dat"), 100))
            .collect();
        let set = AiCandidateBuilder::from_unclassified_files(&files, &HashSet::new(), &kb, &[])
            .aggregate_by_dir(20)
            .build();
        assert_eq!(set.candidates.len(), 1);
        assert_eq!(set.candidates[0].path, "/Users/x/big_dir");
        assert_eq!(set.candidates[0].child_count, Some(25));
        assert_eq!(set.candidates[0].size_bytes, 2500);
        assert_eq!(set.candidates[0].member_paths.len(), 25);
    }

    #[test]
    fn resolve_routes_high_confidence_hints_to_local_only() {
        let kb =
            OsKnowledgeBase::from_yaml("version: 1\nmacos: []\nwindows: []\nlinux: []", "macos")
                .unwrap();
        let path = "/Users/x/Library/Application Support/Cursor/CachedData/x";
        match resolve_unclassified_for_ai(path, 10, &kb, &[]) {
            UnclassifiedAiRouting::Local(entry) => {
                assert_eq!(entry.category, EntryCategory::Cache);
                assert!(entry.deletable);
            }
            UnclassifiedAiRouting::SendToAi { .. } => panic!("expected local routing"),
        }
        let ai_output = "/Users/x/project/llm-output/note.md";
        match resolve_unclassified_for_ai(ai_output, 5, &kb, &[]) {
            UnclassifiedAiRouting::SendToAi { cleanup_hint } => {
                assert_eq!(cleanup_hint.unwrap().source, "ai_generated_output");
            }
            UnclassifiedAiRouting::Local(_) => panic!("ai output still needs model review"),
        }
    }

    #[test]
    fn annotates_ai_cleanup_patterns_inside_snapshot_only() {
        let kb =
            OsKnowledgeBase::from_yaml("version: 1\nmacos: []\nwindows: []\nlinux: []", "macos")
                .unwrap();
        let files = vec![
            ("/tmp/volward-ai/a.tmp".to_string(), 10),
            (
                "/Users/x/Library/Application Support/Cursor/CachedData/blob".to_string(),
                20,
            ),
            ("/Users/x/project/ai-output/summary.md".to_string(), 30),
            ("/Users/x/project/README.md".to_string(), 40),
            ("/Users/x/project/temp/draft.txt".to_string(), 50),
            ("/Users/x/Projects/codex/logs/app.log".to_string(), 60),
        ];
        let set = AiCandidateBuilder::from_unclassified_files(&files, &HashSet::new(), &kb, &[])
            .annotate_ai_cleanup_patterns()
            .build();

        assert!(set.pre_classified.len() >= 3);
        assert!(
            set.pre_classified
                .iter()
                .any(|entry| entry.path.contains("CachedData"))
        );
        assert!(
            set.pre_classified
                .iter()
                .any(|entry| entry.path.contains("volward-ai"))
        );
        assert!(
            set.pre_classified
                .iter()
                .any(|entry| entry.path.contains("draft.txt")),
            "project temp segment matches local cache/temp heuristics"
        );

        let by_path = set
            .candidates
            .iter()
            .map(|candidate| (candidate.path.as_str(), candidate))
            .collect::<std::collections::HashMap<_, _>>();
        assert_eq!(
            by_path["/Users/x/project/ai-output/summary.md"]
                .cleanup_source
                .as_deref(),
            Some("ai_generated_output")
        );
        assert_eq!(
            by_path["/Users/x/project/ai-output/summary.md"].retention_days,
            Some(90)
        );
        assert_eq!(
            by_path.get("/Users/x/project/README.md").unwrap().cleanup_source, None,
            "plain markdown documents must not be treated as AI output"
        );
        assert!(
            by_path.contains_key("/Users/x/Projects/codex/logs/app.log"),
            "codex log path still routed to AI"
        );
        assert_eq!(
            by_path.get("/Users/x/Projects/codex/logs/app.log").unwrap().cleanup_source, None,
            "ordinary project paths named after AI tools are not app cache roots"
        );
    }

    #[test]
    fn aggregate_cleanup_meta_uses_all_children_before_member_cap() {
        let kb =
            OsKnowledgeBase::from_yaml("version: 1\nmacos: []\nwindows: []\nlinux: []", "macos")
                .unwrap();
        let mut files: Vec<(String, u64)> = (0..250)
            .map(|i| (format!("/Users/x/project/mixed/file_{i:03}.dat"), 1000))
            .collect();
        files.push((
            "/Users/x/project/mixed/prompt-cache-note.txt".to_string(),
            1,
        ));

        let set = AiCandidateBuilder::from_unclassified_files(&files, &HashSet::new(), &kb, &[])
            .annotate_ai_cleanup_patterns()
            .aggregate_by_dir(20)
            .build();

        assert_eq!(set.candidates.len(), 1);
        let aggregate = &set.candidates[0];
        assert_eq!(aggregate.path, "/Users/x/project/mixed");
        assert_eq!(aggregate.member_paths.len(), DEFAULT_MAX_MEMBER_PATHS);
        assert!(
            !aggregate
                .member_paths
                .contains(&"/Users/x/project/mixed/prompt-cache-note.txt".to_string()),
            "small hint file is outside the capped display members"
        );
        assert_eq!(
            aggregate.cleanup_source.as_deref(),
            Some("ai_generated_output")
        );
        assert_eq!(aggregate.retention_days, Some(30));
    }
}
