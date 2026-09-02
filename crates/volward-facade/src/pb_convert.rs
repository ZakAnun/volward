//! Encodes `volward-core` model types into generated protobuf messages.
//!
//! Enum fields are written as their raw proto field numbers (`i32`) rather than
//! the generated Rust enum variants, so this layer stays correct regardless of
//! how prost happens to name those variants — the wire numbers are fixed by
//! `proto/volward.proto` and mirrored here.
//!
//! Only encode (model -> proto) is implemented for now. Decode (proto -> model,
//! needed for `set_last_snapshot` / delete round-trips) lands in a later phase.

use volward_core::model;

use crate::proto;

// --- enum -> proto field number (keep in sync with proto/volward.proto) ---

fn capability_pb(c: model::CapabilityLevel) -> i32 {
    match c {
        model::CapabilityLevel::FullPath => 1,
        model::CapabilityLevel::AppStatsOnly => 2,
        model::CapabilityLevel::GuidedOnly => 3,
    }
}

fn category_pb(c: model::EntryCategory) -> i32 {
    match c {
        model::EntryCategory::Cache => 1,
        model::EntryCategory::Temp => 2,
        model::EntryCategory::Media => 3,
        model::EntryCategory::AppData => 4,
        model::EntryCategory::Orphan => 5,
        model::EntryCategory::Duplicate => 6,
        model::EntryCategory::System => 7,
        model::EntryCategory::Unknown => 8,
        model::EntryCategory::BuildArtifact => 9,
    }
}

fn risk_pb(r: model::RiskLevel) -> i32 {
    match r {
        model::RiskLevel::Low => 1,
        model::RiskLevel::Medium => 2,
        model::RiskLevel::High => 3,
    }
}

fn source_pb(s: model::SourceType) -> i32 {
    match s {
        model::SourceType::Directory => 1,
        model::SourceType::File => 2,
        model::SourceType::Volume => 3,
        model::SourceType::Application => 4,
    }
}

// --- message conversions ---

impl From<&model::StorageEntry> for proto::StorageEntry {
    fn from(e: &model::StorageEntry) -> Self {
        proto::StorageEntry {
            id: e.id.clone(),
            display_name: e.display_name.clone(),
            path_or_uri: e.path_or_uri.clone(),
            size_bytes: e.size_bytes,
            category: category_pb(e.category),
            risk_level: risk_pb(e.risk_level),
            source_type: source_pb(e.source_type),
            deletable: e.deletable,
            reason: e.reason.clone(),
            modified_at_ms: e.modified_at_ms,
        }
    }
}

impl From<&model::ScanTreeNode> for proto::ScanTreeNode {
    fn from(n: &model::ScanTreeNode) -> Self {
        proto::ScanTreeNode {
            name: n.name.clone(),
            path: n.path.clone(),
            is_dir: n.is_dir,
            size_bytes: n.size_bytes,
            entry_id: n.entry_id.clone(),
            children: n.children.iter().map(proto::ScanTreeNode::from).collect(),
            // Client-only progressive-scan markers: never set by the producer;
            // the Flutter merge stamps them. Default false on the wire.
            scanned: false,
            peek_scanned: false,
        }
    }
}

impl From<&model::ScanStats> for proto::ScanStats {
    fn from(s: &model::ScanStats) -> Self {
        proto::ScanStats {
            paths_seen: s.paths_seen,
            dirs_seen: s.dirs_seen,
            files_seen: s.files_seen,
            files_in_snapshot: s.files_in_snapshot,
            paths_skipped: s.paths_skipped,
            truncated: s.truncated,
            incomplete_reason: s.incomplete_reason.clone(),
        }
    }
}

impl From<&model::StorageSnapshot> for proto::StorageSnapshot {
    fn from(s: &model::StorageSnapshot) -> Self {
        proto::StorageSnapshot {
            snapshot_id: s.snapshot_id.clone(),
            scanned_at_ms: s.scanned_at_ms,
            capability: capability_pb(s.capability),
            volume_total_bytes: s.volume_total_bytes,
            volume_used_bytes: s.volume_used_bytes,
            reclaimable_estimate_bytes: s.reclaimable_estimate_bytes,
            entries: s.entries.iter().map(proto::StorageEntry::from).collect(),
            tree: Some(proto::ScanTreeNode::from(&s.tree)),
            stats: Some(proto::ScanStats::from(&s.stats)),
            warnings: s.warnings.clone(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use volward_core::model::{
        CapabilityLevel, EntryCategory, RiskLevel, ScanStats, ScanTreeNode, SourceType,
        StorageEntry, StorageSnapshot,
    };

    fn sample() -> StorageSnapshot {
        StorageSnapshot {
            snapshot_id: "s1".into(),
            scanned_at_ms: 42,
            capability: CapabilityLevel::FullPath,
            volume_total_bytes: 100,
            volume_used_bytes: 50,
            reclaimable_estimate_bytes: 10,
            entries: vec![StorageEntry {
                id: "e1".into(),
                display_name: "file".into(),
                path_or_uri: "/tmp/file".into(),
                size_bytes: 10,
                category: EntryCategory::Cache,
                risk_level: RiskLevel::Low,
                source_type: SourceType::File,
                deletable: true,
                reason: "test".into(),
                modified_at_ms: None,
            }],
            tree: ScanTreeNode {
                name: "root".into(),
                path: "/".into(),
                is_dir: true,
                size_bytes: 10,
                entry_id: None,
                children: vec![ScanTreeNode {
                    name: "file".into(),
                    path: "/tmp/file".into(),
                    is_dir: false,
                    size_bytes: 10,
                    entry_id: Some("e1".into()),
                    children: vec![],
                }],
            },
            stats: ScanStats::default(),
            warnings: vec!["w".into()],
        }
    }

    #[test]
    fn encodes_snapshot_fields() {
        let pb = proto::StorageSnapshot::from(&sample());
        assert_eq!(pb.snapshot_id, "s1");
        assert_eq!(pb.scanned_at_ms, 42);
        assert_eq!(pb.capability, 1); // FullPath
        assert_eq!(pb.entries.len(), 1);
        assert_eq!(pb.entries[0].category, 1); // Cache
        assert_eq!(pb.entries[0].risk_level, 1); // Low
        assert_eq!(pb.entries[0].source_type, 2); // File
        let tree = pb.tree.expect("tree present");
        assert_eq!(tree.children.len(), 1);
        assert_eq!(tree.children[0].entry_id.as_deref(), Some("e1"));
        assert!(!tree.scanned && !tree.peek_scanned);
        assert!(pb.stats.is_some());
        assert_eq!(pb.warnings, vec!["w".to_string()]);
    }

    #[test]
    fn round_trips_through_protobuf_bytes() {
        use prost::Message;
        let pb = proto::StorageSnapshot::from(&sample());
        let bytes = pb.encode_to_vec();
        let decoded = proto::StorageSnapshot::decode(bytes.as_slice()).expect("decode");
        assert_eq!(decoded.snapshot_id, "s1");
        assert_eq!(decoded.tree.unwrap().children[0].path, "/tmp/file");
    }
}
