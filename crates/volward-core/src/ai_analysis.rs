use serde::{Deserialize, Serialize};
use std::path::PathBuf;

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
    pub fn load(snapshot_id: &str) -> Option<Self> {
        let json = std::fs::read_to_string(analysis_path(snapshot_id)).ok()?;
        serde_json::from_str(&json).ok()
    }

    pub fn save(&self, snapshot_id: &str) -> Result<(), String> {
        let path = analysis_path(snapshot_id);
        std::fs::create_dir_all(path.parent().unwrap()).map_err(|e| e.to_string())?;
        let json = serde_json::to_string_pretty(self).map_err(|e| e.to_string())?;
        let tmp = path.with_extension("tmp");
        std::fs::write(&tmp, &json).map_err(|e| e.to_string())?;
        std::fs::rename(&tmp, &path).map_err(|e| {
            let _ = std::fs::remove_file(&tmp);
            e.to_string()
        })
    }

    pub fn exists(snapshot_id: &str) -> bool {
        analysis_path(snapshot_id).exists()
    }
}

fn analysis_path(snapshot_id: &str) -> PathBuf {
    crate::scan::default_data_dir()
        .join("ai_analysis")
        .join(format!("{snapshot_id}.json"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;
    use tempfile::TempDir;

    static ENV_LOCK: Mutex<()> = Mutex::new(());

    fn sample_result(snapshot_id: &str) -> AiAnalysisResult {
        AiAnalysisResult {
            schema_version: 1,
            snapshot_id: snapshot_id.to_string(),
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
        let mut result = sample_result(id);
        result.save(id).expect("first save");
        result.entries[0].verdict = "keep".into();
        result.credits_used = 2;
        result.save(id).expect("overwrite");

        let loaded = AiAnalysisResult::load(id).expect("load");
        assert_eq!(loaded.entries[0].verdict, "keep");
        assert_eq!(loaded.credits_used, 2);
        assert!(!analysis_path(id).with_extension("tmp").exists());
    }
}
