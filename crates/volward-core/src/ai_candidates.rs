use std::collections::HashSet;
use serde::Serialize;
use crate::model::{EntryCategory, ScanTreeNode};
use crate::os_knowledge::{Confidence, OsKnowledgeBase};

/// Default maximum number of candidates sent to the model / UI.
pub const DEFAULT_CANDIDATE_CAP: usize = 150;
/// Max concrete member paths retained per aggregated directory candidate.
/// Keeps the FFI JSON bounded even when a single parent has huge fan-out.
pub const DEFAULT_MAX_MEMBER_PATHS: usize = 200;
/// Max Tier-2 / KB pre-classified rows shown in the pre-check UI.
pub const DEFAULT_PRECLASSIFIED_CAP: usize = 200;
pub const AI_AGGREGATE_DELETE_TARGET_PREFIX: &str = "volward-ai-aggregate:v1:";

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
        b.walk(tree, classified, kb);
        b.raw_file_count = b.raw_unknown.len();
        b
    }

    /// Adds an already-classified entry (e.g. a Tier-2 index hit) so the
    /// pre-check UI can offer it without another AI round-trip.
    pub fn push_pre_classified(&mut self, entry: PreClassifiedEntry) {
        self.pre_classified.push(entry);
    }

    fn walk(&mut self, node: &ScanTreeNode, classified: &HashSet<String>, kb: &OsKnowledgeBase) {
        if classified.contains(&node.path) {
            return;
        }
        if let Some(e) = kb.classify_path(&node.path) {
            self.pre_classified.push(PreClassifiedEntry {
                path: node.path.clone(),
                size_bytes: node.size_bytes,
                is_dir: node.is_dir,
                category: e.category,
                confidence: if e.confidence == Confidence::High {
                    "high".into()
                } else {
                    "medium".into()
                },
                reason: e.reason,
                deletable: e.deletable,
            });
            return;
        }
        if node.is_dir && !node.children.is_empty() {
            for child in &node.children {
                self.walk(child, classified, kb);
            }
        } else if !node.is_dir {
            let ext = std::path::Path::new(&node.path)
                .extension()
                .and_then(|e| e.to_str())
                .map(|s| format!(".{s}"));
            self.raw_unknown.push(AiCandidate {
                path: node.path.clone(),
                size_bytes: node.size_bytes,
                is_dir: false,
                child_count: None,
                extension: ext,
                member_paths: vec![],
                delete_target: None,
            });
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
                // Prefer the largest members when capping the model/UI list.
                if children.len() > DEFAULT_MAX_MEMBER_PATHS {
                    children.sort_by(|a, b| {
                        b.size_bytes
                            .cmp(&a.size_bytes)
                            .then(a.path.cmp(&b.path))
                    });
                    children.truncate(DEFAULT_MAX_MEMBER_PATHS);
                }
                let member_paths: Vec<String> =
                    children.iter().map(|c| c.path.clone()).collect();
                let delete_target = ai_aggregate_delete_target(&parent);
                self.raw_unknown.push(AiCandidate {
                    path: parent,
                    size_bytes: total_size,
                    is_dir: true,
                    child_count: Some(child_count),
                    extension: None,
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
        let candidates_total_before_cap =
            self.total_before_cap.unwrap_or(self.raw_unknown.len());
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
    ) -> Self {
        let mut b = Self::empty();
        for (path, size) in files {
            if classified.contains(path) {
                continue;
            }
            if let Some(e) = kb.classify_path(path) {
                b.pre_classified.push(PreClassifiedEntry {
                    path: path.clone(),
                    size_bytes: *size,
                    is_dir: false,
                    category: e.category,
                    confidence: if e.confidence == Confidence::High {
                        "high".into()
                    } else {
                        "medium".into()
                    },
                    reason: e.reason,
                    deletable: e.deletable,
                });
                continue;
            }
            let ext = std::path::Path::new(path)
                .extension()
                .and_then(|e| e.to_str())
                .map(|s| format!(".{s}"));
            b.raw_unknown.push(AiCandidate {
                path: path.clone(),
                size_bytes: *size,
                is_dir: false,
                child_count: None,
                extension: ext,
                member_paths: vec![],
                delete_target: None,
            });
        }
        b.raw_file_count = b.raw_unknown.len();
        b
    }
}

impl AiCandidateSet {
    /// Keeps the largest pre-classified entries so the pre-check UI stays
    /// responsive on huge scans (hundreds of GB / many build artifacts).
    pub fn cap_pre_classified_top_n(mut self, n: usize) -> Self {
        if self.pre_classified.len() <= n {
            return self;
        }
        self.pre_classified.sort_by(|a, b| {
            b.size_bytes
                .cmp(&a.size_bytes)
                .then(a.path.cmp(&b.path))
        });
        self.pre_classified.truncate(n);
        self.pre_classified_truncated = true;
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;
    use crate::model::{EntryCategory, ScanTreeNode};
    use crate::os_knowledge::OsKnowledgeBase;

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
        let kb = OsKnowledgeBase::from_yaml(
            "version: 1\nmacos: []\nwindows: []\nlinux: []", "macos").unwrap();
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
        let kb = OsKnowledgeBase::from_yaml(
            "version: 1\nmacos: []\nwindows: []\nlinux: []", "macos").unwrap();
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
        let kb = OsKnowledgeBase::from_yaml(
            "version: 1\nmacos: []\nwindows: []\nlinux: []", "macos").unwrap();
        let mut builder = AiCandidateBuilder::from_tree(
            &leaf("/tmp/x", 1),
            &HashSet::new(),
            &kb,
        );
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
        let kb = OsKnowledgeBase::from_yaml(
            "version: 1\nmacos: []\nwindows: []\nlinux: []", "macos").unwrap();
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
        let kb = OsKnowledgeBase::from_yaml(
            "version: 1\nmacos: []\nwindows: []\nlinux: []", "macos").unwrap();
        let files: Vec<(String, u64)> = (0..10)
            .map(|i| (format!("/Users/x/dir_{i}/file.dat"), (i as u64 + 1) * 100))
            .collect();
        let set = AiCandidateBuilder::from_unclassified_files(&files, &HashSet::new(), &kb)
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
        let kb = OsKnowledgeBase::from_yaml(
            "version: 1\nmacos: []\nwindows: []\nlinux: []", "macos").unwrap();
        let files = vec![("/Users/x/a.dat".to_string(), 10u64)];
        let set = AiCandidateBuilder::from_unclassified_files(&files, &HashSet::new(), &kb)
            .cap_top_n(DEFAULT_CANDIDATE_CAP)
            .build();
        assert!(!set.truncated);
        assert_eq!(set.candidates_total_before_cap, 1);
    }

    #[test]
    fn token_estimate_positive_for_nonempty() {
        let kb = OsKnowledgeBase::from_yaml(
            "version: 1\nmacos: []\nwindows: []\nlinux: []", "macos").unwrap();
        let tree = leaf("/Users/x/Projects/old/weird_thing.xyz", 50000);
        let set = AiCandidateBuilder::from_tree(&tree, &HashSet::new(), &kb).build();
        assert!(set.estimated_input_tokens > 0);
    }

    #[test]
    fn from_unclassified_files_aggregate_folds_siblings() {
        let kb = OsKnowledgeBase::from_yaml(
            "version: 1\nmacos: []\nwindows: []\nlinux: []", "macos").unwrap();
        let files: Vec<(String, u64)> = (0..25)
            .map(|i| (format!("/Users/x/big_dir/file_{i}.dat"), 100))
            .collect();
        let set = AiCandidateBuilder::from_unclassified_files(&files, &HashSet::new(), &kb)
            .aggregate_by_dir(20)
            .build();
        assert_eq!(set.candidates.len(), 1);
        assert_eq!(set.candidates[0].path, "/Users/x/big_dir");
        assert_eq!(set.candidates[0].child_count, Some(25));
        assert_eq!(set.candidates[0].size_bytes, 2500);
        assert_eq!(set.candidates[0].member_paths.len(), 25);
    }
}
