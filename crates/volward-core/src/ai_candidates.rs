use std::collections::HashSet;
use serde::Serialize;
use crate::model::{EntryCategory, ScanTreeNode};
use crate::os_knowledge::{Confidence, OsKnowledgeBase};

#[derive(Debug, Clone, Serialize)]
pub struct AiCandidate {
    pub path: String,
    pub size_bytes: u64,
    pub is_dir: bool,
    pub child_count: Option<usize>,
    pub extension: Option<String>,
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
    pub total_raw_count: usize,
}

pub struct AiCandidateBuilder {
    pre_classified: Vec<PreClassifiedEntry>,
    raw_unknown: Vec<AiCandidate>,
}

impl AiCandidateBuilder {
    pub fn from_tree(
        tree: &ScanTreeNode,
        classified: &HashSet<String>,
        kb: &OsKnowledgeBase,
    ) -> Self {
        let mut b = Self { pre_classified: vec![], raw_unknown: vec![] };
        b.walk(tree, classified, kb);
        b
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
                let total_size: u64 = children.iter().map(|c| c.size_bytes).sum();
                self.raw_unknown.push(AiCandidate {
                    path: parent,
                    size_bytes: total_size,
                    is_dir: true,
                    child_count: Some(children.len()),
                    extension: None,
                });
            } else {
                self.raw_unknown.append(&mut children);
            }
        }
        self.raw_unknown.extend(singletons);
        self
    }

    pub fn build(self) -> AiCandidateSet {
        let total_raw_count = self.raw_unknown.len();
        let estimated_input_tokens = self.raw_unknown.len() * 8 + 200;
        AiCandidateSet {
            pre_classified: self.pre_classified,
            candidates: self.raw_unknown,
            estimated_input_tokens,
            total_raw_count,
        }
    }

    /// Index-mode entry point: `files` are unclassified `(path, size)` pairs
    /// (typically from `SnapshotIndex::unclassified_files()`).
    pub fn from_unclassified_files(
        files: &[(String, u64)],
        classified: &HashSet<String>,
        kb: &OsKnowledgeBase,
    ) -> Self {
        let mut b = Self { pre_classified: vec![], raw_unknown: vec![] };
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
            });
        }
        b
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;
    use crate::model::ScanTreeNode;
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
    }
}
