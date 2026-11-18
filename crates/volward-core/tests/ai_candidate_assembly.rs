use std::collections::HashSet;
use std::sync::Arc;
use std::sync::Mutex;

use volward_core::ai_candidates::{
    build_index_candidate_assembly, build_snapshot_candidate_assembly,
};
use volward_core::coverage_funnel::{CoverageFunnelContextMap, CoverageFunnelStats};
use volward_core::model::{
    CapabilityLevel, EntryCategory, RiskLevel, ScanStats, ScanTreeNode, SourceType, StorageEntry,
    StorageSnapshot,
};
use volward_core::unclassified_coverage_cache::UnclassifiedCoverageCache;
use volward_core::{
    indexed_local_exclusion_prefixes, AiAnalysisResult, AiTokenUsage, OsKnowledgeBase,
    SnapshotIndex, SnapshotIndexBuilder, UnclassifiedSubtreeIndex, DEFAULT_PRECLASSIFIED_CAP,
};

static CACHE_ENV_LOCK: Mutex<()> = Mutex::new(());

fn lock_cache_env() -> std::sync::MutexGuard<'static, ()> {
    CACHE_ENV_LOCK
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
}

fn empty_kb() -> OsKnowledgeBase {
    OsKnowledgeBase::from_yaml("version: 1\nmacos: []\nwindows: []\nlinux: []", "macos").unwrap()
}

fn build_artifact(path: &str, size_bytes: u64) -> StorageEntry {
    StorageEntry {
        id: "build-artifact".to_string(),
        display_name: "node_modules".to_string(),
        path_or_uri: path.to_string(),
        size_bytes,
        category: EntryCategory::BuildArtifact,
        risk_level: RiskLevel::Low,
        source_type: SourceType::Directory,
        deletable: true,
        reason: "build artifact".to_string(),
        modified_at_ms: None,
    }
}

fn candidate_identity(
    assembly: &volward_core::AiCandidateAssembly,
) -> Vec<(String, u64, Option<usize>)> {
    assembly
        .set
        .candidates
        .iter()
        .map(|candidate| {
            (
                candidate.path.clone(),
                candidate.size_bytes,
                candidate.child_count,
            )
        })
        .collect()
}

#[test]
fn snapshot_assembly_preserves_aggregation_and_build_artifact_fields() {
    let _env_guard = lock_cache_env();
    let temp = tempfile::TempDir::new().unwrap();
    let root = temp.path().to_string_lossy().to_string();
    let scratch = temp.path().join("scratch");
    std::fs::create_dir_all(&scratch).unwrap();

    let children = (0..25)
        .map(|index| {
            let path = scratch.join(format!("blob_{index}.dat"));
            std::fs::write(&path, [0u8]).unwrap();
            ScanTreeNode {
                name: format!("blob_{index}.dat"),
                path: path.to_string_lossy().to_string(),
                is_dir: false,
                size_bytes: 1,
                entry_id: None,
                children: vec![],
            }
        })
        .collect::<Vec<_>>();

    let snapshot = StorageSnapshot {
        snapshot_id: "snapshot-assembly".to_string(),
        scanned_at_ms: 1,
        capability: CapabilityLevel::FullPath,
        volume_total_bytes: 100,
        volume_used_bytes: 50,
        reclaimable_estimate_bytes: 25,
        entries: vec![build_artifact("/Users/x/app/node_modules", 4096)],
        tree: ScanTreeNode {
            name: "root".to_string(),
            path: root.clone(),
            is_dir: true,
            size_bytes: 4121,
            entry_id: None,
            children: vec![ScanTreeNode {
                name: "scratch".to_string(),
                path: scratch.to_string_lossy().to_string(),
                is_dir: true,
                size_bytes: 25,
                entry_id: None,
                children,
            }],
        },
        stats: ScanStats {
            files_seen: 25,
            files_in_snapshot: 25,
            ..ScanStats::default()
        },
        warnings: vec![],
    };

    let assembly = build_snapshot_candidate_assembly(&snapshot, &empty_kb());

    assert_eq!(assembly.root_path, root);
    assert_eq!(assembly.set.candidates.len(), 1);
    assert_eq!(assembly.set.candidates[0].child_count, Some(25));
    assert_eq!(assembly.set.total_raw_count, 25);
    assert!(assembly.set.pre_classified.len() >= 1);
    assert!(assembly
        .set
        .pre_classified
        .iter()
        .any(|entry| entry.path == "/Users/x/app/node_modules"));
    assert!(assembly.cache_key.len() > 10);
    assert!(!assembly.truncated);
    assert_eq!(assembly.truncated, assembly.set.truncated);
}

#[test]
fn index_assembly_preserves_funnel_truncation_and_cache_key() {
    let _env_guard = lock_cache_env();
    let temp = tempfile::TempDir::new().unwrap();
    let root = temp.path().to_string_lossy().to_string();
    let file = temp.path().join("large.dat");
    std::fs::write(&file, [0u8; 16]).unwrap();
    let file_path = file.to_string_lossy().to_string();

    let mut builder = SnapshotIndexBuilder::new(&root);
    builder.record_file_size(&file_path, 16);
    builder.insert_entry(build_artifact("/Users/x/app/node_modules", 4096));
    let index = builder.finish(
        "index-assembly".to_string(),
        1,
        1,
        "Done".to_string(),
        ScanStats {
            files_seen: 2,
            files_in_snapshot: 2,
            ..ScanStats::default()
        },
    );
    let cache = UnclassifiedCoverageCache {
        funnel_map: Arc::new(CoverageFunnelContextMap::default()),
        classified: Arc::new(HashSet::new()),
        funnel_stats: CoverageFunnelStats::default(),
        subtree_index: Arc::new(UnclassifiedSubtreeIndex::default()),
        tail_file_paths: vec![],
        funnel_largest_files: vec![(file_path, 16)],
        total_unclassified_file_count: 2,
        total_unclassified: 2,
        subtree_index_ready: false,
    };
    let prefixes = indexed_local_exclusion_prefixes(&index);

    let assembly = build_index_candidate_assembly(&index, &cache, &empty_kb(), &prefixes);
    let duplicate = build_index_candidate_assembly(&index, &cache, &empty_kb(), &prefixes);

    assert_eq!(assembly.root_path, root);
    assert!(assembly.cache_key.len() > 10);
    assert_eq!(assembly.cache_key, duplicate.cache_key);
    assert!(assembly.truncated);
    assert_eq!(assembly.truncated, assembly.set.truncated);
    assert_eq!(assembly.set.total_raw_count, 2);
    assert_eq!(assembly.has_existing_result, duplicate.has_existing_result);
}

#[test]
fn index_and_snapshot_assemblies_match_for_equivalent_input() {
    let _env_guard = lock_cache_env();
    let temp = tempfile::TempDir::new().unwrap();
    let root = temp.path().to_string_lossy().to_string();
    let scratch = temp.path().join("scratch");
    std::fs::create_dir_all(&scratch).unwrap();

    let file_paths = (0..2)
        .map(|index| {
            let path = scratch.join(format!("file_{index}.bin"));
            std::fs::write(&path, vec![index as u8; index + 1]).unwrap();
            path.to_string_lossy().to_string()
        })
        .collect::<Vec<_>>();
    let tree = ScanTreeNode {
        name: "root".to_string(),
        path: root.clone(),
        is_dir: true,
        size_bytes: 4099,
        entry_id: None,
        children: vec![ScanTreeNode {
            name: "scratch".to_string(),
            path: scratch.to_string_lossy().to_string(),
            is_dir: true,
            size_bytes: 3,
            entry_id: None,
            children: file_paths
                .iter()
                .enumerate()
                .map(|(index, path)| ScanTreeNode {
                    name: format!("file_{index}.bin"),
                    path: path.clone(),
                    is_dir: false,
                    size_bytes: (index + 1) as u64,
                    entry_id: None,
                    children: vec![],
                })
                .collect(),
        }],
    };
    let snapshot = StorageSnapshot {
        snapshot_id: "equivalent-assembly".to_string(),
        scanned_at_ms: 1,
        capability: CapabilityLevel::FullPath,
        volume_total_bytes: 100,
        volume_used_bytes: 50,
        reclaimable_estimate_bytes: 3,
        entries: vec![build_artifact("/Users/x/app/node_modules", 4096)],
        tree,
        stats: ScanStats {
            files_seen: 2,
            files_in_snapshot: 2,
            dirs_seen: 2,
            paths_seen: 4,
            ..ScanStats::default()
        },
        warnings: vec![],
    };
    let index = SnapshotIndex::from_snapshot(&snapshot);
    let cache = UnclassifiedCoverageCache {
        funnel_map: Arc::new(CoverageFunnelContextMap::default()),
        classified: Arc::new(HashSet::new()),
        funnel_stats: CoverageFunnelStats::default(),
        subtree_index: Arc::new(UnclassifiedSubtreeIndex::default()),
        tail_file_paths: vec![],
        funnel_largest_files: file_paths
            .iter()
            .enumerate()
            .map(|(index, path)| (path.clone(), (index + 1) as u64))
            .collect(),
        total_unclassified_file_count: 2,
        total_unclassified: 2,
        subtree_index_ready: false,
    };
    let prefixes = indexed_local_exclusion_prefixes(&index);

    let snapshot_assembly = build_snapshot_candidate_assembly(&snapshot, &empty_kb());
    let index_assembly = build_index_candidate_assembly(&index, &cache, &empty_kb(), &prefixes);

    assert_eq!(snapshot_assembly.root_path, index_assembly.root_path);
    assert_eq!(snapshot_assembly.cache_key, index_assembly.cache_key);
    assert_eq!(snapshot_assembly.truncated, index_assembly.truncated);
    assert_eq!(
        candidate_identity(&snapshot_assembly),
        candidate_identity(&index_assembly)
    );
    assert_eq!(
        snapshot_assembly
            .set
            .pre_classified
            .iter()
            .map(|entry| (entry.path.clone(), entry.size_bytes))
            .collect::<Vec<_>>(),
        index_assembly
            .set
            .pre_classified
            .iter()
            .map(|entry| (entry.path.clone(), entry.size_bytes))
            .collect::<Vec<_>>()
    );
}

#[test]
fn index_and_snapshot_keep_largest_pre_classified_entries() {
    let _env_guard = lock_cache_env();
    let temp = tempfile::TempDir::new().unwrap();
    let root = temp.path().to_string_lossy().to_string();
    let entries = (0..=DEFAULT_PRECLASSIFIED_CAP)
        .map(|index| {
            let mut entry = build_artifact(
                &format!("/Users/x/builds/artifact-{index:03}"),
                (index + 1) as u64,
            );
            entry.id = format!("build-artifact-{index:03}");
            entry
        })
        .collect::<Vec<_>>();
    let snapshot = StorageSnapshot {
        snapshot_id: "pre-classified-cap".to_string(),
        scanned_at_ms: 1,
        capability: CapabilityLevel::FullPath,
        volume_total_bytes: 100,
        volume_used_bytes: 50,
        reclaimable_estimate_bytes: 0,
        entries,
        tree: ScanTreeNode {
            name: "root".to_string(),
            path: root.clone(),
            is_dir: true,
            size_bytes: 0,
            entry_id: None,
            children: vec![],
        },
        stats: ScanStats::default(),
        warnings: vec![],
    };
    let index = SnapshotIndex::from_snapshot(&snapshot);
    let cache = UnclassifiedCoverageCache {
        funnel_map: Arc::new(CoverageFunnelContextMap::default()),
        classified: Arc::new(HashSet::new()),
        funnel_stats: CoverageFunnelStats::default(),
        subtree_index: Arc::new(UnclassifiedSubtreeIndex::default()),
        tail_file_paths: vec![],
        funnel_largest_files: vec![],
        total_unclassified_file_count: 0,
        total_unclassified: 0,
        subtree_index_ready: false,
    };
    let prefixes = indexed_local_exclusion_prefixes(&index);
    let snapshot_assembly = build_snapshot_candidate_assembly(&snapshot, &empty_kb());
    let index_assembly = build_index_candidate_assembly(&index, &cache, &empty_kb(), &prefixes);

    let expected_paths = (0..DEFAULT_PRECLASSIFIED_CAP)
        .map(|offset| {
            format!(
                "/Users/x/builds/artifact-{:03}",
                DEFAULT_PRECLASSIFIED_CAP - offset
            )
        })
        .collect::<Vec<_>>();

    for assembly in [snapshot_assembly, index_assembly] {
        assert_eq!(assembly.set.pre_classified.len(), DEFAULT_PRECLASSIFIED_CAP);
        assert!(assembly.set.pre_classified_truncated);
        assert_eq!(
            assembly
                .set
                .pre_classified
                .iter()
                .map(|entry| entry.path.as_str())
                .collect::<Vec<_>>(),
            expected_paths
                .iter()
                .map(String::as_str)
                .collect::<Vec<_>>()
        );
        assert!(assembly
            .set
            .pre_classified
            .windows(2)
            .all(|pair| pair[0].size_bytes >= pair[1].size_bytes));
    }
}

#[test]
fn existing_result_transitions_from_false_to_true() {
    let _env_guard = lock_cache_env();
    let temp = tempfile::TempDir::new().unwrap();
    let previous_cache_dir = std::env::var_os("VOLWARD_CACHE_DIR");
    std::env::set_var("VOLWARD_CACHE_DIR", temp.path());

    let root = temp.path().join("root");
    std::fs::create_dir_all(&root).unwrap();
    let snapshot = StorageSnapshot {
        snapshot_id: "existing-result".to_string(),
        scanned_at_ms: 1,
        capability: CapabilityLevel::FullPath,
        volume_total_bytes: 100,
        volume_used_bytes: 50,
        reclaimable_estimate_bytes: 0,
        entries: vec![],
        tree: ScanTreeNode {
            name: "root".to_string(),
            path: root.to_string_lossy().to_string(),
            is_dir: true,
            size_bytes: 0,
            entry_id: None,
            children: vec![],
        },
        stats: ScanStats::default(),
        warnings: vec![],
    };

    let before = build_snapshot_candidate_assembly(&snapshot, &empty_kb());
    assert!(!before.has_existing_result);
    AiAnalysisResult {
        schema_version: 1,
        snapshot_id: snapshot.snapshot_id.clone(),
        cache_key: Some(before.cache_key.clone()),
        root_path: Some(before.root_path.clone()),
        analyzed_at_ms: 1,
        mode: "test".to_string(),
        model: "test".to_string(),
        entries: vec![],
        token_usage: AiTokenUsage {
            input: 0,
            output: 0,
        },
        cost_estimate_usd: 0.0,
        credits_used: 0,
    }
    .save(&before.cache_key)
    .unwrap();
    let after = build_snapshot_candidate_assembly(&snapshot, &empty_kb());
    assert!(after.has_existing_result);

    if let Some(previous) = previous_cache_dir {
        std::env::set_var("VOLWARD_CACHE_DIR", previous);
    } else {
        std::env::remove_var("VOLWARD_CACHE_DIR");
    }
}
