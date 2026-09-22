//! Encodes `volward-core` model types into generated protobuf messages.
//!
//! Enum fields are written as their raw proto field numbers (`i32`) rather than
//! the generated Rust enum variants, so this layer stays correct regardless of
//! how prost happens to name those variants — the wire numbers are fixed by
//! `proto/volward.proto` and mirrored here.
//!
//! `StorageSnapshot` encode-only lives here; `SnapshotIndex` encode/decode is
//! delegated to the shared `volward-index-pb` crate.

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

fn capability_from_pb(v: i32) -> model::CapabilityLevel {
    match v {
        1 => model::CapabilityLevel::FullPath,
        2 => model::CapabilityLevel::AppStatsOnly,
        3 => model::CapabilityLevel::GuidedOnly,
        _ => model::CapabilityLevel::FullPath,
    }
}

fn category_from_pb(v: i32) -> model::EntryCategory {
    match v {
        1 => model::EntryCategory::Cache,
        2 => model::EntryCategory::Temp,
        3 => model::EntryCategory::Media,
        4 => model::EntryCategory::AppData,
        5 => model::EntryCategory::Orphan,
        6 => model::EntryCategory::Duplicate,
        7 => model::EntryCategory::System,
        8 => model::EntryCategory::Unknown,
        9 => model::EntryCategory::BuildArtifact,
        _ => model::EntryCategory::Unknown,
    }
}

fn risk_from_pb(v: i32) -> model::RiskLevel {
    match v {
        1 => model::RiskLevel::Low,
        2 => model::RiskLevel::Medium,
        3 => model::RiskLevel::High,
        _ => model::RiskLevel::Low,
    }
}

fn source_from_pb(v: i32) -> model::SourceType {
    match v {
        1 => model::SourceType::Directory,
        2 => model::SourceType::File,
        3 => model::SourceType::Volume,
        4 => model::SourceType::Application,
        _ => model::SourceType::File,
    }
}

fn storage_entry_from_proto(e: proto::StorageEntry) -> model::StorageEntry {
    model::StorageEntry {
        id: e.id,
        display_name: e.display_name,
        path_or_uri: e.path_or_uri,
        size_bytes: e.size_bytes,
        category: category_from_pb(e.category),
        risk_level: risk_from_pb(e.risk_level),
        source_type: source_from_pb(e.source_type),
        deletable: e.deletable,
        reason: e.reason,
        modified_at_ms: e.modified_at_ms,
    }
}

fn scan_tree_from_proto(n: proto::ScanTreeNode) -> model::ScanTreeNode {
    model::ScanTreeNode {
        name: n.name,
        path: n.path,
        is_dir: n.is_dir,
        size_bytes: n.size_bytes,
        entry_id: n.entry_id,
        children: n.children.into_iter().map(scan_tree_from_proto).collect(),
    }
}

fn scan_stats_from_proto(s: proto::ScanStats) -> model::ScanStats {
    model::ScanStats {
        paths_seen: s.paths_seen,
        dirs_seen: s.dirs_seen,
        files_seen: s.files_seen,
        files_in_snapshot: s.files_in_snapshot,
        paths_skipped: s.paths_skipped,
        truncated: s.truncated,
        incomplete_reason: s.incomplete_reason,
    }
}

use volward_core::{AiAnalysisResult, AiCandidate, AiCandidateSet, PreClassifiedEntry};

/// Encode the AI pre-check / candidate payload for async spill (`.pb`).
pub fn encode_ai_candidates_payload_pb(
    snapshot_id: &str,
    set: &AiCandidateSet,
    has_existing_result: bool,
    cache_key: &str,
    root_path: &str,
) -> Vec<u8> {
    use prost::Message;

    let pre_classified = set
        .pre_classified
        .iter()
        .map(pre_classified_to_proto)
        .collect();
    let unknown_candidates = set.candidates.iter().map(ai_candidate_to_proto).collect();
    let pb = proto::AiCandidatesPayload {
        snapshot_id: snapshot_id.to_string(),
        root_path: root_path.to_string(),
        result_cache_key: cache_key.to_string(),
        pre_classified,
        unknown_candidates,
        estimated_input_tokens: set.estimated_input_tokens as u32,
        estimated_byok_batch_input_tokens: set.estimated_byok_batch_input_tokens as u32,
        total_raw_count: set.total_raw_count as u32,
        candidates_total_before_cap: set.candidates_total_before_cap as u32,
        truncated: set.truncated,
        pre_classified_truncated: set.pre_classified_truncated,
        has_existing_result,
    };
    pb.encode_to_vec()
}

fn pre_classified_to_proto(entry: &PreClassifiedEntry) -> proto::AiPreClassifiedEntry {
    proto::AiPreClassifiedEntry {
        path: entry.path.clone(),
        size_bytes: entry.size_bytes,
        is_dir: entry.is_dir,
        category: category_pb(entry.category) as u32,
        confidence: entry.confidence.clone(),
        reason: entry.reason.clone(),
        deletable: entry.deletable,
    }
}

fn ai_candidate_to_proto(c: &AiCandidate) -> proto::AiUnknownCandidate {
    proto::AiUnknownCandidate {
        path: c.path.clone(),
        size_bytes: c.size_bytes,
        is_dir: c.is_dir,
        child_count: c.child_count.map(|v| v as u32),
        extension: c.extension.clone(),
        cleanup_source: c.cleanup_source.clone(),
        cleanup_hint: c.cleanup_hint.clone(),
        retention_days: c.retention_days,
        member_paths: c.member_paths.clone(),
        delete_target: c.delete_target.clone(),
    }
}

/// Re-encode the JSON emitted by [`serialize_ai_candidate_set`] on a worker thread.
pub fn encode_ai_candidates_payload_from_json(json: &str) -> Result<Vec<u8>, String> {
    use serde::Deserialize;

    #[derive(Deserialize)]
    struct Payload {
        snapshot_id: String,
        root_path: String,
        result_cache_key: String,
        pre_classified: Vec<PreClassifiedEntry>,
        unknown_candidates: Vec<AiCandidate>,
        estimated_input_tokens: usize,
        #[serde(default)]
        estimated_byok_batch_input_tokens: usize,
        total_raw_count: usize,
        candidates_total_before_cap: usize,
        truncated: bool,
        pre_classified_truncated: bool,
        has_existing_result: bool,
    }

    let payload: Payload =
        serde_json::from_str(json).map_err(|e| format!("error:decode candidates json: {e}"))?;
    let set = AiCandidateSet {
        pre_classified: payload.pre_classified,
        candidates: payload.unknown_candidates,
        estimated_input_tokens: payload.estimated_input_tokens,
        estimated_byok_batch_input_tokens: payload.estimated_byok_batch_input_tokens,
        total_raw_count: payload.total_raw_count,
        candidates_total_before_cap: payload.candidates_total_before_cap,
        truncated: payload.truncated,
        pre_classified_truncated: payload.pre_classified_truncated,
    };
    Ok(encode_ai_candidates_payload_pb(
        &payload.snapshot_id,
        &set,
        payload.has_existing_result,
        &payload.result_cache_key,
        &payload.root_path,
    ))
}

/// Encode a saved AI analysis result for `{key}.pb` beside legacy JSON.
pub fn encode_ai_analysis_result_pb(result: &AiAnalysisResult) -> Vec<u8> {
    use prost::Message;

    let entries = result
        .entries
        .iter()
        .map(|entry| proto::AiVerdictEntryWire {
            path: entry.path.clone(),
            size_bytes: entry.size_bytes,
            verdict: entry.verdict.clone(),
            confidence: entry.confidence.clone(),
            reason: entry.reason.clone(),
            cleanup_source: entry.cleanup_source.clone(),
            cleanup_hint: entry.cleanup_hint.clone(),
            retention_days: entry.retention_days,
        })
        .collect();
    let pb = proto::AiAnalysisResultWire {
        schema_version: result.schema_version,
        snapshot_id: result.snapshot_id.clone(),
        cache_key: result.cache_key.clone(),
        root_path: result.root_path.clone(),
        analyzed_at_ms: result.analyzed_at_ms,
        mode: result.mode.clone(),
        model: result.model.clone(),
        entries,
        token_usage: Some(proto::AiTokenUsageWire {
            input: result.token_usage.input,
            output: result.token_usage.output,
        }),
        cost_estimate_usd: result.cost_estimate_usd,
        credits_used: result.credits_used,
    };
    pb.encode_to_vec()
}

/// Decode a [`StorageSnapshot`] from protobuf bytes (Flutter/Rust file I/O).
pub fn decode_storage_snapshot_from_pb(bytes: &[u8]) -> Result<model::StorageSnapshot, String> {
    use prost::Message;

    let pb = proto::StorageSnapshot::decode(bytes).map_err(|e| format!("decode pb snapshot: {e}"))?;
    Ok(model::StorageSnapshot {
        snapshot_id: pb.snapshot_id,
        scanned_at_ms: pb.scanned_at_ms,
        capability: capability_from_pb(pb.capability),
        volume_total_bytes: pb.volume_total_bytes,
        volume_used_bytes: pb.volume_used_bytes,
        reclaimable_estimate_bytes: pb.reclaimable_estimate_bytes,
        entries: pb.entries.into_iter().map(storage_entry_from_proto).collect(),
        tree: pb
            .tree
            .map(scan_tree_from_proto)
            .unwrap_or_else(|| model::ScanTreeNode {
                name: String::new(),
                path: String::new(),
                is_dir: true,
                size_bytes: 0,
                entry_id: None,
                children: vec![],
            }),
        stats: pb.stats.map(scan_stats_from_proto).unwrap_or_default(),
        warnings: pb.warnings,
    })
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
    fn encode_ai_candidates_payload_from_json_allows_missing_member_paths() {
        let json = r#"{
            "snapshot_id": "snap-1",
            "root_path": "/tmp",
            "result_cache_key": "key-1",
            "pre_classified": [],
            "unknown_candidates": [{
                "path": "/tmp/a.cache",
                "size_bytes": 10,
                "is_dir": false
            }],
            "estimated_input_tokens": 100,
            "total_raw_count": 1,
            "candidates_total_before_cap": 1,
            "truncated": false,
            "pre_classified_truncated": false,
            "has_existing_result": false
        }"#;
        let bytes = encode_ai_candidates_payload_from_json(json).expect("encode");
        assert!(!bytes.is_empty());
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

    #[test]
    fn decode_storage_snapshot_from_pb_round_trips_model() {
        use prost::Message;
        let original = sample();
        let bytes = proto::StorageSnapshot::from(&original).encode_to_vec();
        let decoded = decode_storage_snapshot_from_pb(&bytes).expect("decode model");
        assert_eq!(decoded.snapshot_id, original.snapshot_id);
        assert_eq!(decoded.entries.len(), original.entries.len());
        assert_eq!(decoded.tree.path, original.tree.path);
        assert_eq!(decoded.tree.children[0].path, original.tree.children[0].path);
    }
}
