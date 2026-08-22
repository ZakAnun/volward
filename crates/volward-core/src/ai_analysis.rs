use serde::{Deserialize, Serialize};
use std::path::PathBuf;

use crate::ai_candidates::AiCandidateSet;
use crate::model::ScanStats;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AiVerdictEntry {
    pub path: String,
    pub size_bytes: u64,
    pub verdict: String,
    pub confidence: String,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiTokenUsage {
    pub input: u64,
    pub output: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiAnalysisResult {
    pub schema_version: u32,
    pub snapshot_id: String,
    /// Stable reuse key: same scan root + AI-relevant content → same key.
    /// Preferred file name under `ai_analysis/`. Absent on legacy saves.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cache_key: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub root_path: Option<String>,
    pub analyzed_at_ms: i64,
    pub mode: String,
    pub model: String,
    pub entries: Vec<AiVerdictEntry>,
    pub token_usage: AiTokenUsage,
    pub cost_estimate_usd: f64,
    #[serde(default)]
    pub credits_used: u32,
}

impl AiAnalysisResult {
    pub fn load(key: &str) -> Option<Self> {
        let json = std::fs::read_to_string(analysis_path(key)).ok()?;
        serde_json::from_str(&json).ok()
    }

    pub fn save(&self, key: &str) -> Result<(), String> {
        let path = analysis_path(key);
        std::fs::create_dir_all(path.parent().unwrap()).map_err(|e| e.to_string())?;
        let json = serde_json::to_string_pretty(self).map_err(|e| e.to_string())?;
        let tmp = path.with_extension("tmp");
        std::fs::write(&tmp, &json).map_err(|e| e.to_string())?;
        std::fs::rename(&tmp, &path).map_err(|e| {
            let _ = std::fs::remove_file(&tmp);
            e.to_string()
        })
    }

    /// Persist under the stable [cache_key] (when present) and also under
    /// [snapshot_id] so in-session lookup by either id still works.
    pub fn save_for_reuse(&self) -> Result<(), String> {
        if let Some(cache_key) = self.cache_key.as_deref() {
            if !cache_key.is_empty() {
                self.save(cache_key)?;
            }
        }
        if !self.snapshot_id.is_empty()
            && self.cache_key.as_deref() != Some(self.snapshot_id.as_str())
        {
            self.save(&self.snapshot_id)?;
        }
        Ok(())
    }

    pub fn exists(key: &str) -> bool {
        !key.is_empty() && analysis_path(key).exists()
    }
}

fn analysis_path(key: &str) -> PathBuf {
    crate::scan::default_data_dir()
        .join("ai_analysis")
        .join(format!("{key}.json"))
}

fn normalize_root(path: &str) -> String {
    let trimmed = path.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    let mut out = trimmed.replace('\\', "/");
    while out.len() > 1 && out.ends_with('/') {
        out.pop();
    }
    out
}

/// FNV-1a 64-bit — stable across Rust releases (unlike DefaultHasher).
fn fnv1a64(bytes: &[u8]) -> u64 {
    const OFFSET: u64 = 0xcbf29ce484222325;
    const PRIME: u64 = 0x100000001b3;
    let mut hash = OFFSET;
    for b in bytes {
        hash ^= u64::from(*b);
        hash = hash.wrapping_mul(PRIME);
    }
    hash
}

/// Content-addressed key so re-scanning an unchanged directory reuses AI results
/// even when `snapshot_id` is a fresh UUID.
pub fn compute_result_cache_key(
    root_path: &str,
    stats: &ScanStats,
    root_size_bytes: u64,
    reclaimable_estimate_bytes: u64,
    set: &AiCandidateSet,
) -> String {
    let mut material = String::with_capacity(512);
    material.push_str("v1|");
    material.push_str(&normalize_root(root_path));
    material.push('|');
    material.push_str(&format!(
        "files={}|dirs={}|paths={}|in_snap={}|root_size={}|reclaim={}|cand={}|pre={}",
        stats.files_seen,
        stats.dirs_seen,
        stats.paths_seen,
        stats.files_in_snapshot,
        root_size_bytes,
        reclaimable_estimate_bytes,
        set.candidates.len(),
        set.pre_classified.len(),
    ));

    let mut cand_lines: Vec<String> = set
        .candidates
        .iter()
        .map(|c| format!("{}:{}:{}", c.path, c.size_bytes, c.child_count.unwrap_or(0)))
        .collect();
    cand_lines.sort();
    for line in cand_lines {
        material.push('\n');
        material.push_str(&line);
    }

    let mut pre_lines: Vec<String> = set
        .pre_classified
        .iter()
        .map(|e| format!("{}:{}:{}", e.path, e.size_bytes, e.deletable))
        .collect();
    pre_lines.sort();
    for line in pre_lines {
        material.push('\n');
        material.push_str(&line);
    }

    format!("{:016x}", fnv1a64(material.as_bytes()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai_candidates::{AiCandidate, AiCandidateSet, PreClassifiedEntry};
    use crate::model::EntryCategory;
    use std::sync::Mutex;
    use tempfile::TempDir;

    static ENV_LOCK: Mutex<()> = Mutex::new(());

    fn empty_set() -> AiCandidateSet {
        AiCandidateSet {
            pre_classified: vec![],
            candidates: vec![],
            estimated_input_tokens: 0,
            total_raw_count: 0,
            candidates_total_before_cap: 0,
            truncated: false,
            pre_classified_truncated: false,
        }
    }

    fn sample_result(snapshot_id: &str) -> AiAnalysisResult {
        AiAnalysisResult {
            schema_version: 1,
            snapshot_id: snapshot_id.to_string(),
            cache_key: Some("cache-abc".into()),
            root_path: Some("/Users/x/Downloads".into()),
            analyzed_at_ms: 1_700_000_000_000,
            mode: "hosted".into(),
            model: "gpt-4o-mini".into(),
            entries: vec![AiVerdictEntry {
                path: "/Users/x/weird.xyz".into(),
                size_bytes: 1000,
                verdict: "safe_to_remove".into(),
                confidence: "medium".into(),
                reason: "looks like temp".into(),
            }],
            token_usage: AiTokenUsage {
                input: 100,
                output: 50,
            },
            cost_estimate_usd: 0.001,
            credits_used: 1,
        }
    }

    #[test]
    fn save_and_load_round_trip() {
        let _guard = ENV_LOCK.lock().unwrap();
        let tmp = TempDir::new().expect("temp dir");
        std::env::set_var("VOLWARD_CACHE_DIR", tmp.path());

        let id = "snap-round-trip";
        let result = sample_result(id);
        result.save(id).expect("save");
        let loaded = AiAnalysisResult::load(id).expect("load");
        assert_eq!(loaded.snapshot_id, id);
        assert_eq!(loaded.entries, result.entries);
        assert_eq!(loaded.token_usage.input, 100);
        assert_eq!(loaded.credits_used, 1);
        assert_eq!(loaded.cache_key.as_deref(), Some("cache-abc"));
    }

    #[test]
    fn exists_returns_false_before_save() {
        let _guard = ENV_LOCK.lock().unwrap();
        let tmp = TempDir::new().expect("temp dir");
        std::env::set_var("VOLWARD_CACHE_DIR", tmp.path());

        assert!(!AiAnalysisResult::exists("never-saved-id"));
    }

    #[test]
    fn save_overwrites_atomically() {
        let _guard = ENV_LOCK.lock().unwrap();
        let tmp = TempDir::new().expect("temp dir");
        std::env::set_var("VOLWARD_CACHE_DIR", tmp.path());

        let id = "snap-overwrite";
        sample_result(id).save(id).expect("save1");
        let mut second = sample_result(id);
        second.credits_used = 9;
        second.save(id).expect("save2");
        let loaded = AiAnalysisResult::load(id).expect("load");
        assert_eq!(loaded.credits_used, 9);
        assert!(!analysis_path(id).with_extension("tmp").exists());
    }

    #[test]
    fn save_for_reuse_writes_cache_key_and_snapshot_alias() {
        let _guard = ENV_LOCK.lock().unwrap();
        let tmp = TempDir::new().expect("temp dir");
        std::env::set_var("VOLWARD_CACHE_DIR", tmp.path());

        let result = sample_result("snap-1");
        result.save_for_reuse().expect("save");
        assert!(AiAnalysisResult::exists("cache-abc"));
        assert!(AiAnalysisResult::exists("snap-1"));
        let by_cache = AiAnalysisResult::load("cache-abc").expect("load cache");
        assert_eq!(by_cache.snapshot_id, "snap-1");
    }

    #[test]
    fn cache_key_stable_for_same_content_different_snapshot_stats_shape() {
        let stats = ScanStats {
            files_seen: 10,
            dirs_seen: 2,
            paths_seen: 12,
            files_in_snapshot: 3,
            ..ScanStats::default()
        };
        let mut set = empty_set();
        set.candidates.push(AiCandidate {
            path: "/Users/x/a.dat".into(),
            size_bytes: 100,
            is_dir: false,
            child_count: None,
            extension: Some(".dat".into()),
            member_paths: vec![],
            delete_member_paths: vec![],
        });
        let k1 = compute_result_cache_key("/Users/x/Downloads/", &stats, 999, 40, &set);
        let k2 = compute_result_cache_key("/Users/x/Downloads", &stats, 999, 40, &set);
        assert_eq!(k1, k2);
        assert_eq!(k1.len(), 16);
    }

    #[test]
    fn cache_key_changes_when_candidate_set_changes() {
        let stats = ScanStats {
            files_seen: 10,
            dirs_seen: 2,
            paths_seen: 12,
            ..ScanStats::default()
        };
        let mut set_a = empty_set();
        set_a.candidates.push(AiCandidate {
            path: "/Users/x/a.dat".into(),
            size_bytes: 100,
            is_dir: false,
            child_count: None,
            extension: None,
            member_paths: vec![],
            delete_member_paths: vec![],
        });
        let mut set_b = empty_set();
        set_b.candidates.push(AiCandidate {
            path: "/Users/x/b.dat".into(),
            size_bytes: 100,
            is_dir: false,
            child_count: None,
            extension: None,
            member_paths: vec![],
            delete_member_paths: vec![],
        });
        let k_a = compute_result_cache_key("/Users/x", &stats, 1, 0, &set_a);
        let k_b = compute_result_cache_key("/Users/x", &stats, 1, 0, &set_b);
        assert_ne!(k_a, k_b);
    }

    #[test]
    fn cache_key_changes_when_root_size_changes() {
        let stats = ScanStats::default();
        let set = empty_set();
        let k1 = compute_result_cache_key("/Users/x", &stats, 100, 0, &set);
        let k2 = compute_result_cache_key("/Users/x", &stats, 200, 0, &set);
        assert_ne!(k1, k2);
    }

    #[test]
    fn cache_key_includes_pre_classified() {
        let stats = ScanStats::default();
        let mut with_pre = empty_set();
        with_pre.pre_classified.push(PreClassifiedEntry {
            path: "/Users/x/node_modules".into(),
            size_bytes: 50,
            is_dir: true,
            category: EntryCategory::BuildArtifact,
            confidence: "high".into(),
            reason: "t".into(),
            deletable: true,
        });
        let k0 = compute_result_cache_key("/Users/x", &stats, 1, 0, &empty_set());
        let k1 = compute_result_cache_key("/Users/x", &stats, 1, 0, &with_pre);
        assert_ne!(k0, k1);
    }
}
