use regex::Regex;

use crate::model::{EntryCategory, RiskLevel, SourceType, StorageEntry};

pub struct Classifier {
    cache_re: Regex,
    temp_re: Regex,
    media_exts: Vec<&'static str>,
    protected_prefixes: Vec<String>,
}

impl Default for Classifier {
    fn default() -> Self {
        Self::new(Vec::new())
    }
}

impl Classifier {
    pub fn new(protected_prefixes: Vec<String>) -> Self {
        Self {
            cache_re: Regex::new(r"(?i)(/Caches/|/cache/|\.cache/)").expect("cache regex"),
            temp_re: Regex::new(r"(?i)(/tmp/|/temp/|\.tmp$)").expect("temp regex"),
            media_exts: vec![
                ".jpg", ".jpeg", ".png", ".gif", ".mp4", ".mov", ".pdf", ".dmg",
            ],
            protected_prefixes,
        }
    }

    pub fn classify_path(
        &self,
        path: &str,
        size_bytes: u64,
        is_dir: bool,
        entry_id_seed: &str,
    ) -> StorageEntry {
        let name = path
            .rsplit('/')
            .next()
            .filter(|s| !s.is_empty())
            .unwrap_or(path)
            .to_string();

        for prefix in &self.protected_prefixes {
            if path.starts_with(prefix) {
                return entry(
                    entry_id_seed,
                    path,
                    name,
                    size_bytes,
                    is_dir,
                    EntryCategory::System,
                    RiskLevel::High,
                    "protected_prefix",
                    false,
                );
            }
        }

        if self.cache_re.is_match(path) {
            return entry(
                entry_id_seed,
                path,
                name,
                size_bytes,
                is_dir,
                EntryCategory::Cache,
                RiskLevel::Low,
                "cache_segment",
                !is_dir,
            );
        }

        if self.temp_re.is_match(path) {
            return entry(
                entry_id_seed,
                path,
                name,
                size_bytes,
                is_dir,
                EntryCategory::Temp,
                RiskLevel::Low,
                "temp_segment",
                !is_dir,
            );
        }

        let lower = path.to_lowercase();
        if self.media_exts.iter().any(|ext| lower.ends_with(ext)) {
            return entry(
                entry_id_seed,
                path,
                name,
                size_bytes,
                is_dir,
                EntryCategory::Media,
                RiskLevel::High,
                "media_extension",
                false,
            );
        }

        entry(
            entry_id_seed,
            path,
            name,
            size_bytes,
            is_dir,
            EntryCategory::Unknown,
            RiskLevel::Medium,
            "unclassified",
            false,
        )
    }
}

fn entry(
    seed: &str,
    path: &str,
    name: String,
    size_bytes: u64,
    is_dir: bool,
    category: EntryCategory,
    risk_level: RiskLevel,
    reason: &str,
    deletable: bool,
) -> StorageEntry {
    StorageEntry {
        id: format!("{seed}:{}", path),
        display_name: name,
        path_or_uri: path.to_string(),
        size_bytes,
        category,
        risk_level,
        source_type: if is_dir {
            SourceType::Directory
        } else {
            SourceType::File
        },
        deletable,
        reason: reason.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn classifies_cache_path() {
        let c = Classifier::default();
        let e = c.classify_path("/Users/x/Library/Caches/foo", 10, false, "t");
        assert_eq!(e.category, EntryCategory::Cache);
        assert!(e.deletable);
    }

    #[test]
    fn protected_is_system() {
        let c = Classifier::new(vec!["/System".to_string()]);
        let e = c.classify_path("/System/Library", 10, true, "t");
        assert_eq!(e.category, EntryCategory::System);
        assert!(!e.deletable);
    }
}
