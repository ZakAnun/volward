use regex::Regex;
use serde::Deserialize;
use crate::model::{EntryCategory, RiskLevel, SourceType, StorageEntry};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Confidence { High, Medium }

#[derive(Debug, Clone)]
pub struct KnownSafeEntry {
    pub category: EntryCategory,
    pub confidence: Confidence,
    pub reason: String,
    pub deletable: bool,
}

impl KnownSafeEntry {
    pub fn into_storage_entry(
        self,
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
        StorageEntry {
            id: format!("{entry_id_seed}:{path}"),
            display_name: name,
            path_or_uri: path.to_string(),
            size_bytes,
            category: self.category,
            risk_level: match self.confidence {
                Confidence::High => RiskLevel::Low,
                Confidence::Medium => RiskLevel::Medium,
            },
            source_type: if is_dir { SourceType::Directory } else { SourceType::File },
            deletable: self.deletable,
            reason: self.reason,
        }
    }
}

#[derive(Deserialize)]
struct RawRule {
    pattern: String,
    category: String,
    deletable: bool,
    confidence: String,
    reason: String,
}

#[derive(Deserialize)]
struct RawFile {
    #[allow(dead_code)]
    version: u32,
    #[serde(default)]
    macos: Vec<RawRule>,
    #[serde(default)]
    windows: Vec<RawRule>,
    #[serde(default)]
    linux: Vec<RawRule>,
}

struct CompiledRule {
    re: Regex,
    category: EntryCategory,
    confidence: Confidence,
    reason: String,
    deletable: bool,
}

pub struct OsKnowledgeBase {
    rules: Vec<CompiledRule>,
}

impl OsKnowledgeBase {
    pub fn from_yaml(yaml: &str, platform: &str) -> Result<Self, serde_yaml::Error> {
        let file: RawFile = serde_yaml::from_str(yaml)?;
        let raw = match platform {
            "macos" => &file.macos,
            "windows" => &file.windows,
            "linux" => &file.linux,
            _ => return Ok(Self { rules: vec![] }),
        };
        let rules = raw.iter().filter_map(|r| {
            let re = Regex::new(&r.pattern).ok()?;
            let category = match r.category.as_str() {
                "BuildArtifact" => EntryCategory::BuildArtifact,
                "Cache" => EntryCategory::Cache,
                "Temp" => EntryCategory::Temp,
                _ => return None,
            };
            let confidence = if r.confidence == "high" {
                Confidence::High
            } else {
                Confidence::Medium
            };
            Some(CompiledRule {
                re,
                category,
                confidence,
                reason: r.reason.clone(),
                deletable: r.deletable,
            })
        }).collect();
        Ok(Self { rules })
    }

    pub fn for_current_platform() -> Self {
        let yaml = include_str!("../../../rules/os_knowledge.yaml");
        let platform = if cfg!(target_os = "macos") {
            "macos"
        } else if cfg!(target_os = "windows") {
            "windows"
        } else if cfg!(target_os = "linux") {
            "linux"
        } else {
            "other"
        };
        Self::from_yaml(yaml, platform).unwrap_or(Self { rules: vec![] })
    }

    /// Number of rules that actually compiled — a rule with a bad regex or an
    /// unknown category is silently dropped by `from_yaml`.
    pub fn rule_count(&self) -> usize {
        self.rules.len()
    }

    pub fn classify_path(&self, path: &str) -> Option<KnownSafeEntry> {
        self.rules.iter().find(|r| r.re.is_match(path)).map(|r| KnownSafeEntry {
            category: r.category,
            confidence: r.confidence,
            reason: r.reason.clone(),
            deletable: r.deletable,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::EntryCategory;

    const YAML: &str = include_str!("../../../rules/os_knowledge.yaml");

    #[test]
    fn node_modules_matches_all_platforms() {
        for platform in ["macos", "windows", "linux"] {
            let kb = OsKnowledgeBase::from_yaml(YAML, platform).unwrap();
            let entry = kb
                .classify_path("/Users/x/p/node_modules/x")
                .expect("node_modules should match");
            assert_eq!(entry.category, EntryCategory::BuildArtifact);
        }
    }

    #[test]
    fn documents_not_matched() {
        let kb = OsKnowledgeBase::from_yaml(YAML, "macos").unwrap();
        assert!(kb
            .classify_path("/Users/x/Documents/report.pdf")
            .is_none());
    }

    #[test]
    fn derived_data_matches_macos_not_linux() {
        let path = "/Users/x/Library/Developer/Xcode/DerivedData/App-abc";
        let macos = OsKnowledgeBase::from_yaml(YAML, "macos").unwrap();
        assert!(macos.classify_path(path).is_some());
        let linux = OsKnowledgeBase::from_yaml(YAML, "linux").unwrap();
        assert!(linux.classify_path(path).is_none());
    }

    #[test]
    fn every_macos_yaml_rule_compiles() {
        #[derive(serde::Deserialize)]
        struct CountFile {
            macos: Vec<serde_yaml::Value>,
        }
        let declared: CountFile = serde_yaml::from_str(YAML).unwrap();
        let kb = OsKnowledgeBase::from_yaml(YAML, "macos").unwrap();
        assert_eq!(
            kb.rule_count(),
            declared.macos.len(),
            "a macOS rule was dropped — check its regex and category"
        );
    }

    #[test]
    fn for_current_platform_does_not_panic() {
        let _ = OsKnowledgeBase::for_current_platform();
    }

    #[test]
    fn into_storage_entry_maps_confidence_to_risk() {
        let kb = OsKnowledgeBase::from_yaml(YAML, "macos").unwrap();
        let high = kb.classify_path("/Users/x/p/node_modules/x").unwrap();
        let e = high.into_storage_entry("/Users/x/p/node_modules/x", 10, false, "job");
        assert_eq!(e.category, EntryCategory::BuildArtifact);
        assert_eq!(e.risk_level, crate::model::RiskLevel::Low);
        assert!(e.deletable);

        let med = kb
            .classify_path("/Users/x/Library/Developer/Xcode/Archives/App")
            .unwrap();
        let e2 = med.into_storage_entry(
            "/Users/x/Library/Developer/Xcode/Archives/App",
            10,
            true,
            "job",
        );
        assert_eq!(e2.risk_level, crate::model::RiskLevel::Medium);
        assert!(e2.deletable);
    }
}
