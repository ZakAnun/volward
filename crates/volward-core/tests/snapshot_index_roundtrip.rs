use volward_core::{
    CapabilityLevel, EntryCategory, RiskLevel, ScanStats, ScanTreeNode, SnapshotIndex, SourceType,
    StorageEntry, StorageSnapshot,
};

fn sample_snapshot() -> StorageSnapshot {
    StorageSnapshot {
        snapshot_id: "snap-compact".to_string(),
        scanned_at_ms: 123,
        capability: CapabilityLevel::FullPath,
        volume_total_bytes: 1_000,
        volume_used_bytes: 400,
        reclaimable_estimate_bytes: 40,
        entries: vec![StorageEntry {
            id: "entry-1".to_string(),
            display_name: "a.txt".to_string(),
            path_or_uri: "/root/Documents/a.txt".to_string(),
            size_bytes: 40,
            category: EntryCategory::Cache,
            risk_level: RiskLevel::Low,
            source_type: SourceType::File,
            deletable: true,
            reason: "cache".to_string(),
            modified_at_ms: None,
        }],
        tree: ScanTreeNode {
            name: "root".to_string(),
            path: "/root".to_string(),
            is_dir: true,
            size_bytes: 40,
            entry_id: None,
            children: vec![
                ScanTreeNode {
                    name: "Documents".to_string(),
                    path: "/root/Documents".to_string(),
                    is_dir: true,
                    size_bytes: 40,
                    entry_id: None,
                    children: vec![ScanTreeNode {
                        name: "a.txt".to_string(),
                        path: "/root/Documents/a.txt".to_string(),
                        is_dir: false,
                        size_bytes: 40,
                        entry_id: Some("entry-1".to_string()),
                        children: vec![],
                    }],
                },
                ScanTreeNode {
                    name: "Downloads".to_string(),
                    path: "/root/Downloads".to_string(),
                    is_dir: true,
                    size_bytes: 0,
                    entry_id: None,
                    children: vec![],
                },
            ],
        },
        stats: ScanStats {
            paths_seen: 4,
            dirs_seen: 3,
            files_seen: 1,
            files_in_snapshot: 1,
            paths_skipped: 0,
            truncated: false,
            incomplete_reason: None,
        },
        warnings: vec![],
    }
}

#[test]
fn compact_index_roundtrips_and_accepts_older_format_versions() {
    let snapshot = sample_snapshot();
    let index = SnapshotIndex::from(&snapshot);

    let json = serde_json::to_string(&index).expect("serialize index");
    assert!(
        json.contains("\"format_version\":5"),
        "writers should emit format_version=5"
    );
    assert!(json.contains("\"file_size_by_path\""));
    let loaded: SnapshotIndex = serde_json::from_str(&json).expect("deserialize index");
    assert_eq!(
        loaded.summary_json().unwrap(),
        index.summary_json().unwrap()
    );
    assert_eq!(
        loaded
            .query_directory("/root", None, false, "name")
            .direct_children
            .len(),
        2
    );

    // Older caches with versions 2–4 must still load.
    let v2_json = json.replace("\"format_version\":5", "\"format_version\":2");
    let loaded_v2: SnapshotIndex =
        serde_json::from_str(&v2_json).expect("deserialize format_version=2 index");
    assert_eq!(
        loaded_v2.summary_json().unwrap(),
        index.summary_json().unwrap()
    );

    let v3_json = json.replace("\"format_version\":5", "\"format_version\":3");
    let loaded_v3: SnapshotIndex =
        serde_json::from_str(&v3_json).expect("deserialize format_version=3 index");
    assert_eq!(
        loaded_v3.summary_json().unwrap(),
        index.summary_json().unwrap()
    );
    assert_eq!(
        loaded_v3
            .query_directory("/root", None, false, "name")
            .direct_children
            .len(),
        2
    );

    let v4_json = json.replace("\"format_version\":5", "\"format_version\":4");
    let loaded_v4: SnapshotIndex =
        serde_json::from_str(&v4_json).expect("deserialize format_version=4 index");
    assert_eq!(
        loaded_v4.summary_json().unwrap(),
        index.summary_json().unwrap()
    );
}
