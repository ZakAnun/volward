pub mod ai_analysis;
pub mod ai_candidates;
pub mod os_knowledge;
pub mod classify;
pub mod capability;
pub mod capability_job;
pub mod capability_registry;
pub mod cleanup_candidates;
pub mod delete;
pub mod duplicates;
pub mod index;
pub mod large_files;
pub mod manifest;
pub mod model;
pub mod platform;
pub mod rules;
pub mod scan;
pub mod scan_tree;
pub mod snapshot_catalog;
pub mod string_table;

pub use ai_analysis::{
    compute_result_cache_key, AiAnalysisResult, AiTokenUsage, AiVerdictEntry,
};
pub use capability::*;
pub use capability_job::*;
pub use capability_registry::*;
pub use cleanup_candidates::*;
pub use duplicates::*;
pub use large_files::*;
pub use ai_candidates::{
    ai_aggregate_delete_target, ai_aggregate_path_from_delete_target, AiCandidate,
    AiCandidateBuilder, AiCandidateSet, PreClassifiedEntry, AI_AGGREGATE_DELETE_TARGET_PREFIX,
    DEFAULT_CANDIDATE_CAP, DEFAULT_MAX_MEMBER_PATHS, DEFAULT_PRECLASSIFIED_CAP,
};
pub use os_knowledge::{Confidence, KnownSafeEntry, OsKnowledgeBase};
pub use classify::Classifier;
pub use delete::DeleteOrchestrator;
pub use index::{
    SnapshotDirectoryRecord, SnapshotEntryRecord, SnapshotIndex, SnapshotIndexBuilder,
    SnapshotNodeRecord, SnapshotQueryResult,
};
pub use model::*;
pub use platform::{PlatformError, PlatformStorage, WalkAction, WalkOptions};
pub use scan::ScanOrchestrator;
pub use snapshot_catalog::SnapshotCatalog;
pub use string_table::StringTable;
