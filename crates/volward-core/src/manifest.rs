use std::collections::HashMap;
use std::fs::File;
use std::hash::{Hash, Hasher};
use std::io::{BufReader, BufWriter, Write};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::index::SnapshotIndex;
use crate::model::StorageSnapshot;

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
    #[serde(default)]
    pub snapshot_path: Option<String>,
    pub dir_fingerprints: HashMap<String, DirFingerprint>,
}

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

fn hash_root(root: &str) -> String {
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
        let path = self.path_for_root(root);
        let temp_path = temp_path_for(&path);
        let file = File::create(&temp_path).map_err(|e| e.to_string())?;
        let mut writer = BufWriter::new(file);
        serde_json::to_writer(&mut writer, index).map_err(|e| e.to_string())?;
        writer.flush().map_err(|e| e.to_string())?;
        std::fs::rename(&temp_path, &path).map_err(|e| e.to_string())?;
        Ok(path)
    }

    pub fn load_snapshot(&self, root: &str) -> Option<StorageSnapshot> {
        let file = File::open(self.path_for_root(root)).ok()?;
        serde_json::from_reader(BufReader::new(file)).ok()
    }

    pub fn load_index(&self, root: &str) -> Option<SnapshotIndex> {
        let file = File::open(self.path_for_root(root)).ok()?;
        serde_json::from_reader::<_, SnapshotIndex>(BufReader::new(file)).ok()
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
}
