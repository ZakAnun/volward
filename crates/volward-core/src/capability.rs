use serde::de::Error as DeError;
use serde::{Deserialize, Deserializer, Serialize};
use thiserror::Error;

pub use crate::model::CapabilityLevel;

pub const CAPABILITY_SCHEMA_VERSION: u32 = 1;
pub const DEFAULT_PAGE_SIZE: u32 = 100;
pub const MAX_PAGE_SIZE: u32 = 500;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Capability {
    LargeFiles,
    CleanupCandidates,
    DuplicateFiles,
    SimilarPhotos,
    Applications,
    BrowserPrivacy,
    SpaceAnalysis,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum LargeFileThresholdPreset {
    #[serde(rename = "50_mb")]
    Mb50,
    #[serde(rename = "100_mb")]
    Mb100,
    #[serde(rename = "1_gb")]
    Gb1,
    #[serde(rename = "5_gb")]
    Gb5,
}

impl LargeFileThresholdPreset {
    pub const fn threshold_bytes(self) -> u64 {
        match self {
            Self::Mb50 => 50_000_000,
            Self::Mb100 => 100_000_000,
            Self::Gb1 => 1_000_000_000,
            Self::Gb5 => 5_000_000_000,
        }
    }
}

impl Default for LargeFileThresholdPreset {
    fn default() -> Self {
        Self::Mb50
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum AgePreset {
    #[serde(rename = "7_days")]
    Days7,
    #[serde(rename = "30_days")]
    Days30,
    #[serde(rename = "90_days")]
    Days90,
}

impl Default for AgePreset {
    fn default() -> Self {
        Self::Days30
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SimilarityPreset {
    Strict,
    Balanced,
    Loose,
}

impl Default for SimilarityPreset {
    fn default() -> Self {
        Self::Balanced
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AnalysisOptions {
    pub root_path: String,
    pub large_file_threshold_bytes: u64,
    pub large_file_threshold_preset: LargeFileThresholdPreset,
    pub age_preset: AgePreset,
    pub similarity_preset: SimilarityPreset,
    pub page_size: u32,
    pub cursor: Option<String>,
}

impl Default for AnalysisOptions {
    fn default() -> Self {
        let large_file_threshold_preset = LargeFileThresholdPreset::default();
        Self {
            root_path: String::new(),
            large_file_threshold_bytes: large_file_threshold_preset.threshold_bytes(),
            large_file_threshold_preset,
            age_preset: AgePreset::default(),
            similarity_preset: SimilarityPreset::default(),
            page_size: DEFAULT_PAGE_SIZE,
            cursor: None,
        }
    }
}

impl AnalysisOptions {
    pub fn validate(&self, _capability: Capability) -> Result<(), AnalysisOptionsError> {
        if self.page_size == 0 || self.page_size > MAX_PAGE_SIZE {
            return Err(AnalysisOptionsError::InvalidPageSize {
                page_size: self.page_size,
            });
        }

        let expected_threshold_bytes = self.large_file_threshold_preset.threshold_bytes();
        if self.large_file_threshold_bytes != expected_threshold_bytes {
            return Err(AnalysisOptionsError::ThresholdPresetMismatch {
                preset: self.large_file_threshold_preset,
                threshold_bytes: self.large_file_threshold_bytes,
                expected_threshold_bytes,
            });
        }

        Ok(())
    }
}

#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum AnalysisOptionsError {
    #[error("page_size must be between 1 and {MAX_PAGE_SIZE}, got {page_size}")]
    InvalidPageSize { page_size: u32 },
    #[error(
        "large_file_threshold_bytes must match {preset:?}: expected {expected_threshold_bytes}, got {threshold_bytes}"
    )]
    ThresholdPresetMismatch {
        preset: LargeFileThresholdPreset,
        threshold_bytes: u64,
        expected_threshold_bytes: u64,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CapabilityAnalysisResult {
    pub schema_version: u32,
    pub capability: Capability,
    pub snapshot_id: String,
    pub root_path: String,
    pub analyzer_version: String,
    pub generated_at_ms: i64,
    pub capability_level: CapabilityLevel,
    pub summary: AnalysisSummary,
    pub groups: Vec<AnalysisGroup>,
    pub next_cursor: Option<String>,
    pub deletion_plan: DeletionPlan,
    pub warnings: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct AnalysisSummary {
    pub item_count: u64,
    pub total_bytes: u64,
    pub safe_count: u64,
    pub review_count: u64,
    pub kept_count: u64,
    pub truncated: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AnalysisGroup {
    pub group_id: String,
    pub group_path: String,
    pub title: String,
    pub item_count: u64,
    pub total_bytes: u64,
    pub safe_count: u64,
    pub review_count: u64,
    pub kept_count: u64,
    pub default_expanded: bool,
    pub items: Vec<AnalysisItem>,
}

impl AnalysisGroup {
    pub fn new(
        group_id: impl Into<String>,
        group_path: impl Into<String>,
        title: impl Into<String>,
        items: Vec<AnalysisItem>,
    ) -> Self {
        let item_count = items.len() as u64;
        let total_bytes = items.iter().map(|item| item.size_bytes).sum();
        let safe_count = items
            .iter()
            .filter(|item| item.recommendation == Recommendation::SafeToRemove)
            .count() as u64;
        let review_count = items
            .iter()
            .filter(|item| item.recommendation == Recommendation::ReviewNeeded)
            .count() as u64;
        let kept_count = items
            .iter()
            .filter(|item| item.recommendation == Recommendation::Keep)
            .count() as u64;

        Self {
            group_id: group_id.into(),
            group_path: group_path.into(),
            title: title.into(),
            item_count,
            total_bytes,
            safe_count,
            review_count,
            kept_count,
            default_expanded: (1..=2).contains(&item_count),
            items,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AnalysisItem {
    pub id: String,
    pub path: String,
    pub display_name: String,
    pub size_bytes: u64,
    pub is_directory: bool,
    pub modified_at_ms: Option<i64>,
    pub recommendation: Recommendation,
    pub confidence: AnalysisConfidence,
    pub reason: String,
    pub evidence: Vec<String>,
    pub delete_target: Option<String>,
    pub preview: Option<AnalysisPreview>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Recommendation {
    SafeToRemove,
    ReviewNeeded,
    Keep,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AnalysisConfidence {
    Low,
    Medium,
    High,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AnalysisPreview {
    pub kind: String,
    pub locatable: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct DeletionPlan {
    pub snapshot_id: String,
    pub target_count: u64,
    pub target_bytes: u64,
    pub targets: Vec<String>,
    pub blocked_targets: Vec<String>,
    pub requires_confirmation: bool,
}

#[derive(Deserialize)]
struct DeletionPlanWire {
    snapshot_id: String,
    target_count: u64,
    target_bytes: u64,
    targets: Vec<String>,
    blocked_targets: Vec<String>,
    requires_confirmation: bool,
}

impl<'de> Deserialize<'de> for DeletionPlan {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let plan = DeletionPlanWire::deserialize(deserializer)?;
        if !plan.requires_confirmation {
            return Err(D::Error::custom("requires_confirmation must be true"));
        }

        Ok(Self {
            snapshot_id: plan.snapshot_id,
            target_count: plan.target_count,
            target_bytes: plan.target_bytes,
            targets: plan.targets,
            blocked_targets: plan.blocked_targets,
            requires_confirmation: true,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CapabilityAnalysisProgress {
    pub job_id: String,
    pub snapshot_id: String,
    pub capability: Capability,
    pub phase: CapabilityAnalysisPhase,
    pub processed: u64,
    pub total: u64,
    pub current_path: Option<String>,
    pub cancelled: bool,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CapabilityAnalysisPhase {
    Preparing,
    Indexing,
    Inspecting,
    Hashing,
    Grouping,
    BuildingResult,
    Completed,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn large_file_presets_use_decimal_bytes() {
        assert_eq!(LargeFileThresholdPreset::Mb50.threshold_bytes(), 50_000_000);
        assert_eq!(
            LargeFileThresholdPreset::Mb100.threshold_bytes(),
            100_000_000
        );
        assert_eq!(
            LargeFileThresholdPreset::Gb1.threshold_bytes(),
            1_000_000_000
        );
        assert_eq!(
            LargeFileThresholdPreset::Gb5.threshold_bytes(),
            5_000_000_000
        );
        assert_eq!(
            AnalysisOptions::default().large_file_threshold_bytes,
            50_000_000
        );
    }

    #[test]
    fn analysis_options_reject_invalid_page_sizes() {
        let too_small = AnalysisOptions {
            page_size: 0,
            ..AnalysisOptions::default()
        };
        let too_large = AnalysisOptions {
            page_size: 501,
            ..AnalysisOptions::default()
        };

        assert!(too_small.validate(Capability::LargeFiles).is_err());
        assert!(too_large.validate(Capability::LargeFiles).is_err());
        assert!(AnalysisOptions::default()
            .validate(Capability::LargeFiles)
            .is_ok());
    }

    #[test]
    fn result_round_trips_using_versioned_snake_case_wire_contract() {
        let result = sample_result();

        let json = serde_json::to_value(&result).unwrap();
        assert_eq!(json["schema_version"], 1);
        assert_eq!(json["capability"], "large_files");
        assert_eq!(json["capability_level"], "full_path");
        assert!(json["next_cursor"].is_null());
        assert_eq!(
            serde_json::from_value::<CapabilityAnalysisResult>(json).unwrap(),
            result
        );
    }

    #[test]
    fn default_expanded_serializes_for_groups_with_one_or_two_items() {
        let one_item = AnalysisGroup::new(
            "group:/tmp/one",
            "/tmp/one",
            "one",
            vec![sample_item("item-1")],
        );
        let two_items = AnalysisGroup::new(
            "group:/tmp/two",
            "/tmp/two",
            "two",
            vec![sample_item("item-1"), sample_item("item-2")],
        );
        let three_items = AnalysisGroup::new(
            "group:/tmp/three",
            "/tmp/three",
            "three",
            vec![
                sample_item("item-1"),
                sample_item("item-2"),
                sample_item("item-3"),
            ],
        );

        assert_eq!(
            serde_json::to_value(one_item).unwrap()["default_expanded"],
            true
        );
        assert_eq!(
            serde_json::to_value(two_items).unwrap()["default_expanded"],
            true
        );
        assert_eq!(
            serde_json::to_value(three_items).unwrap()["default_expanded"],
            false
        );
    }

    #[test]
    fn deletion_plan_rejects_missing_confirmation() {
        let plan = serde_json::json!({
            "snapshot_id": "snapshot-1",
            "target_count": 0,
            "target_bytes": 0,
            "targets": [],
            "blocked_targets": [],
            "requires_confirmation": false,
        });

        let error = serde_json::from_value::<DeletionPlan>(plan).unwrap_err();
        assert!(error.to_string().contains("requires_confirmation"));
    }

    fn sample_result() -> CapabilityAnalysisResult {
        CapabilityAnalysisResult {
            schema_version: 1,
            capability: Capability::LargeFiles,
            snapshot_id: "snapshot-1".to_string(),
            root_path: "/tmp".to_string(),
            analyzer_version: "large_files-v1".to_string(),
            generated_at_ms: 0,
            capability_level: CapabilityLevel::FullPath,
            summary: AnalysisSummary {
                item_count: 1,
                total_bytes: 50_000_000,
                safe_count: 0,
                review_count: 1,
                kept_count: 0,
                truncated: false,
            },
            groups: vec![AnalysisGroup::new(
                "group:/tmp",
                "/tmp",
                "tmp",
                vec![sample_item("item-1")],
            )],
            next_cursor: None,
            deletion_plan: DeletionPlan {
                snapshot_id: "snapshot-1".to_string(),
                target_count: 0,
                target_bytes: 0,
                targets: vec![],
                blocked_targets: vec![],
                requires_confirmation: true,
            },
            warnings: vec![],
        }
    }

    fn sample_item(id: &str) -> AnalysisItem {
        AnalysisItem {
            id: id.to_string(),
            path: format!("/tmp/{id}"),
            display_name: id.to_string(),
            size_bytes: 50_000_000,
            is_directory: false,
            modified_at_ms: None,
            recommendation: Recommendation::ReviewNeeded,
            confidence: AnalysisConfidence::Medium,
            reason: "large_file".to_string(),
            evidence: vec![],
            delete_target: None,
            preview: Some(AnalysisPreview {
                kind: "file".to_string(),
                locatable: true,
            }),
        }
    }
}
