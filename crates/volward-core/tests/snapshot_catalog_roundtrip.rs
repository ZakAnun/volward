use volward_core::model::{CapabilityLevel, ScanStats};
use volward_core::SnapshotCatalog;

#[test]
fn snapshot_catalog_round_trips_as_compact_json() {
    let catalog = SnapshotCatalog {
        snapshot_id: "snap-1".to_string(),
        scanned_at_ms: 42,
        capability: CapabilityLevel::FullPath,
        reclaimable_estimate_bytes: 123,
        stats: ScanStats {
            files_in_snapshot: 2,
            ..ScanStats::default()
        },
        entry_count: 2,
        deletable_count: 1,
        category_counts: [("Cache".to_string(), 1), ("Media".to_string(), 1)]
            .into_iter()
            .collect(),
        deletable_category_counts: [("Cache".to_string(), 1)].into_iter().collect(),
    };

    let json = serde_json::to_string(&catalog).expect("catalog should serialize");
    assert!(!json.contains("entries"));
    assert!(!json.contains("tree"));
    let decoded: SnapshotCatalog = serde_json::from_str(&json).expect("catalog should decode");

    assert_eq!(decoded, catalog);
}
