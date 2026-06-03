use serde::Deserialize;

#[derive(Debug, Clone, Deserialize, PartialEq)]
pub struct DesktopRules {
    pub version: u32,
    pub protected_prefixes: Vec<String>,
    pub cache_patterns: Vec<String>,
    pub temp_patterns: Vec<String>,
    #[serde(default = "default_media_extensions")]
    pub media_extensions: Vec<String>,
}

fn default_media_extensions() -> Vec<String> {
    vec![
        ".jpg".into(),
        ".jpeg".into(),
        ".png".into(),
        ".gif".into(),
        ".mp4".into(),
        ".mov".into(),
        ".pdf".into(),
        ".dmg".into(),
    ]
}

impl DesktopRules {
    pub fn parse_yaml(yaml: &str) -> Result<Self, serde_yaml::Error> {
        serde_yaml::from_str(yaml)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_desktop_yaml_fixture() {
        let yaml = r#"
version: 1
protected_prefixes:
  - /System
cache_patterns:
  - "(?i)/Caches/"
temp_patterns:
  - "(?i)/tmp/"
"#;
        let rules = DesktopRules::parse_yaml(yaml).unwrap();
        assert_eq!(rules.version, 1);
        assert!(rules.protected_prefixes.contains(&"/System".to_string()));
        assert_eq!(rules.cache_patterns.len(), 1);
    }
}
