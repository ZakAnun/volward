//! Encodes `volward-core` model types into generated protobuf messages.
//!
//! Enum fields are written as their raw proto field numbers (`i32`) rather than
//! the generated Rust enum variants, so this layer stays correct regardless of
//! how prost happens to name those variants — the wire numbers are fixed by
//! `proto/volward.proto` and mirrored here.
//!
//! `StorageSnapshot` encode-only was the initial scope; `SnapshotIndex`
//! encode/decode round-trips through the wire DTO exported by `volward-core`.

use volward_core::model;
use volward_core::{
    DirectoryRecord, EntryRecord, SnapshotIndex, SnapshotIndexWire,
};

use crate::proto;

const SNAPSHOT_INDEX_FORMAT_VERSION: u32 = 5;

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

// --- SnapshotIndex wire conversions ---

fn directory_record_to_proto(rec: &DirectoryRecord) -> proto::IndexDirectoryRecord {
    proto::IndexDirectoryRecord {
        parent: rec.parent,
        name: rec.name,
        size_bytes: rec.size_bytes,
        scanned: rec.scanned,
        peek_scanned: rec.peek_scanned,
        category_mask: rec.category_mask,
        deletable_category_mask: rec.deletable_category_mask,
        deletable_file_count: rec.deletable_file_count,
    }
}

fn directory_record_from_proto(rec: proto::IndexDirectoryRecord) -> DirectoryRecord {
    DirectoryRecord {
        parent: rec.parent,
        name: rec.name,
        size_bytes: rec.size_bytes,
        scanned: rec.scanned,
        peek_scanned: rec.peek_scanned,
        category_mask: rec.category_mask,
        deletable_category_mask: rec.deletable_category_mask,
        deletable_file_count: rec.deletable_file_count,
    }
}

fn entry_record_to_proto(rec: &EntryRecord) -> proto::IndexEntryRecord {
    proto::IndexEntryRecord {
        id: rec.id,
        path: rec.path,
        parent_path: rec.parent_path,
        display_name: rec.display_name,
        size_bytes: rec.size_bytes,
        category: rec.category,
        deletable: rec.deletable,
        modified_at_ms: rec.modified_at_ms,
    }
}

fn entry_record_from_proto(rec: proto::IndexEntryRecord) -> EntryRecord {
    EntryRecord {
        id: rec.id,
        path: rec.path,
        parent_path: rec.parent_path,
        display_name: rec.display_name,
        size_bytes: rec.size_bytes,
        category: rec.category,
        deletable: rec.deletable,
        modified_at_ms: rec.modified_at_ms,
    }
}

fn wire_to_proto(wire: &SnapshotIndexWire) -> proto::SnapshotIndex {
    proto::SnapshotIndex {
        format_version: wire.format_version,
        snapshot_id: wire.snapshot_id.clone(),
        root_path: wire.root_path.clone(),
        scanned_at_ms: wire.scanned_at_ms,
        version: wire.version,
        scan_state: wire.scan_state.clone(),
        reclaimable_estimate_bytes: wire.reclaimable_estimate_bytes,
        stats: Some(proto::ScanStats::from(&wire.stats)),
        strings: wire.strings.iter().map(|s| s.to_string()).collect(),
        root_id: wire.root_id,
        directories: wire
            .directories
            .iter()
            .map(|(id, record)| proto::IndexDirectoryMapEntry {
                id: *id,
                record: Some(directory_record_to_proto(record)),
            })
            .collect(),
        entries: wire
            .entries
            .iter()
            .map(|(id, record)| proto::IndexEntryMapEntry {
                id: *id,
                record: Some(entry_record_to_proto(record)),
            })
            .collect(),
        entry_id_by_path: wire
            .entry_id_by_path
            .iter()
            .map(|(key, value)| proto::IndexU32Pair {
                key: *key,
                value: *value,
            })
            .collect(),
        file_size_by_path: wire
            .file_size_by_path
            .iter()
            .map(|(key, value)| proto::IndexU32u64Pair {
                key: *key,
                value: *value,
            })
            .collect(),
        children: wire
            .children
            .iter()
            .map(|(key, child_ids)| proto::IndexChildrenEntry {
                key: *key,
                child_ids: child_ids.clone(),
            })
            .collect(),
        category_counts: wire
            .category_counts
            .iter()
            .map(|(key, value)| proto::IndexStringCountEntry {
                key: key.clone(),
                value: *value,
            })
            .collect(),
        deletable_counts: wire
            .deletable_counts
            .iter()
            .map(|(key, value)| proto::IndexStringCountEntry {
                key: key.clone(),
                value: *value,
            })
            .collect(),
    }
}

fn wire_from_proto(msg: proto::SnapshotIndex) -> Result<SnapshotIndexWire, String> {
    if msg.format_version != SNAPSHOT_INDEX_FORMAT_VERSION {
        return Err(format!(
            "unsupported SnapshotIndex format_version {} (expected {})",
            msg.format_version, SNAPSHOT_INDEX_FORMAT_VERSION
        ));
    }
    if msg.root_id as usize >= msg.strings.len() {
        return Err(format!(
            "invalid SnapshotIndex root_id {} for {} strings",
            msg.root_id,
            msg.strings.len()
        ));
    }

    Ok(SnapshotIndexWire {
        format_version: msg.format_version,
        snapshot_id: msg.snapshot_id,
        root_path: msg.root_path,
        scanned_at_ms: msg.scanned_at_ms,
        version: msg.version,
        scan_state: msg.scan_state,
        reclaimable_estimate_bytes: msg.reclaimable_estimate_bytes,
        stats: msg
            .stats
            .map(|s| model::ScanStats {
                paths_seen: s.paths_seen,
                dirs_seen: s.dirs_seen,
                files_seen: s.files_seen,
                files_in_snapshot: s.files_in_snapshot,
                paths_skipped: s.paths_skipped,
                truncated: s.truncated,
                incomplete_reason: s.incomplete_reason,
            })
            .unwrap_or_default(),
        strings: msg.strings.into_iter().map(String::into_boxed_str).collect(),
        root_id: msg.root_id,
        directories: msg
            .directories
            .into_iter()
            .map(|entry| {
                let record = entry
                    .record
                    .ok_or_else(|| format!("missing directory record for id {}", entry.id))?;
                Ok((entry.id, directory_record_from_proto(record)))
            })
            .collect::<Result<Vec<_>, String>>()?,
        entries: msg
            .entries
            .into_iter()
            .map(|entry| {
                let record = entry
                    .record
                    .ok_or_else(|| format!("missing entry record for id {}", entry.id))?;
                Ok((entry.id, entry_record_from_proto(record)))
            })
            .collect::<Result<Vec<_>, String>>()?,
        entry_id_by_path: msg
            .entry_id_by_path
            .into_iter()
            .map(|pair| (pair.key, pair.value))
            .collect(),
        file_size_by_path: msg
            .file_size_by_path
            .into_iter()
            .map(|pair| (pair.key, pair.value))
            .collect(),
        children: msg
            .children
            .into_iter()
            .map(|entry| (entry.key, entry.child_ids))
            .collect(),
        category_counts: msg
            .category_counts
            .into_iter()
            .map(|entry| (entry.key, entry.value))
            .collect(),
        deletable_counts: msg
            .deletable_counts
            .into_iter()
            .map(|entry| (entry.key, entry.value))
            .collect(),
    })
}

pub fn snapshot_index_to_proto(index: &SnapshotIndex) -> proto::SnapshotIndex {
    wire_to_proto(&index.to_wire())
}

pub fn snapshot_index_from_proto(msg: proto::SnapshotIndex) -> Result<SnapshotIndex, String> {
    Ok(SnapshotIndex::from_wire(wire_from_proto(msg)?))
}

#[cfg(test)]
mod tests {
    use super::*;
    use volward_core::model::{
        CapabilityLevel, EntryCategory, RiskLevel, ScanStats, ScanTreeNode, SourceType,
        StorageEntry, StorageSnapshot,
    };
    use volward_core::SnapshotIndex;

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

    fn minimal_snapshot() -> StorageSnapshot {
        StorageSnapshot {
            snapshot_id: "test-snap".to_string(),
            scanned_at_ms: 1,
            capability: CapabilityLevel::FullPath,
            volume_total_bytes: 100,
            volume_used_bytes: 50,
            reclaimable_estimate_bytes: 10,
            entries: vec![StorageEntry {
                id: "e1".to_string(),
                display_name: "file".to_string(),
                path_or_uri: "/tmp/file".to_string(),
                size_bytes: 10,
                category: EntryCategory::Cache,
                risk_level: RiskLevel::Low,
                source_type: SourceType::File,
                deletable: true,
                reason: "test".to_string(),
                modified_at_ms: None,
            }],
            tree: ScanTreeNode {
                name: "root".to_string(),
                path: "/".to_string(),
                is_dir: true,
                size_bytes: 10,
                entry_id: None,
                children: vec![],
            },
            stats: ScanStats::default(),
            warnings: vec![],
        }
    }

    #[test]
    fn snapshot_index_pb_roundtrip_matches_summary() {
        use prost::Message;

        let index = SnapshotIndex::from(&minimal_snapshot());
        let pb = snapshot_index_to_proto(&index);
        assert_eq!(pb.format_version, SNAPSHOT_INDEX_FORMAT_VERSION);
        let bytes = pb.encode_to_vec();
        let decoded = proto::SnapshotIndex::decode(bytes.as_slice()).unwrap();
        let restored = snapshot_index_from_proto(decoded).unwrap();
        assert_eq!(
            restored.summary_json().unwrap(),
            index.summary_json().unwrap()
        );
    }
}
