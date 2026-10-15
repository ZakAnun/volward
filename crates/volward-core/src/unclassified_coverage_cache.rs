//! Single build of funnel map + unclassified scan artifacts for AI precheck / tree plan.

use std::collections::HashSet;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::ai_coverage_tree::{scan_unclassified_for_coverage, UnclassifiedSubtreeIndex};
use crate::coverage_funnel::{
    build_coverage_funnel_context, CoverageFunnelContextMap, CoverageFunnelStats,
};
use crate::index::SnapshotIndex;
use crate::os_knowledge::OsKnowledgeBase;

pub const UNCLASSIFIED_COVERAGE_CACHE_VERSION: u32 = 1;

#[derive(Debug, Clone)]
pub struct UnclassifiedCoverageCache {
    pub funnel_map: CoverageFunnelContextMap,
    pub classified: HashSet<String>,
    pub funnel_stats: CoverageFunnelStats,
    pub subtree_index: UnclassifiedSubtreeIndex,
    pub tail_file_paths: Vec<(String, u64)>,
    pub total_unclassified: usize,
}

impl UnclassifiedCoverageCache {
    pub fn total_unclassified_from_stats(stats: &CoverageFunnelStats) -> usize {
        (stats.local_safe_files
            + stats.local_keep_files
            + stats.tail_files
            + stats.tree_pending_files) as usize
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CoverageCacheSidecarMeta {
    pub version: u32,
    pub snapshot_id: String,
    pub index_version: u64,
    pub funnel_stats: CoverageFunnelStats,
    pub total_unclassified: usize,
}

impl CoverageCacheSidecarMeta {
    pub fn from_cache(
        snapshot_id: &str,
        index_version: u64,
        cache: &UnclassifiedCoverageCache,
    ) -> Self {
        Self {
            version: UNCLASSIFIED_COVERAGE_CACHE_VERSION,
            snapshot_id: snapshot_id.to_string(),
            index_version,
            funnel_stats: cache.funnel_stats,
            total_unclassified: cache.total_unclassified,
        }
    }
}

pub fn coverage_cache_sidecar_path(snapshot_id: &str) -> PathBuf {
    std::env::var("VOLWARD_SNAPSHOT_CACHE_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| std::env::temp_dir())
        .join(format!("{snapshot_id}.coverage_cache.json"))
}

pub fn save_coverage_cache_sidecar(
    path: &Path,
    meta: &CoverageCacheSidecarMeta,
) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let json = serde_json::to_string(meta).map_err(std::io::Error::other)?;
    std::fs::write(path, json)
}

pub fn load_coverage_cache_sidecar(path: &Path) -> Option<CoverageCacheSidecarMeta> {
    let raw = std::fs::read_to_string(path).ok()?;
    let meta: CoverageCacheSidecarMeta = serde_json::from_str(&raw).ok()?;
    if meta.version != UNCLASSIFIED_COVERAGE_CACHE_VERSION {
        return None;
    }
    Some(meta)
}

pub fn build_unclassified_coverage_cache(
    index: &SnapshotIndex,
    kb: &OsKnowledgeBase,
    protected_prefixes: &[String],
    personal_prefixes: &[String],
) -> UnclassifiedCoverageCache {
    let funnel_map = build_coverage_funnel_context(index, kb, protected_prefixes);
    let classified = index.classified_paths();
    let scan = scan_unclassified_for_coverage(
        index,
        kb,
        protected_prefixes,
        personal_prefixes,
        &funnel_map,
    );
    let total_unclassified = UnclassifiedCoverageCache::total_unclassified_from_stats(
        &scan.funnel_stats,
    );
    UnclassifiedCoverageCache {
        funnel_map,
        classified,
        funnel_stats: scan.funnel_stats,
        subtree_index: scan.subtree_index,
        tail_file_paths: scan.tail_file_paths,
        total_unclassified,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai_coverage_tree::build_ai_tree_plan_from_coverage_cache;
    use crate::index::SnapshotIndexBuilder;
    use crate::model::ScanStats;

    fn kb_empty() -> OsKnowledgeBase {
        OsKnowledgeBase::from_yaml("version: 1\nmacos: []\nwindows: []\nlinux: []", "macos")
            .unwrap()
    }

    #[test]
    fn sidecar_meta_round_trips() {
        let dir = std::env::temp_dir().join("volward-sidecar-test");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("snap.coverage_cache.json");
        let meta = CoverageCacheSidecarMeta {
            version: UNCLASSIFIED_COVERAGE_CACHE_VERSION,
            snapshot_id: "snap".to_string(),
            index_version: 3,
            funnel_stats: CoverageFunnelStats {
                local_safe_files: 1,
                local_keep_files: 2,
                tail_files: 3,
                tree_pending_files: 4,
            },
            total_unclassified: 10,
        };
        save_coverage_cache_sidecar(&path, &meta).unwrap();
        assert_eq!(load_coverage_cache_sidecar(&path).unwrap(), meta);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn cache_matches_direct_tree_plan_stats() {
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.ensure_dir("/root/bucket");
        builder.record_file_size("/root/bucket/large.dat", 900);
        let index = builder.finish(
            "snap-cache".to_string(),
            1,
            1,
            "Done".to_string(),
            ScanStats::default(),
        );
        let kb = kb_empty();
        let cache = build_unclassified_coverage_cache(&index, &kb, &[], &[]);
        let plan =
            build_ai_tree_plan_from_coverage_cache(&index, &kb, &[], &[], &cache);
        assert_eq!(plan.funnel_stats.tail_files, cache.funnel_stats.tail_files);
        assert_eq!(cache.total_unclassified, 1);
    }
}
