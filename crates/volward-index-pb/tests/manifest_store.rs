use volward_core::index::SnapshotIndex;
use volward_core::manifest::FileSnapshotStore;
use volward_core::model::{
    CapabilityLevel, EntryCategory, RiskLevel, ScanStats, ScanTreeNode, SourceType,
    StorageEntry, StorageSnapshot,
};
use volward_index_pb::ensure_registered;

fn sample_index(root: &str) -> SnapshotIndex {
    let snapshot = StorageSnapshot {
        snapshot_id: "index-snap-001".to_string(),
        scanned_at_ms: 1_700_000_123_456,
        capability: CapabilityLevel::FullPath,
        volume_total_bytes: 1_000,
        volume_used_bytes: 600,
        reclaimable_estimate_bytes: 100,
        entries: vec![StorageEntry {
            id: "e1".to_string(),
            display_name: "file".to_string(),
            path_or_uri: format!("{root}/file.txt"),
            size_bytes: 42,
            category: EntryCategory::Cache,
            risk_level: RiskLevel::Low,
            source_type: SourceType::File,
            deletable: true,
            reason: "test".to_string(),
            modified_at_ms: None,
        }],
        tree: ScanTreeNode {
            name: "IndexPb".to_string(),
            path: root.to_string(),
            is_dir: true,
            size_bytes: 42,
            entry_id: None,
            children: vec![],
        },
        stats: ScanStats::default(),
        warnings: vec![],
    };
    SnapshotIndex::from(&snapshot)
}

#[test]
fn file_snapshot_store_pb_roundtrip() {
    ensure_registered();
    let tmp = tempfile::TempDir::new().expect("temp dir");
    let store = FileSnapshotStore::new(tmp.path());
    let root = "/Users/test/IndexPb";
    let index = sample_index(root);

    let saved_path = store
        .save_index(root, &index)
        .expect("index save should succeed");
    assert_eq!(saved_path, store.index_path_for_root(root));
    assert_eq!(
        saved_path.extension().and_then(|e| e.to_str()),
        Some("pb")
    );
    assert!(!store.path_for_root(root).exists());

    let loaded = store.load_index(root).expect("index load should succeed");
    assert_eq!(
        loaded.summary_json().unwrap(),
        index.summary_json().unwrap()
    );
}

#[test]
fn save_index_removes_legacy_json_sibling() {
    ensure_registered();
    let tmp = tempfile::TempDir::new().expect("temp dir");
    let store = FileSnapshotStore::new(tmp.path());
    let root = "/Users/test/JsonCleanup";
    let index = sample_index(root);

    let json_path = store.path_for_root(root);
    std::fs::create_dir_all(json_path.parent().unwrap()).expect("create parent");
    std::fs::write(&json_path, b"legacy").expect("seed legacy json");

    store.save_index(root, &index).expect("save pb");
    assert!(!json_path.exists());
}
