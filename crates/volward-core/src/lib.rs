pub mod ai_analysis;
pub mod ai_candidates;
pub mod ai_coverage;
pub mod ai_coverage_propagate;
pub mod ai_coverage_tree;
pub mod capability;
pub mod capability_job;
pub mod capability_registry;
pub mod classify;
pub mod cleanup_candidates;
pub mod coverage_funnel;
pub mod delete;
pub mod directory_role;
pub mod duplicates;
pub mod index;
pub mod large_files;
pub mod manifest;
pub mod model;
pub mod os_knowledge;
pub mod pause_store;
pub mod platform;
pub mod rules;
pub mod scan;
pub mod scan_tree;
pub mod similar_photos;
pub mod snapshot_catalog;
pub mod string_table;

pub use ai_analysis::{compute_result_cache_key, AiAnalysisResult, AiTokenUsage, AiVerdictEntry};
pub use ai_candidates::{
    ai_aggregate_delete_target, ai_aggregate_path_from_delete_target, hint_source_skips_ai,
    indexed_local_exclusion_prefixes, resolve_unclassified_for_ai, AiCandidate, AiCandidateBuilder,
    AiCandidateSet, PreClassifiedEntry, UnclassifiedAiRouting, AI_AGGREGATE_DELETE_TARGET_PREFIX,
    DEFAULT_CANDIDATE_CAP, DEFAULT_MAX_MEMBER_PATHS, DEFAULT_PRECLASSIFIED_CAP,
};
pub use ai_coverage::{
    build_ai_coverage_plan, coverage_group_member_paths, AiCoveragePlan, AiCoverageRow,
    AiCoverageRowKind, AI_COVERAGE_PLAN_VERSION,
};
pub use ai_coverage_propagate::{apply_dir_verdict, CoverageLocalVerdict};
pub use ai_coverage_tree::{
    build_ai_tree_plan, expand_tree_drill_children, AiTreeNode, AiTreePlan,
    AI_COVERAGE_TREE_PLAN_VERSION,
};
pub use capability::*;
pub use capability_job::*;
pub use capability_registry::*;
pub use classify::Classifier;
pub use cleanup_candidates::*;
pub use coverage_funnel::{
    build_coverage_funnel_context, build_funnel_context_for_files,
    compute_coverage_funnel_stats, coverage_funnel_context_for_path,
    coverage_local_exclusion_prefixes, deepest_project_ancestor_for_path,
    path_under_longest_prefix, resolve_unclassified_for_coverage, CoverageFileResolution,
    CoverageFunnelContext, CoverageFunnelContextMap, CoverageFunnelStats,
};
pub use delete::DeleteOrchestrator;
pub use directory_role::{
    classify_directory_role, collect_project_anchor_paths, DirectoryRole, PRUNED_VCS,
};
pub use duplicates::*;
pub use index::{
    DirectoryRecord, EntryRecord, SnapshotDirectoryRecord, SnapshotEntryRecord, SnapshotIndex,
    SnapshotIndexBuilder, SnapshotIndexWire, SnapshotNodeRecord, SnapshotQueryResult,
};
pub use large_files::*;
pub use model::*;
pub use os_knowledge::{Confidence, KnownSafeEntry, OsKnowledgeBase};
pub use platform::{PlatformError, PlatformStorage, WalkAction, WalkOptions};
pub use scan::ScanOrchestrator;
pub use similar_photos::*;
pub use snapshot_catalog::SnapshotCatalog;
pub use string_table::StringTable;
