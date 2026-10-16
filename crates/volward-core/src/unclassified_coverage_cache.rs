//! Single build of funnel map + unclassified scan artifacts for AI precheck / tree plan.

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use serde::{Deserialize, Serialize};

use crate::ai_coverage_tree::{scan_unclassified_for_coverage, UnclassifiedSubtreeIndex};
use crate::coverage_funnel::{
    build_coverage_funnel_context, CoverageFunnelContextMap, CoverageFunnelStats,
};
use crate::index::SnapshotIndex;
use crate::os_knowledge::OsKnowledgeBase;

pub const UNCLASSIFIED_COVERAGE_CACHE_VERSION: u32 = 2;

/// How much of [`UnclassifiedCoverageCache`] callers need.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UnclassifiedCoverageCacheDepth {
    /// Top-N largest unclassified files + counts (AI precheck / candidates).
    FunnelSample,
    /// Full funnel stats + per-directory subtree index (tree coverage plan).
    Full,
}

/// Large maps are `Arc`-shared so engine-level caches can hold them without deep copies.
/// `funnel_map` / `classified` are empty unless `subtree_index_ready` (full build).
#[derive(Debug, Clone)]
pub struct UnclassifiedCoverageCache {
    pub funnel_map: Arc<CoverageFunnelContextMap>,
    pub classified: Arc<HashSet<String>>,
    pub funnel_stats: CoverageFunnelStats,
    pub subtree_index: Arc<UnclassifiedSubtreeIndex>,
    pub tail_file_paths: Vec<(String, u64)>,
    pub funnel_largest_files: Vec<(String, u64)>,
    pub total_unclassified_file_count: usize,
    pub total_unclassified: usize,
    /// False when built via [`build_unclassified_coverage_cache_funnel_sample`] only.
    pub subtree_index_ready: bool,
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
    /// [`SnapshotIndex::content_fingerprint`] at build time; empty in legacy metas.
    #[serde(default)]
    pub index_fingerprint: String,
}

impl CoverageCacheSidecarMeta {
    pub fn from_cache(
        snapshot_id: &str,
        index_version: u64,
        index_fingerprint: &str,
        cache: &UnclassifiedCoverageCache,
    ) -> Self {
        Self {
            version: UNCLASSIFIED_COVERAGE_CACHE_VERSION,
            snapshot_id: snapshot_id.to_string(),
            index_version,
            funnel_stats: cache.funnel_stats,
            total_unclassified: cache.total_unclassified,
            index_fingerprint: index_fingerprint.to_string(),
        }
    }
}

pub fn coverage_cache_sidecar_path(snapshot_id: &str) -> PathBuf {
    crate::unclassified_coverage_cache_persist::coverage_cache_meta_path(snapshot_id)
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

/// Removes sidecar metadata when snapshot or index generation no longer matches.
pub fn invalidate_stale_coverage_cache_sidecar(
    snapshot_id: &str,
    index_version: u64,
) {
    use crate::unclassified_coverage_cache_persist::coverage_cache_bin_path;

    let meta_path = coverage_cache_sidecar_path(snapshot_id);
    let bin_path = coverage_cache_bin_path(snapshot_id);
    let Some(meta) = load_coverage_cache_sidecar(&meta_path) else {
        return;
    };
    if meta.snapshot_id != snapshot_id || meta.index_version != index_version {
        let _ = std::fs::remove_file(meta_path);
        let _ = std::fs::remove_file(bin_path);
    }
}

pub fn coverage_cache_to_persisted(
    cache: &UnclassifiedCoverageCache,
    snapshot_id: &str,
    index_version: u64,
) -> crate::unclassified_coverage_cache_persist::CoverageCachePersistedV1 {
    use crate::unclassified_coverage_cache_persist::PersistedDirUnclassifiedAgg;
    use std::collections::HashMap;

    let subtree_by_dir = cache
        .subtree_index
        .by_dir
        .iter()
        .map(|(dir, agg)| {
            (
                dir.clone(),
                PersistedDirUnclassifiedAgg {
                    unclassified_files: agg.unclassified_files,
                    local_files: agg.local_files,
                    ai_pending_files: agg.ai_pending_files,
                    ext_counts: agg.ext_counts.clone(),
                },
            )
        })
        .collect::<HashMap<_, _>>();
    crate::unclassified_coverage_cache_persist::CoverageCachePersistedV1 {
        snapshot_id: snapshot_id.to_string(),
        index_version,
        funnel_map: cache.funnel_map.as_ref().clone(),
        classified: cache.classified.iter().cloned().collect(),
        funnel_stats: cache.funnel_stats,
        subtree_by_dir,
        tail_file_paths: cache.tail_file_paths.clone(),
        funnel_largest_files: cache.funnel_largest_files.clone(),
        total_unclassified_file_count: cache.total_unclassified_file_count,
    }
}

pub fn coverage_cache_from_persisted(
    wire: crate::unclassified_coverage_cache_persist::CoverageCachePersistedV1,
) -> UnclassifiedCoverageCache {
    use crate::ai_coverage_tree::DirUnclassifiedAgg;
    use std::collections::HashSet;

    let mut by_dir = std::collections::HashMap::new();
    for (dir, agg) in wire.subtree_by_dir {
        by_dir.insert(
            dir,
            DirUnclassifiedAgg {
                unclassified_files: agg.unclassified_files,
                local_files: agg.local_files,
                ai_pending_files: agg.ai_pending_files,
                ext_counts: agg.ext_counts,
            },
        );
    }
    let total_unclassified =
        UnclassifiedCoverageCache::total_unclassified_from_stats(&wire.funnel_stats);
    UnclassifiedCoverageCache {
        funnel_map: Arc::new(wire.funnel_map),
        classified: Arc::new(wire.classified.into_iter().collect::<HashSet<_>>()),
        funnel_stats: wire.funnel_stats,
        subtree_index: Arc::new(crate::ai_coverage_tree::UnclassifiedSubtreeIndex { by_dir }),
        tail_file_paths: wire.tail_file_paths,
        funnel_largest_files: wire.funnel_largest_files,
        total_unclassified_file_count: wire.total_unclassified_file_count,
        total_unclassified,
        subtree_index_ready: true,
    }
}

pub fn cache_meets_depth(
    cache: &UnclassifiedCoverageCache,
    depth: UnclassifiedCoverageCacheDepth,
) -> bool {
    match depth {
        UnclassifiedCoverageCacheDepth::FunnelSample => true,
        UnclassifiedCoverageCacheDepth::Full => cache.subtree_index_ready,
    }
}

/// Loads a persisted full cache only when its meta matches `index_fingerprint`
/// (a bin without meta is never trusted).
pub fn try_load_coverage_cache_from_disk(
    snapshot_id: &str,
    index_version: u64,
    index_fingerprint: &str,
) -> Option<UnclassifiedCoverageCache> {
    use crate::unclassified_coverage_cache_persist::{
        coverage_cache_bin_path, load_coverage_cache_bin,
    };

    let meta_path = coverage_cache_sidecar_path(snapshot_id);
    let bin_path = coverage_cache_bin_path(snapshot_id);
    let meta = load_coverage_cache_sidecar(&meta_path)?;
    if meta.snapshot_id != snapshot_id
        || meta.index_version != index_version
        || meta.index_fingerprint != index_fingerprint
    {
        let _ = std::fs::remove_file(meta_path);
        let _ = std::fs::remove_file(bin_path);
        return None;
    }
    let wire = load_coverage_cache_bin(&bin_path)?;
    if wire.snapshot_id != snapshot_id || wire.index_version != index_version {
        let _ = std::fs::remove_file(bin_path);
        let _ = std::fs::remove_file(meta_path);
        return None;
    }
    if meta.funnel_stats != wire.funnel_stats
        || meta.total_unclassified
            != UnclassifiedCoverageCache::total_unclassified_from_stats(&wire.funnel_stats)
    {
        let _ = std::fs::remove_file(bin_path);
        let _ = std::fs::remove_file(meta_path);
        return None;
    }
    Some(coverage_cache_from_persisted(wire))
}

#[cfg(debug_assertions)]
static DEBUG_BUILD_UNCLASSIFIED_CACHE_CALLS: std::sync::atomic::AtomicUsize =
    std::sync::atomic::AtomicUsize::new(0);

/// Test/diagnostic hook (debug builds only): full in-memory cache builds.
#[cfg(debug_assertions)]
pub fn debug_unclassified_cache_build_count() -> usize {
    DEBUG_BUILD_UNCLASSIFIED_CACHE_CALLS.load(std::sync::atomic::Ordering::SeqCst)
}

#[cfg(debug_assertions)]
pub fn debug_reset_unclassified_cache_build_count() {
    DEBUG_BUILD_UNCLASSIFIED_CACHE_CALLS.store(0, std::sync::atomic::Ordering::SeqCst);
}

/// Funnel sample only: one index pass + size heap. Skips project ancestry, classified
/// set, per-file funnel resolution and subtree aggregation (all full-build only).
pub fn build_unclassified_coverage_cache_funnel_sample(
    index: &SnapshotIndex,
) -> UnclassifiedCoverageCache {
    use crate::ai_candidates::FUNNEL_UNCLASSIFIED_FILE_BUDGET;

    let (total_unclassified_file_count, funnel_largest_files) =
        index.scan_unclassified_files(FUNNEL_UNCLASSIFIED_FILE_BUDGET, |_, _| {});
    UnclassifiedCoverageCache {
        funnel_map: Arc::default(),
        classified: Arc::default(),
        funnel_stats: CoverageFunnelStats::default(),
        subtree_index: Arc::default(),
        tail_file_paths: Vec::new(),
        funnel_largest_files,
        total_unclassified_file_count,
        total_unclassified: total_unclassified_file_count,
        subtree_index_ready: false,
    }
}

pub fn build_unclassified_coverage_cache(
    index: &SnapshotIndex,
    kb: &OsKnowledgeBase,
    protected_prefixes: &[String],
    personal_prefixes: &[String],
) -> UnclassifiedCoverageCache {
    #[cfg(debug_assertions)]
    DEBUG_BUILD_UNCLASSIFIED_CACHE_CALLS.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
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
        funnel_map: Arc::new(funnel_map),
        classified: Arc::new(classified),
        funnel_stats: scan.funnel_stats,
        subtree_index: Arc::new(scan.subtree_index),
        tail_file_paths: scan.tail_file_paths,
        funnel_largest_files: scan.funnel_largest_files,
        total_unclassified_file_count: scan.total_unclassified_file_count,
        total_unclassified,
        subtree_index_ready: true,
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
    fn invalidate_stale_sidecar_removes_mismatched_meta() {
        let dir = std::env::temp_dir().join("volward-sidecar-stale");
        let _ = std::fs::remove_dir_all(&dir);
        std::env::set_var("VOLWARD_CACHE_DIR", dir.to_string_lossy().as_ref());
        let path = coverage_cache_sidecar_path("snap-a");
        let meta = CoverageCacheSidecarMeta {
            version: UNCLASSIFIED_COVERAGE_CACHE_VERSION,
            snapshot_id: "snap-a".to_string(),
            index_version: 1,
            funnel_stats: CoverageFunnelStats::default(),
            total_unclassified: 0,
            index_fingerprint: String::new(),
        };
        save_coverage_cache_sidecar(&path, &meta).unwrap();
        invalidate_stale_coverage_cache_sidecar("snap-a", 2);
        assert!(load_coverage_cache_sidecar(&path).is_none());
        let _ = std::fs::remove_dir_all(&dir);
        std::env::remove_var("VOLWARD_CACHE_DIR");
    }

    #[test]
    fn try_load_coverage_cache_roundtrips_via_disk() {
        let dir = std::env::temp_dir().join("volward-sidecar-load");
        let _ = std::fs::remove_dir_all(&dir);
        std::env::set_var("VOLWARD_CACHE_DIR", dir.to_string_lossy().as_ref());
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.record_file_size("/root/f.dat", 50);
        let index = builder.finish(
            "snap-load".into(),
            1,
            4,
            "Done".into(),
            ScanStats::default(),
        );
        let kb = kb_empty();
        let cache = build_unclassified_coverage_cache(&index, &kb, &[], &[]);
        let wire = coverage_cache_to_persisted(&cache, "snap-load", 4);
        let fingerprint = index.content_fingerprint();
        let meta = CoverageCacheSidecarMeta::from_cache("snap-load", 4, &fingerprint, &cache);
        let bin_path =
            crate::unclassified_coverage_cache_persist::coverage_cache_bin_path("snap-load");
        crate::unclassified_coverage_cache_persist::save_coverage_cache_bin(&bin_path, &wire)
            .unwrap();
        save_coverage_cache_sidecar(&coverage_cache_sidecar_path("snap-load"), &meta).unwrap();
        assert!(
            try_load_coverage_cache_from_disk("snap-load", 4, "other-index").is_none(),
            "fingerprint mismatch must not load"
        );
        assert!(!bin_path.exists(), "mismatched cache files are removed");

        crate::unclassified_coverage_cache_persist::save_coverage_cache_bin(&bin_path, &wire)
            .unwrap();
        save_coverage_cache_sidecar(&coverage_cache_sidecar_path("snap-load"), &meta).unwrap();
        let loaded =
            try_load_coverage_cache_from_disk("snap-load", 4, &fingerprint).expect("load");
        assert_eq!(loaded.funnel_stats, cache.funnel_stats);
        assert_eq!(loaded.funnel_largest_files, cache.funnel_largest_files);
        let _ = std::fs::remove_dir_all(&dir);
        std::env::remove_var("VOLWARD_CACHE_DIR");
    }

    #[test]
    fn full_cache_build_scales_linearly_with_many_cache_entries() {
        use crate::model::{EntryCategory, RiskLevel, SourceType, StorageEntry};

        let mut builder = SnapshotIndexBuilder::new("/root");
        for i in 0..2_000 {
            let path = format!("/root/caches/c{i}/blob.bin");
            builder.insert_entry(StorageEntry {
                id: format!("id:{path}"),
                display_name: "blob.bin".to_string(),
                path_or_uri: path,
                size_bytes: 10,
                category: EntryCategory::Cache,
                risk_level: RiskLevel::Low,
                source_type: SourceType::File,
                deletable: true,
                reason: "test".to_string(),
                modified_at_ms: None,
            });
        }
        for d in 0..200 {
            for f in 0..250 {
                builder.record_file_size(&format!("/root/media/d{d}/s{}/f{f}.mov", f % 5), 1_000);
            }
        }
        let index = builder.finish("snap-scale".into(), 1, 1, "Done".into(), ScanStats::default());
        let kb = kb_empty();

        let started = std::time::Instant::now();
        let cache = build_unclassified_coverage_cache(&index, &kb, &[], &[]);
        let elapsed = started.elapsed();

        assert_eq!(cache.total_unclassified_file_count, 50_000);
        assert!(cache.subtree_index_ready);
        assert!(
            elapsed < std::time::Duration::from_secs(20),
            "full coverage cache build took {elapsed:?}"
        );
    }

    #[test]
    fn funnel_sample_skips_subtree_but_keeps_largest_files() {
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.record_file_size("/root/small.dat", 1);
        builder.record_file_size("/root/large.dat", 999);
        let index = builder.finish("snap".into(), 1, 1, "Done".into(), ScanStats::default());
        let cache = build_unclassified_coverage_cache_funnel_sample(&index);
        assert!(!cache.subtree_index_ready);
        assert!(cache.funnel_map.is_empty(), "sample must not build project ancestry");
        assert!(cache.subtree_index.by_dir.is_empty());
        assert_eq!(cache.total_unclassified_file_count, 2);
        assert_eq!(cache.funnel_largest_files[0].0, "/root/large.dat");
        assert!(cache_meets_depth(&cache, UnclassifiedCoverageCacheDepth::FunnelSample));
        assert!(!cache_meets_depth(&cache, UnclassifiedCoverageCacheDepth::Full));
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
            index_fingerprint: "/root|0|1|2|3".to_string(),
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
        assert_eq!(cache.funnel_largest_files.len(), 1);
        assert_eq!(cache.funnel_largest_files[0].0, "/root/bucket/large.dat");
    }
}
