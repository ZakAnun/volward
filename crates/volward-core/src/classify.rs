use regex::Regex;

use crate::model::{EntryCategory, RiskLevel, SourceType, StorageEntry};
use crate::rules::DesktopRules;

pub struct Classifier {
    cache_res: Vec<Regex>,
    temp_res: Vec<Regex>,
    media_exts: Vec<String>,
    protected_prefixes: Vec<String>,
    /// True when YAML rules include patterns not covered by fast-path heuristics.
    needs_regex_fallback: bool,
}

impl Default for Classifier {
    fn default() -> Self {
        Self::new(Vec::new())
    }
}

impl Classifier {
    const DEFAULT_CACHE_PATTERNS: &'static [&'static str] = &[
        "(?i)/Caches/",
        "(?i)/cache/",
        "(?i)(/Caches/|/cache/|\\.cache/)",
    ];
    const DEFAULT_TEMP_PATTERNS: &'static [&'static str] =
        &["(?i)/tmp/", "(?i)/temp/", "(?i)(/tmp/|/temp/|\\.tmp$)"];

    fn patterns_need_regex_fallback(patterns: &[String], defaults: &[&str]) -> bool {
        patterns.iter().any(|p| !defaults.contains(&p.as_str()))
    }

    pub fn new(protected_prefixes: Vec<String>) -> Self {
        Self {
            cache_res: vec![Regex::new(r"(?i)(/Caches/|/cache/|\.cache/)").expect("cache regex")],
            temp_res: vec![Regex::new(r"(?i)(/tmp/|/temp/|\.tmp$)").expect("temp regex")],
            media_exts: vec![
                ".jpg".into(),
                ".jpeg".into(),
                ".png".into(),
                ".gif".into(),
                ".mp4".into(),
                ".mov".into(),
                ".pdf".into(),
                ".dmg".into(),
            ],
            protected_prefixes,
            needs_regex_fallback: false,
        }
    }

    pub fn from_rules(rules: &DesktopRules, extra_protected: &[String]) -> Self {
        let mut protected_prefixes: Vec<String> = extra_protected.to_vec();
        protected_prefixes.extend(rules.protected_prefixes.clone());

        let cache_res = rules
            .cache_patterns
            .iter()
            .map(|p| Regex::new(p).expect("cache pattern"))
            .collect();
        let temp_res = rules
            .temp_patterns
            .iter()
            .map(|p| Regex::new(p).expect("temp pattern"))
            .collect();

        let needs_regex_fallback =
            Self::patterns_need_regex_fallback(&rules.cache_patterns, Self::DEFAULT_CACHE_PATTERNS)
                || Self::patterns_need_regex_fallback(
                    &rules.temp_patterns,
                    Self::DEFAULT_TEMP_PATTERNS,
                );

        Self {
            cache_res,
            temp_res,
            media_exts: rules.media_extensions.clone(),
            protected_prefixes,
            needs_regex_fallback,
        }
    }

    /// Cheap pre-check before regex / StorageEntry allocation.
    fn path_might_match_rules(&self, path: &str) -> bool {
        for prefix in &self.protected_prefixes {
            if path.starts_with(prefix) {
                return true;
            }
        }
        if path
            .as_bytes()
            .windows(8)
            .any(|w| w.eq_ignore_ascii_case(b"/Caches/"))
            || path
                .as_bytes()
                .windows(7)
                .any(|w| w.eq_ignore_ascii_case(b"/cache/"))
            || path
                .as_bytes()
                .windows(7)
                .any(|w| w.eq_ignore_ascii_case(b".cache/"))
        {
            return true;
        }
        if path
            .as_bytes()
            .windows(5)
            .any(|w| w.eq_ignore_ascii_case(b"/tmp/"))
            || path
                .as_bytes()
                .windows(6)
                .any(|w| w.eq_ignore_ascii_case(b"/temp/"))
            || (path.len() >= 4 && path.as_bytes()[path.len() - 4..].eq_ignore_ascii_case(b".tmp"))
        {
            return true;
        }
        let lower = path.as_bytes();
        if self.media_exts.iter().any(|ext| {
            let ext_bytes = ext.as_bytes();
            lower.len() >= ext_bytes.len()
                && lower[lower.len() - ext_bytes.len()..].eq_ignore_ascii_case(ext_bytes)
        }) {
            return true;
        }
        self.needs_regex_fallback
    }

    pub fn classify_path(
        &self,
        path: &str,
        size_bytes: u64,
        is_dir: bool,
        entry_id_seed: &str,
    ) -> Option<StorageEntry> {
        if !self.path_might_match_rules(path) {
            return None;
        }

        let name = path
            .rsplit('/')
            .next()
            .filter(|s| !s.is_empty())
            .unwrap_or(path)
            .to_string();

        for prefix in &self.protected_prefixes {
            if path.starts_with(prefix) {
                return Some(entry(
                    entry_id_seed,
                    path,
                    name,
                    size_bytes,
                    is_dir,
                    EntryCategory::System,
                    RiskLevel::High,
                    "protected_prefix",
                    false,
                ));
            }
        }

        if self.cache_res.iter().any(|re| re.is_match(path)) {
            return Some(entry(
                entry_id_seed,
                path,
                name,
                size_bytes,
                is_dir,
                EntryCategory::Cache,
                RiskLevel::Low,
                "cache_segment",
                !is_dir,
            ));
        }

        if self.temp_res.iter().any(|re| re.is_match(path)) {
            return Some(entry(
                entry_id_seed,
                path,
                name,
                size_bytes,
                is_dir,
                EntryCategory::Temp,
                RiskLevel::Low,
                "temp_segment",
                !is_dir,
            ));
        }

        let lower = path.as_bytes();
        if self.media_exts.iter().any(|ext| {
            let ext_bytes = ext.as_bytes();
            lower.len() >= ext_bytes.len()
                && lower[lower.len() - ext_bytes.len()..].eq_ignore_ascii_case(ext_bytes)
        }) {
            return Some(entry(
                entry_id_seed,
                path,
                name,
                size_bytes,
                is_dir,
                EntryCategory::Media,
                RiskLevel::High,
                "media_extension",
                false,
            ));
        }

        None
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
        let e = c
            .classify_path("/Users/x/Library/Caches/foo", 10, false, "t")
            .unwrap();
        assert_eq!(e.category, EntryCategory::Cache);
        assert!(e.deletable);
    }

    #[test]
    fn unknown_path_not_classified() {
        let c = Classifier::default();
        assert!(c
            .classify_path("/Users/x/Documents/report.txt", 10, false, "t")
            .is_none());
    }

    #[test]
    fn protected_is_system() {
        let c = Classifier::new(vec!["/System".to_string()]);
        let e = c.classify_path("/System/Library", 10, true, "t").unwrap();
        assert_eq!(e.category, EntryCategory::System);
        assert!(!e.deletable);
    }

    #[test]
    fn fast_path_matches_full_classify_for_fixture_paths() {
        let c = Classifier::default();
        let paths = [
            "/Users/x/Library/Caches/foo",
            "/Users/x/Documents/a.txt",
            "/Users/x/Documents/report.txt",
            "/Users/x/Pictures/x.JPG",
            "/tmp/bar",
            "/Users/x/.cache/data",
        ];
        for p in paths {
            assert_eq!(
                c.path_might_match_rules(p),
                c.classify_path(p, 1, false, "t").is_some(),
                "path: {p}",
            );
        }
    }

    #[test]
    fn fast_path_skips_unknown_paths() {
        let c = Classifier::default();
        assert!(!c.path_might_match_rules("/Users/x/Documents/report.txt"));
    }

    #[test]
    fn fast_path_falls_back_when_custom_patterns_present() {
        let rules = DesktopRules::parse_yaml(
            r#"
version: 1
protected_prefixes: []
cache_patterns: ["(?i)/CustomCache/"]
temp_patterns: []
"#,
        )
        .unwrap();
        let c = Classifier::from_rules(&rules, &[]);
        assert!(c.path_might_match_rules("/Users/x/CustomCache/foo"));
        let e = c
            .classify_path("/Users/x/CustomCache/foo", 1, false, "t")
            .unwrap();
        assert_eq!(e.category, EntryCategory::Cache);
    }

    #[test]
    fn desktop_yaml_rules_use_fast_path_for_unknown() {
        let rules = DesktopRules::parse_yaml(include_str!("../../../rules/desktop.yaml")).unwrap();
        let c = Classifier::from_rules(&rules, &[]);
        assert!(!c.path_might_match_rules("/Users/x/Documents/report.txt"));
        assert!(c
            .classify_path("/Users/x/Documents/report.txt", 10, false, "t")
            .is_none());
    }

    #[test]
    fn from_rules_classifies_yaml_cache_pattern() {
        let rules = DesktopRules::parse_yaml(
            r#"
version: 1
protected_prefixes: []
cache_patterns: ["(?i)/Caches/"]
temp_patterns: []
"#,
        )
        .unwrap();
        let c = Classifier::from_rules(&rules, &[]);
        let e = c
            .classify_path("/Users/x/Library/Caches/foo", 10, false, "t")
            .unwrap();
        assert_eq!(e.category, EntryCategory::Cache);
    }
}
