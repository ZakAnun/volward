use std::collections::HashMap;
use std::fs::File;
use std::io::{BufReader, BufWriter, Write};
use std::path::{Path, PathBuf};

use crate::index::SnapshotIndex;
use crate::manifest::{hash_root, DirFingerprint, ScanManifest, SIZE_ACCOUNTING_VERSION};

pub struct FilePauseStore {
    base_dir: PathBuf,
}

impl FilePauseStore {
    pub fn new(base_dir: impl Into<PathBuf>) -> Self {
        Self {
            base_dir: base_dir.into(),
        }
    }

    pub fn save(
        &self,
        root: &str,
        index: &SnapshotIndex,
        fingerprints: &HashMap<String, DirFingerprint>,
    ) -> Result<(), String> {
        std::fs::create_dir_all(&self.base_dir).map_err(|error| error.to_string())?;
        let index_path = self.index_path(root);
        write_json_atomically(&index_path, index)?;

        let manifest = ScanManifest {
            root: root.to_string(),
            scanned_at_ms: index.scanned_at_ms,
            snapshot_id: index.snapshot_id.clone(),
            size_accounting: SIZE_ACCOUNTING_VERSION,
            snapshot_path: Some(index_path.to_string_lossy().into_owned()),
            dir_fingerprints: fingerprints.clone(),
        };
        write_json_atomically(&self.manifest_path(root), &manifest)
    }

    pub fn load(&self, root: &str) -> Option<(ScanManifest, SnapshotIndex)> {
        let manifest: ScanManifest =
            serde_json::from_reader(BufReader::new(File::open(self.manifest_path(root)).ok()?))
                .ok()?;
        let index: SnapshotIndex =
            serde_json::from_reader(BufReader::new(File::open(self.index_path(root)).ok()?))
                .ok()?;
        (manifest.root == root && manifest.snapshot_id == index.snapshot_id)
            .then_some((manifest, index))
    }

    pub fn clear(&self, root: &str) -> Result<(), String> {
        let mut failures = Vec::new();
        for path in [self.index_path(root), self.manifest_path(root)] {
            match std::fs::remove_file(&path) {
                Ok(()) => {}
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                Err(error) => failures.push(format!("{}: {error}", path.display())),
            }
        }
        if failures.is_empty() {
            Ok(())
        } else {
            Err(format!(
                "failed to clear pause artifacts: {}",
                failures.join("; ")
            ))
        }
    }

    pub fn index_path(&self, root: &str) -> PathBuf {
        self.base_dir
            .join(format!("{}.index.json", hash_root(root)))
    }

    fn manifest_path(&self, root: &str) -> PathBuf {
        self.base_dir
            .join(format!("{}.manifest.json", hash_root(root)))
    }
}

fn write_json_atomically(path: &Path, value: &impl serde::Serialize) -> Result<(), String> {
    let temp_path = path.with_extension("json.tmp");
    let file = File::create(&temp_path).map_err(|error| error.to_string())?;
    let mut writer = BufWriter::new(file);
    serde_json::to_writer(&mut writer, value).map_err(|error| error.to_string())?;
    writer.flush().map_err(|error| error.to_string())?;
    std::fs::rename(temp_path, path).map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::index::SnapshotIndexBuilder;
    use crate::manifest::{DirFingerprint, SIZE_ACCOUNTING_VERSION};
    use crate::model::ScanStats;
    use std::collections::HashMap;
    use tempfile::TempDir;

    #[test]
    fn pause_roundtrip_does_not_use_completed_snapshot_path() {
        let tmp = TempDir::new().unwrap();
        let store = FilePauseStore::new(tmp.path());
        let index = SnapshotIndexBuilder::new("/Users/test/Downloads").finish(
            "pause-1".to_string(),
            1,
            1,
            "Cancelled".to_string(),
            ScanStats::default(),
        );
        let mut fps = HashMap::new();
        fps.insert(
            "/Users/test/Downloads".to_string(),
            DirFingerprint {
                mtime_secs: 1,
                children_count: 2,
                max_child_mtime_secs: 2,
            },
        );

        store.save("/Users/test/Downloads", &index, &fps).unwrap();
        let (manifest, loaded) = store.load("/Users/test/Downloads").unwrap();
        assert_eq!(manifest.root, "/Users/test/Downloads");
        assert_eq!(manifest.size_accounting, SIZE_ACCOUNTING_VERSION);
        assert_eq!(loaded.root_path, index.root_path);
        assert!(manifest
            .snapshot_path
            .as_deref()
            .is_some_and(|path| path.ends_with(".index.json")));
        store.clear("/Users/test/Downloads").unwrap();
        assert!(store.load("/Users/test/Downloads").is_none());
    }

    #[test]
    fn clear_reports_pause_artifacts_that_cannot_be_removed() {
        let tmp = TempDir::new().unwrap();
        let store = FilePauseStore::new(tmp.path());
        let root = "/Users/test/Downloads";
        std::fs::create_dir_all(store.manifest_path(root)).unwrap();

        let error = store
            .clear(root)
            .expect_err("a remaining pause artifact must be reported");

        assert!(error.contains("manifest.json"));
        assert!(store.manifest_path(root).is_dir());
    }
}
