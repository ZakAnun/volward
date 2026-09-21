use serde::{Deserialize, Serialize};

/// Analyze-path candidate. Never includes `member_paths` (delete-only).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AnalyzeCandidate {
    pub path: String,
    pub size_bytes: u64,
    pub is_dir: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub child_count: Option<usize>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub extension: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cleanup_source: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cleanup_hint: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub retention_days: Option<u32>,
}

/// Directory node for tree coverage analyze (compact stats only — no member file paths).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AnalyzeTreeNode {
    pub path: String,
    pub size_bytes: u64,
    pub file_count: u64,
    pub subdir_count: u64,
    pub role: String,
    pub markers: Vec<String>,
    pub pruned_flags: u32,
    pub top_extensions: Vec<(String, u32)>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AiVerdict {
    pub path: String,
    pub verdict: String,
    pub confidence: String,
    pub reason: String,
}
