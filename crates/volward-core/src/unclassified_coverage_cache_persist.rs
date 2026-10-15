//! On-disk sidecar for [`super::UnclassifiedCoverageCache`] (spec §2 方案 C).

use std::collections::HashMap;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::coverage_funnel::{CoverageFunnelContextMap, CoverageFunnelStats};
use crate::scan::default_data_dir;

pub const COVERAGE_CACHE_FILE_MAGIC: [u8; 4] = *b"VWCC";
pub const COVERAGE_CACHE_FILE_VERSION: u32 = 1;

pub fn coverage_cache_bin_path(snapshot_id: &str) -> PathBuf {
    default_data_dir().join(format!("{snapshot_id}.coverage_cache.bin"))
}

pub fn coverage_cache_meta_path(snapshot_id: &str) -> PathBuf {
    default_data_dir().join(format!("{snapshot_id}.coverage_cache.json"))
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
pub struct PersistedDirUnclassifiedAgg {
    pub unclassified_files: u64,
    pub local_files: u64,
    pub ai_pending_files: u64,
    pub ext_counts: HashMap<String, u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CoverageCachePersistedV1 {
    pub snapshot_id: String,
    pub index_version: u64,
    pub funnel_map: CoverageFunnelContextMap,
    pub classified: Vec<String>,
    pub funnel_stats: CoverageFunnelStats,
    pub subtree_by_dir: HashMap<String, PersistedDirUnclassifiedAgg>,
    pub tail_file_paths: Vec<(String, u64)>,
    pub funnel_largest_files: Vec<(String, u64)>,
    pub total_unclassified_file_count: usize,
}

pub fn save_coverage_cache_bin(
    path: &Path,
    payload: &CoverageCachePersistedV1,
) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let json = serde_json::to_vec(payload).map_err(std::io::Error::other)?;
    let tmp = path.with_extension("bintmp");
    {
        let mut file = std::fs::File::create(&tmp)?;
        file.write_all(&COVERAGE_CACHE_FILE_MAGIC)?;
        file.write_all(&COVERAGE_CACHE_FILE_VERSION.to_le_bytes())?;
        file.write_all(&json)?;
    }
    std::fs::rename(&tmp, path).or_else(|e| {
        let _ = std::fs::remove_file(&tmp);
        Err(e)
    })
}

pub fn load_coverage_cache_bin(path: &Path) -> Option<CoverageCachePersistedV1> {
    let mut file = std::fs::File::open(path).ok()?;
    let mut magic = [0u8; 4];
    file.read_exact(&mut magic).ok()?;
    if magic != COVERAGE_CACHE_FILE_MAGIC {
        return None;
    }
    let mut version_bytes = [0u8; 4];
    file.read_exact(&mut version_bytes).ok()?;
    let version = u32::from_le_bytes(version_bytes);
    if version != COVERAGE_CACHE_FILE_VERSION {
        return None;
    }
    let mut json = Vec::new();
    file.read_to_end(&mut json).ok()?;
    serde_json::from_slice(&json).ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn coverage_cache_bin_path_uses_default_data_dir() {
        let p = coverage_cache_bin_path("snap-1");
        assert_eq!(
            p.file_name().and_then(|n| n.to_str()),
            Some("snap-1.coverage_cache.bin")
        );
        assert!(p.parent().is_some());
    }

    #[test]
    fn save_and_load_coverage_cache_bin_roundtrips() {
        let dir = std::env::temp_dir().join("vwcc-persist-rt");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("snap.coverage_cache.bin");
        let wire = CoverageCachePersistedV1 {
            snapshot_id: "snap".into(),
            index_version: 2,
            funnel_map: Default::default(),
            classified: vec!["/a".into()],
            funnel_stats: CoverageFunnelStats {
                local_safe_files: 1,
                ..Default::default()
            },
            subtree_by_dir: Default::default(),
            tail_file_paths: vec![("/t".into(), 9)],
            funnel_largest_files: vec![("/t".into(), 9)],
            total_unclassified_file_count: 1,
        };
        save_coverage_cache_bin(&path, &wire).unwrap();
        assert_eq!(load_coverage_cache_bin(&path).unwrap(), wire);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn load_coverage_cache_bin_rejects_bad_magic() {
        let dir = std::env::temp_dir().join("vwcc-bad-magic");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("x.bin");
        std::fs::write(&path, b"NOPE").unwrap();
        assert!(load_coverage_cache_bin(&path).is_none());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
