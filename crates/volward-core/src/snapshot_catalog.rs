use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use crate::model::{CapabilityLevel, ScanStats, StorageSnapshot};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SnapshotCatalog {
    pub snapshot_id: String,
    pub scanned_at_ms: i64,
    pub capability: CapabilityLevel,
    pub reclaimable_estimate_bytes: u64,
    pub stats: ScanStats,
    pub entry_count: u64,
    pub deletable_count: u64,
    pub category_counts: BTreeMap<String, u64>,
    pub deletable_category_counts: BTreeMap<String, u64>,
}

impl From<&StorageSnapshot> for SnapshotCatalog {
    fn from(snapshot: &StorageSnapshot) -> Self {
        let mut category_counts = BTreeMap::new();
        let mut deletable_category_counts = BTreeMap::new();
        for entry in &snapshot.entries {
            *category_counts
                .entry(format!("{:?}", entry.category))
                .or_insert(0) += 1;
            if entry.deletable {
                *deletable_category_counts
                    .entry(format!("{:?}", entry.category))
                    .or_insert(0) += 1;
            }
        }

        Self {
            snapshot_id: snapshot.snapshot_id.clone(),
            scanned_at_ms: snapshot.scanned_at_ms,
            capability: snapshot.capability,
            reclaimable_estimate_bytes: snapshot.reclaimable_estimate_bytes,
            stats: snapshot.stats.clone(),
            entry_count: snapshot.entries.len() as u64,
            deletable_count: snapshot
                .entries
                .iter()
                .filter(|entry| entry.deletable)
                .count() as u64,
            category_counts,
            deletable_category_counts,
        }
    }
}
