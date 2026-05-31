use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum CapabilityLevel {
    FullPath,
    AppStatsOnly,
    GuidedOnly,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EntryCategory {
    Cache,
    Temp,
    Media,
    AppData,
    Orphan,
    Duplicate,
    System,
    Unknown,
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

#[derive(Debug, Clone)]
pub struct RawFsEntry {
    pub path: String,
    pub is_dir: bool,
    pub size_bytes: u64,
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
}
