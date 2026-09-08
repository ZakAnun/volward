use std::collections::HashMap;
use std::fs::File;
use std::hash::{Hash, Hasher};
use std::io::{BufReader, BufWriter, Write};
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

use serde::{Deserialize, Serialize};

use crate::index::SnapshotIndex;
use crate::model::StorageSnapshot;

/// Registered by the platform layer (`volward-index-pb`) at startup.
pub type IndexPbWriterFn = fn(&SnapshotIndex, &str) -> Result<(), String>;

static INDEX_PB_WRITER: OnceLock<IndexPbWriterFn> = OnceLock::new();

/// Register the protobuf index writer (called once from `volward-facade` init).
pub fn register_index_pb_writer(writer: IndexPbWriterFn) {
    let _ = INDEX_PB_WRITER.set(writer);
}

fn write_index_pb(index: &SnapshotIndex, path: &str) -> Result<(), String> {
    INDEX_PB_WRITER
        .get()
        .ok_or_else(|| "SnapshotIndex PB writer not registered".to_string())?(index, path)
}

/// Decode a persisted index from raw bytes (`.pb` wire format).
pub type IndexPbDecoderFn = fn(&[u8]) -> Result<SnapshotIndex, String>;

static INDEX_PB_DECODER: OnceLock<IndexPbDecoderFn> = OnceLock::new();

pub fn register_index_pb_decoder(decoder: IndexPbDecoderFn) {
    let _ = INDEX_PB_DECODER.set(decoder);
}

fn decode_index_pb(bytes: &[u8]) -> Result<SnapshotIndex, String> {
    INDEX_PB_DECODER
        .get()
        .ok_or_else(|| "SnapshotIndex PB decoder not registered".to_string())?(bytes)
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct DirFingerprint {
    pub mtime_secs: i64,
    pub children_count: u32,
    /// Latest modification time among immediate children (files + dirs).
    #[serde(default)]
    pub max_child_mtime_secs: i64,
}

impl DirFingerprint {
    pub fn matches(&self, other: &Self) -> bool {
        self.mtime_secs == other.mtime_secs
            && self.children_count == other.children_count
            && self.max_child_mtime_secs == other.max_child_mtime_secs
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ScanManifest {
    pub root: String,
    pub scanned_at_ms: i64,
    pub snapshot_id: String,
    /// Bumped whenever recorded sizes change meaning (logical → physical
    /// allocated bytes). Older manifests must not be reused for incremental
    /// scans, otherwise a snapshot would mix old and new size semantics.
    #[serde(default)]
    pub size_accounting: u32,
    #[serde(default)]
    pub snapshot_path: Option<String>,
    pub dir_fingerprints: HashMap<String, DirFingerprint>,
}

/// Current size accounting format. Incremental caches written by older builds
/// (default `0`) are rejected and force a full re-scan.
pub const SIZE_ACCOUNTING_VERSION: u32 = 1;

pub trait ManifestStore {
    fn load(&self, root: &str) -> Option<ScanManifest>;
    fn save(&self, manifest: &ScanManifest) -> Result<(), String>;
}

pub struct FileManifestStore {
    base_dir: PathBuf,
}

impl FileManifestStore {
    pub fn new(base_dir: impl Into<PathBuf>) -> Self {
        Self {
            base_dir: base_dir.into(),
        }
    }

    fn path_for_root(&self, root: &str) -> PathBuf {
        self.base_dir.join(format!("{}.json", hash_root(root)))
    }
}

pub(crate) fn hash_root(root: &str) -> String {
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    root.hash(&mut hasher);
    format!("{:016x}", hasher.finish())
}

impl ManifestStore for FileManifestStore {
    fn load(&self, root: &str) -> Option<ScanManifest> {
        let path = self.path_for_root(root);
        let json = std::fs::read_to_string(path).ok()?;
        serde_json::from_str(&json).ok()
    }

    fn save(&self, manifest: &ScanManifest) -> Result<(), String> {
        std::fs::create_dir_all(&self.base_dir).map_err(|e| e.to_string())?;
        let path = self.path_for_root(&manifest.root);
        let json = serde_json::to_string_pretty(manifest).map_err(|e| e.to_string())?;
        let temp_path = temp_path_for(&path);
        std::fs::write(&temp_path, json).map_err(|e| e.to_string())?;
        std::fs::rename(&temp_path, &path).map_err(|e| e.to_string())?;
        Ok(())
    }
}

pub struct FileSnapshotStore {
    base_dir: PathBuf,
}

impl FileSnapshotStore {
    pub fn new(base_dir: impl Into<PathBuf>) -> Self {
        Self {
            base_dir: base_dir.into(),
        }
    }

    pub fn path_for_root(&self, root: &str) -> PathBuf {
        self.base_dir.join(format!("{}.json", hash_root(root)))
    }

    pub fn index_path_for_root(&self, root: &str) -> PathBuf {
        self.base_dir.join(format!("{}.pb", hash_root(root)))
    }

    pub fn save_snapshot(&self, root: &str, snapshot: &StorageSnapshot) -> Result<PathBuf, String> {
        std::fs::create_dir_all(&self.base_dir).map_err(|e| e.to_string())?;
        let path = self.path_for_root(root);
        let temp_path = temp_path_for(&path);
        let file = File::create(&temp_path).map_err(|e| e.to_string())?;
        let mut writer = BufWriter::new(file);
        serde_json::to_writer(&mut writer, snapshot).map_err(|e| e.to_string())?;
        writer.flush().map_err(|e| e.to_string())?;
        std::fs::rename(&temp_path, &path).map_err(|e| e.to_string())?;
        Ok(path)
    }

    pub fn save_index(&self, root: &str, index: &SnapshotIndex) -> Result<PathBuf, String> {
        std::fs::create_dir_all(&self.base_dir).map_err(|e| e.to_string())?;
        let path = self.index_path_for_root(root);
        write_index_pb(index, &path.to_string_lossy())?;

        // Best-effort cleanup of legacy JSON cache for the same root hash.
        let legacy_json = self.path_for_root(root);
        let _ = std::fs::remove_file(legacy_json);

        Ok(path)
    }

    /// Load a persisted index from an explicit path (`.pb` or legacy `.json`).
    pub fn load_index_from_path(path: &Path) -> Option<SnapshotIndex> {
        match path.extension().and_then(|ext| ext.to_str()) {
            Some("pb") => {
                let bytes = std::fs::read(path).ok()?;
                decode_index_pb(&bytes).ok()
            }
            _ => {
                let file = File::open(path).ok()?;
                serde_json::from_reader::<_, SnapshotIndex>(BufReader::new(file)).ok()
            }
        }
    }

    pub fn load_snapshot(&self, root: &str) -> Option<StorageSnapshot> {
        let file = File::open(self.path_for_root(root)).ok()?;
        serde_json::from_reader(BufReader::new(file)).ok()
    }

    pub fn load_index(&self, root: &str) -> Option<SnapshotIndex> {
        let pb_path = self.index_path_for_root(root);
        if pb_path.exists() {
            return Self::load_index_from_path(&pb_path);
        }
        let json_path = self.path_for_root(root);
        if json_path.exists() {
            return Self::load_index_from_path(&json_path);
        }
        None
    }
}

fn temp_path_for(path: &Path) -> PathBuf {
    path.with_extension("json.tmp")
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn sample_manifest(root: &str) -> ScanManifest {
        let mut dir_fingerprints = HashMap::new();
        dir_fingerprints.insert(
            format!("{root}/subdir"),
            DirFingerprint {
                mtime_secs: 1_700_000_000,
                children_count: 42,
                max_child_mtime_secs: 1_700_000_100,
            },
        );
        ScanManifest {
            root: root.to_string(),
            scanned_at_ms: 1_700_000_123_456,
            snapshot_id: "snap-001".to_string(),
            size_accounting: SIZE_ACCOUNTING_VERSION,
            snapshot_path: Some("/tmp/volward/snapshots/snap-001.json".to_string()),
            dir_fingerprints,
        }
    }

    #[test]
    fn roundtrip_save_and_load() {
        let tmp = TempDir::new().expect("temp dir");
        let store = FileManifestStore::new(tmp.path());
        let manifest = sample_manifest("/Users/test/Documents");

        store.save(&manifest).expect("save should succeed");

        let loaded = store
            .load("/Users/test/Documents")
            .expect("load should succeed");
        assert_eq!(loaded, manifest);
    }

    #[test]
    fn corrupt_file_returns_none_on_load() {
        let tmp = TempDir::new().expect("temp dir");
        let store = FileManifestStore::new(tmp.path());
        let root = "/Users/test/Corrupt";

        let path = store.path_for_root(root);
        std::fs::create_dir_all(path.parent().unwrap()).expect("create parent");
        std::fs::write(&path, "{ not valid json").expect("write corrupt file");

        assert!(store.load(root).is_none());
    }

    #[test]
    fn old_manifest_without_snapshot_path_loads_with_none() {
        let manifest: ScanManifest = serde_json::from_str(
            r#"{
                "root": "/Users/test/Legacy",
                "scanned_at_ms": 1700000123456,
                "snapshot_id": "legacy-snapshot",
                "dir_fingerprints": {}
            }"#,
        )
        .expect("legacy manifest should deserialize");

        assert_eq!(manifest.snapshot_path, None);
    }

    #[test]
    fn legacy_manifest_without_max_child_mtime_defaults_to_zero() {
        let fp: DirFingerprint = serde_json::from_str(r#"{"mtime_secs":1,"children_count":2}"#)
            .expect("legacy fingerprint");
        assert_eq!(fp.max_child_mtime_secs, 0);
        assert!(!fp.matches(&DirFingerprint {
            mtime_secs: 1,
            children_count: 2,
            max_child_mtime_secs: 99,
        }));
    }

    #[test]
    fn fingerprint_matches_requires_max_child_mtime() {
        let a = DirFingerprint {
            mtime_secs: 1,
            children_count: 2,
            max_child_mtime_secs: 100,
        };
        let b = DirFingerprint {
            mtime_secs: 1,
            children_count: 2,
            max_child_mtime_secs: 101,
        };
        assert!(a.matches(&a));
        assert!(!a.matches(&b));
    }

    #[test]
    fn snapshot_roundtrip_save_and_load() {
        let tmp = TempDir::new().expect("temp dir");
        let store = FileSnapshotStore::new(tmp.path());
        let root = "/Users/test/Documents";
        let snapshot = StorageSnapshot {
            snapshot_id: "snap-001".to_string(),
            scanned_at_ms: 1_700_000_123_456,
            capability: crate::model::CapabilityLevel::FullPath,
            volume_total_bytes: 1_000,
            volume_used_bytes: 600,
            reclaimable_estimate_bytes: 100,
            entries: vec![],
            tree: crate::model::ScanTreeNode {
                name: "Documents".to_string(),
                path: root.to_string(),
                is_dir: true,
                size_bytes: 0,
                entry_id: None,
                children: vec![],
            },
            stats: crate::model::ScanStats::default(),
            warnings: vec![],
        };

        let saved_path = store
            .save_snapshot(root, &snapshot)
            .expect("snapshot save should succeed");
        assert_eq!(saved_path, store.path_for_root(root));

        let loaded = store
            .load_snapshot(root)
            .expect("snapshot load should succeed");
        assert_eq!(loaded.snapshot_id, snapshot.snapshot_id);
        assert_eq!(loaded.scanned_at_ms, snapshot.scanned_at_ms);
        assert_eq!(loaded.tree.path, snapshot.tree.path);
    }

    #[test]
    fn load_index_falls_back_to_legacy_json() {
        use crate::model::{
            CapabilityLevel, EntryCategory, RiskLevel, ScanStats, ScanTreeNode, SourceType,
            StorageEntry,
        };

        let tmp = TempDir::new().expect("temp dir");
        let store = FileSnapshotStore::new(tmp.path());
        let root = "/Users/test/LegacyIndex";
        let snapshot = StorageSnapshot {
            snapshot_id: "legacy-index".to_string(),
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
                path: root.to_string(),
                is_dir: true,
                size_bytes: 10,
                entry_id: None,
                children: vec![],
            },
            stats: ScanStats::default(),
            warnings: vec![],
        };
        let index = SnapshotIndex::from(&snapshot);
        let json_path = store.path_for_root(root);
        std::fs::create_dir_all(json_path.parent().unwrap()).expect("create parent");
        let file = File::create(&json_path).expect("create json");
        serde_json::to_writer(file, &index).expect("write json");

        let loaded = store.load_index(root).expect("legacy json load");
        assert_eq!(
            loaded.summary_json().unwrap(),
            index.summary_json().unwrap()
        );
    }
}
