//! SnapshotIndex protobuf encode/decode and atomic disk persistence.

#![allow(clippy::all)]

mod proto {
    include!(concat!(env!("OUT_DIR"), "/volward.rs"));
}

use std::fs::File;
use std::io::{BufWriter, Write};

use prost::Message;
use volward_core::model;
use volward_core::{
    DirectoryRecord, EntryRecord, SnapshotIndex, SnapshotIndexWire,
};

pub use proto::SnapshotIndex as ProtoSnapshotIndex;

const SNAPSHOT_INDEX_FORMAT_VERSION: u32 = 5;

fn scan_stats_to_proto(s: &model::ScanStats) -> proto::ScanStats {
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
        stats: Some(scan_stats_to_proto(&wire.stats)),
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

pub fn encode_snapshot_index(index: &SnapshotIndex) -> Result<Vec<u8>, String> {
    Ok(snapshot_index_to_proto(index).encode_to_vec())
}

pub fn decode_snapshot_index(bytes: &[u8]) -> Result<SnapshotIndex, String> {
    let msg = proto::SnapshotIndex::decode(bytes)
        .map_err(|e| format!("error:decode pb index: {e}"))?;
    snapshot_index_from_proto(msg)
}

/// Atomically write a SnapshotIndex protobuf file (temp + rename).
pub fn write_snapshot_index_pb_atomic(index: &SnapshotIndex, path: &str) -> Result<(), String> {
    let bytes = encode_snapshot_index(index)?;
    let tmp = format!("{path}.tmp.{}", index.snapshot_id);
    {
        let file = File::create(&tmp).map_err(|e| format!("error:create pb tmp: {e}"))?;
        let mut writer = BufWriter::new(file);
        writer
            .write_all(&bytes)
            .map_err(|e| format!("error:write pb: {e}"))?;
        writer.flush().map_err(|e| format!("error:flush pb: {e}"))?;
    }
    std::fs::rename(&tmp, path).map_err(|e| {
        let _ = std::fs::remove_file(&tmp);
        format!("error:rename pb: {e}")
    })
}

use std::sync::Once;

static REGISTER_HOOKS: Once = Once::new();

/// Register PB encode/decode hooks with `volward-core` (idempotent, safe to call multiple times).
pub fn ensure_registered() {
    REGISTER_HOOKS.call_once(|| {
        volward_core::manifest::register_index_pb_writer(
            write_snapshot_index_pb_atomic
                as volward_core::manifest::IndexPbWriterFn,
        );
        volward_core::manifest::register_index_pb_decoder(
            decode_snapshot_index as volward_core::manifest::IndexPbDecoderFn,
        );
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use volward_core::model::{
        CapabilityLevel, EntryCategory, RiskLevel, ScanStats, ScanTreeNode, SourceType,
        StorageEntry, StorageSnapshot,
    };

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
        let index = SnapshotIndex::from(&minimal_snapshot());
        let pb = snapshot_index_to_proto(&index);
        assert_eq!(pb.format_version, SNAPSHOT_INDEX_FORMAT_VERSION);
        let bytes = pb.encode_to_vec();
        let restored = decode_snapshot_index(&bytes).unwrap();
        assert_eq!(
            restored.summary_json().unwrap(),
            index.summary_json().unwrap()
        );
    }

    #[test]
    fn write_and_read_atomic_roundtrip() {
        let tmp = tempfile::TempDir::new().expect("temp dir");
        let index = SnapshotIndex::from(&minimal_snapshot());
        let path = tmp.path().join("cache.pb");
        let path_str = path.to_string_lossy();

        write_snapshot_index_pb_atomic(&index, &path_str).expect("write pb");

        let loaded = decode_snapshot_index(&std::fs::read(&path).unwrap()).unwrap();
        assert_eq!(
            loaded.summary_json().unwrap(),
            index.summary_json().unwrap()
        );
    }
}
