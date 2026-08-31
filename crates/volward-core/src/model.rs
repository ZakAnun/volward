use serde::{Deserialize, Serialize};

use crate::manifest::DirFingerprint;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CapabilityLevel {
    FullPath,
    AppStatsOnly,
    GuidedOnly,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EntryCategory {
    /// ~/Library/Caches, .cache/ etc. — deletable, low risk.
    Cache,
    /// /tmp, /temp, .tmp files — deletable, low risk.
    Temp,
    /// Image / video / PDF / DMG files matched by extension — not deletable by default.
    Media,
    /// Application data directories (not yet emitted by Classifier).
    AppData,
    /// Files whose owning application is no longer installed (not yet emitted).
    Orphan,
    /// Duplicate files detected by content hash (not yet emitted).
    Duplicate,
    /// Paths under protected prefixes (/System, /usr …) — never deletable.
    System,
    /// Catch-all for classified entries that don't fit other categories (not yet emitted).
    Unknown,
    /// Build artifacts: node_modules, DerivedData, .gradle/caches — deletable, low risk.
    BuildArtifact,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum RiskLevel {
    Low,
    Medium,
    High,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SourceType {
    Directory,
    File,
    Volume,
    Application,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ScanPhase {
    DiscoveringRoots,
    Walking,
    Classifying,
    Aggregating,
    Done,
    Cancelled,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StorageEntry {
    pub id: String,
    pub display_name: String,
    pub path_or_uri: String,
    pub size_bytes: u64,
    pub category: EntryCategory,
    pub risk_level: RiskLevel,
    pub source_type: SourceType,
    pub deletable: bool,
    pub reason: String,
    /// File modification time in epoch milliseconds; `None` for directories,
    /// unavailable metadata, or old snapshots (never guessed).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub modified_at_ms: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScanTreeNode {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub size_bytes: u64,
    pub entry_id: Option<String>,
    pub children: Vec<ScanTreeNode>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct ScanStats {
    pub paths_seen: u64,
    pub dirs_seen: u64,
    pub files_seen: u64,
    pub files_in_snapshot: u64,
    /// Paths skipped due to permission or I/O errors during directory walk.
    pub paths_skipped: u64,
    pub truncated: bool,
    pub incomplete_reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StorageSnapshot {
    pub snapshot_id: String,
    pub scanned_at_ms: i64,
    pub capability: CapabilityLevel,
    pub volume_total_bytes: u64,
    pub volume_used_bytes: u64,
    pub reclaimable_estimate_bytes: u64,
    pub entries: Vec<StorageEntry>,
    pub tree: ScanTreeNode,
    pub stats: ScanStats,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlatformCapabilities {
    pub level: CapabilityLevel,
    pub can_delete: bool,
    pub can_traverse_system_paths: bool,
    pub permission_hints: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScanProgress {
    pub job_id: String,
    pub phase: ScanPhase,
    pub paths_seen: u64,
    pub bytes_seen: u64,
    pub current_path: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScanRoot {
    pub path: String,
    pub label: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct RawFsEntry {
    pub path: String,
    pub is_dir: bool,
    pub size_bytes: u64,
    pub dir_fingerprint: Option<DirFingerprint>,
    /// File modification time in epoch milliseconds, collected during the
    /// walk without reading file contents; `None` for directories or
    /// unavailable metadata.
    pub modified_at_ms: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VolumeStats {
    pub total_bytes: u64,
    pub available_bytes: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeleteReport {
    pub deleted_count: usize,
    pub failed_paths: Vec<String>,
    pub freed_bytes: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrashEmptyReport {
    pub cleared_count: usize,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry_with(modified_at_ms: Option<i64>) -> StorageEntry {
        StorageEntry {
            id: "e1".to_string(),
            display_name: "a.bin".to_string(),
            path_or_uri: "/root/a.bin".to_string(),
            size_bytes: 10,
            category: EntryCategory::Cache,
            risk_level: RiskLevel::Low,
            source_type: SourceType::File,
            deletable: true,
            reason: "test".to_string(),
            modified_at_ms,
        }
    }

    #[test]
    fn build_artifact_serializes_round_trip() {
        let cat = EntryCategory::BuildArtifact;
        let json = serde_json::to_string(&cat).unwrap();
        let back: EntryCategory = serde_json::from_str(&json).unwrap();
        assert_eq!(cat, back);
    }

    #[test]
    fn storage_entry_round_trips_mtime_present_and_absent() {
        let with_mtime = entry_with(Some(1_700_000_000_000));
        let json = serde_json::to_string(&with_mtime).unwrap();
        let back: StorageEntry = serde_json::from_str(&json).unwrap();
        assert_eq!(back.modified_at_ms, Some(1_700_000_000_000));

        let without_mtime = entry_with(None);
        let json = serde_json::to_string(&without_mtime).unwrap();
        assert!(!json.contains("modified_at_ms"));
        let back: StorageEntry = serde_json::from_str(&json).unwrap();
        assert_eq!(back.modified_at_ms, None);
    }

    #[test]
    fn storage_entry_accepts_old_payloads_without_metadata() {
        let old_json = r#"{
            "id": "e1",
            "display_name": "a.bin",
            "path_or_uri": "/root/a.bin",
            "size_bytes": 10,
            "category": "Cache",
            "risk_level": "Low",
            "source_type": "File",
            "deletable": true,
            "reason": "cache"
        }"#;
        let entry: StorageEntry = serde_json::from_str(old_json).unwrap();
        assert_eq!(entry.modified_at_ms, None);
        assert_eq!(entry.path_or_uri, "/root/a.bin");
    }
}
