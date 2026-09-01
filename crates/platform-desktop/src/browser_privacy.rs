//! Browser privacy inventory for the four supported browsers (Safari,
//! Chrome, Edge, Firefox). Read-only: browser databases are never mutated
//! and password data is always excluded.

use std::path::{Path, PathBuf};

use volward_core::{
    group_items_by_direct_child, AnalysisConfidence, AnalysisItem, AnalysisOptions,
    AnalysisPreview, AnalysisSummary, Capability, CapabilityAnalysisError,
    CapabilityAnalysisResult, CapabilityAnalyzer, CapabilityLevel, DeletionPlan, Recommendation,
    SnapshotIndex, CAPABILITY_SCHEMA_VERSION,
};
use volward_core::capability_registry::CapabilityProgressSink;

pub const BROWSER_PRIVACY_ANALYZER_VERSION: &str = "browser_privacy-v1";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BrowserCategoryData {
    pub browser: String,
    /// cache / cookies / history / downloads / website_storage / databases /
    /// passwords
    pub category: String,
    pub path: String,
    pub estimated_bytes: u64,
    /// Database-level operations are guided-only — never direct targets.
    pub guided_only: bool,
    /// Passwords / autofill — excluded entirely.
    pub excluded: bool,
    /// A running-process lock file was found next to the profile.
    pub running: bool,
}

#[derive(Debug, Clone)]
pub struct BrowserPrivacyInventory {
    roots: Vec<PathBuf>,
    capability_level: CapabilityLevel,
}

impl BrowserPrivacyInventory {
    pub fn new() -> Self {
        Self {
            roots: browser_roots(),
            capability_level: platform_capability_level(),
        }
    }

    pub fn with_roots(roots: Vec<PathBuf>, capability_level: CapabilityLevel) -> Self {
        Self {
            roots,
            capability_level,
        }
    }

    pub fn capability_level(&self) -> CapabilityLevel {
        self.capability_level
    }

    pub fn scan_categories(&self) -> Vec<BrowserCategoryData> {
        let mut out = Vec::new();
        for root in &self.roots {
            let browser = root
                .file_name()
                .map(|name| name.to_string_lossy().to_string())
                .unwrap_or_default();
            out.extend(scan_browser_root(root, &browser));
        }
        out.sort_by(|a, b| a.browser.cmp(&b.browser).then(a.category.cmp(&b.category)));
        out
    }
}

impl Default for BrowserPrivacyInventory {
    fn default() -> Self {
        Self::new()
    }
}

fn browser_roots() -> Vec<PathBuf> {
    let mut roots = Vec::new();
    if let Some(home) = dirs::home_dir() {
        #[cfg(target_os = "macos")]
        {
            let support = home.join("Library").join("Application Support");
            roots.push(support.join("Google").join("Chrome"));
            roots.push(support.join("Microsoft Edge"));
            roots.push(support.join("Firefox"));
            roots.push(home.join("Library").join("Safari"));
        }
        #[cfg(target_os = "windows")]
        {
            let local = home.join("AppData").join("Local");
            let roaming = home.join("AppData").join("Roaming");
            roots.push(local.join("Google").join("Chrome").join("User Data"));
            roots.push(local.join("Microsoft").join("Edge").join("User Data"));
            roots.push(roaming.join("Mozilla").join("Firefox"));
        }
        #[cfg(target_os = "linux")]
        {
            roots.push(home.join(".config").join("google-chrome"));
            roots.push(home.join(".config").join("microsoft-edge"));
            roots.push(home.join(".config").join("firefox"));
        }
    }
    roots
}

fn platform_capability_level() -> CapabilityLevel {
    if cfg!(any(
        target_os = "macos",
        target_os = "windows",
        target_os = "linux"
    )) {
        CapabilityLevel::FullPath
    } else {
        CapabilityLevel::GuidedOnly
    }
}

fn scan_browser_root(root: &Path, browser: &str) -> Vec<BrowserCategoryData> {
    let mut out = Vec::new();
    let running = detect_running(root);
    let profiles = profile_dirs(root, browser);
    for profile in profiles {
        for (category, rel, guided_only, excluded) in known_category_locations(browser) {
            let path = profile.join(rel);
            if !path.exists() {
                continue;
            }
            out.push(BrowserCategoryData {
                browser: browser.to_string(),
                category: category.to_string(),
                path: path.to_string_lossy().to_string(),
                estimated_bytes: dir_size(&path),
                guided_only,
                excluded,
                running,
            });
        }
    }
    out
}

fn profile_dirs(root: &Path, browser: &str) -> Vec<PathBuf> {
    let mut profiles = Vec::new();
    let user_data = if browser.to_ascii_lowercase().contains("firefox") {
        root.join("Profiles")
    } else if browser.to_ascii_lowercase().contains("safari") {
        root.to_path_buf()
    } else {
        root.join("User Data")
    };
    if browser.to_ascii_lowercase().contains("safari") {
        if user_data.exists() {
            profiles.push(user_data);
        }
        return profiles;
    }
    if let Ok(entries) = std::fs::read_dir(&user_data) {
        for entry in entries.flatten() {
            let path = entry.path();
            let name = entry.file_name().to_string_lossy().to_string();
            let is_firefox_profile = browser.to_ascii_lowercase().contains("firefox");
            if path.is_dir()
                && (is_firefox_profile || name == "Default" || name.starts_with("Profile "))
            {
                profiles.push(path);
            }
        }
    }
    if profiles.is_empty() && user_data.exists() {
        profiles.push(user_data);
    }
    profiles
}

fn known_category_locations(browser: &str) -> Vec<(&'static str, &'static str, bool, bool)> {
    let lower = browser.to_ascii_lowercase();
    match lower.as_str() {
        "safari" => vec![
            ("cache", "Caches", false, false),
            ("cookies", "Cookies", false, false),
            ("history", "History", false, false),
            ("website_storage", "WebsiteData", false, false),
            ("databases", "Databases", true, false),
        ],
        "firefox" => vec![
            ("cache", "cache2", false, false),
            ("cookies", "cookies.sqlite", false, false),
            ("history", "places.sqlite", false, false),
            ("website_storage", "storage", false, false),
            ("databases", "storage", true, false),
            ("passwords", "logins.json", false, true),
        ],
        _ => vec![
            ("cache", "Cache", false, false),
            ("cache", "Code Cache", false, false),
            ("cache", "GPUCache", false, false),
            ("cookies", "Network/Cookies", false, false),
            ("history", "History", false, false),
            ("website_storage", "Local Storage", false, false),
            ("website_storage", "IndexedDB", false, false),
            ("website_storage", "Service Worker", false, false),
            ("databases", "Databases", true, false),
            ("passwords", "Login Data", false, true),
        ],
    }
}

fn detect_running(root: &Path) -> bool {
    let locks = [
        "SingletonLock",
        "parent.lock",
        "SingletonCookie",
        "lock",
    ];
    let search_roots = [root.to_path_buf(), root.join("User Data")];
    search_roots
        .iter()
        .any(|search_root| locks.iter().any(|lock| search_root.join(lock).exists()))
}

fn dir_size(path: &Path) -> u64 {
    if path.is_file() {
        return path.metadata().map(|m| m.len()).unwrap_or(0);
    }
    let mut total = 0u64;
    if let Ok(entries) = std::fs::read_dir(path) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                total = total.saturating_add(dir_size(&path));
            } else if let Ok(metadata) = path.metadata() {
                total = total.saturating_add(metadata.len());
            }
        }
    }
    total
}

/// Analyzer over [`BrowserPrivacyInventory`].
pub struct BrowserPrivacyAnalyzer {
    inventory: BrowserPrivacyInventory,
}

impl BrowserPrivacyAnalyzer {
    pub fn new(inventory: BrowserPrivacyInventory) -> Self {
        Self { inventory }
    }
}

impl CapabilityAnalyzer for BrowserPrivacyAnalyzer {
    fn capability(&self) -> Capability {
        Capability::BrowserPrivacy
    }

    fn analyze(
        &self,
        index: &SnapshotIndex,
        normalized_root: &str,
        _options: &AnalysisOptions,
        _progress: &dyn CapabilityProgressSink,
    ) -> Result<CapabilityAnalysisResult, CapabilityAnalysisError> {
        let data = self.inventory.scan_categories();
        let mut items = Vec::new();
        let mut target_paths = Vec::new();
        let mut target_bytes = 0u64;
        let mut blocked_targets = Vec::new();
        let mut warnings = Vec::new();

        for entry in data {
            if entry.excluded {
                blocked_targets.push(entry.path.clone());
                continue;
            }
            let is_known_dir_target = known_dir_target(&entry.path);
            let deletable = !entry.guided_only && is_known_dir_target;
            if deletable {
                target_paths.push(entry.path.clone());
                target_bytes += entry.estimated_bytes;
            }
            let mut evidence = vec![
                format!("category:{}", entry.category),
                format!("estimated_bytes:{}", entry.estimated_bytes),
            ];
            if entry.guided_only {
                evidence.push("guided_only".to_string());
            }
            if entry.running {
                evidence.push("browser_running".to_string());
                warnings.push(format!(
                    "{} is running; browser data changes may be in flight",
                    entry.browser
                ));
            }
            items.push(AnalysisItem {
                id: entry.path.clone(),
                path: entry.path.clone(),
                display_name: file_name(&entry.path),
                size_bytes: entry.estimated_bytes,
                is_directory: true,
                modified_at_ms: None,
                recommendation: Recommendation::ReviewNeeded,
                confidence: AnalysisConfidence::Medium,
                reason: format!("browser:{}", entry.category),
                evidence,
                delete_target: if deletable {
                    Some(entry.path.clone())
                } else {
                    None
                },
                preview: Some(AnalysisPreview {
                    kind: "directory".to_string(),
                    locatable: true,
                }),
            });
        }

        warnings.dedup();
        let groups = group_items_by_direct_child(&items, normalized_root);
        let item_count = items.len() as u64;
        let total_bytes = items.iter().map(|item| item.size_bytes).sum();
        Ok(CapabilityAnalysisResult {
            schema_version: CAPABILITY_SCHEMA_VERSION,
            capability: Capability::BrowserPrivacy,
            snapshot_id: index.snapshot_id.clone(),
            root_path: normalized_root.to_string(),
            analyzer_version: BROWSER_PRIVACY_ANALYZER_VERSION.to_string(),
            generated_at_ms: index.scanned_at_ms,
            capability_level: self.inventory.capability_level(),
            summary: AnalysisSummary {
                item_count,
                total_bytes,
                safe_count: 0,
                review_count: item_count,
                kept_count: 0,
                truncated: false,
            },
            groups,
            next_cursor: None,
            deletion_plan: DeletionPlan {
                snapshot_id: index.snapshot_id.clone(),
                target_count: target_paths.len() as u64,
                target_bytes,
                targets: target_paths,
                blocked_targets,
                requires_confirmation: true,
            },
            warnings,
        })
    }
}

/// Only explicitly browser-managed cache/storage directories may be targeted
/// as whole directories; everything else stays review-only.
fn known_dir_target(path: &str) -> bool {
    let name = file_name(path).to_ascii_lowercase();
    matches!(
        name.as_str(),
        "cache"
            | "cache2"
            | "code cache"
            | "gpucache"
            | "cacheddata"
            | "local storage"
            | "indexeddb"
            | "service worker"
            | "storage"
    )
}

fn file_name(path: &str) -> String {
    path.rsplit('/')
        .next()
        .filter(|name| !name.is_empty())
        .unwrap_or(path)
        .to_string()
}

#[cfg(test)]
mod tests {
    use tempfile::TempDir;

    use super::*;
    use volward_core::NoopProgressSink;

    fn write(temp: &TempDir, relative: &str, bytes: &[u8]) -> PathBuf {
        let path = temp.path().join(relative);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, bytes).unwrap();
        path
    }

    fn index(root: &str) -> SnapshotIndex {
        let builder = volward_core::SnapshotIndexBuilder::new(root);
        builder.finish(
            "snapshot-1".to_string(),
            1,
            1,
            "Done".to_string(),
            volward_core::ScanStats::default(),
        )
    }

    #[test]
    fn chrome_profile_reports_categories_bytes_and_running_lock() {
        let temp = TempDir::new().unwrap();
        write(&temp, "Google/Chrome/User Data/Default/Cache/data_0", &[1u8; 8]);
        write(&temp, "Google/Chrome/User Data/Default/History", b"h");
        write(&temp, "Google/Chrome/User Data/Default/Login Data", b"pw");
        write(&temp, "Google/Chrome/User Data/SingletonLock", b"");

        let inventory = BrowserPrivacyInventory::with_roots(
            vec![temp.path().join("Google/Chrome")],
            CapabilityLevel::FullPath,
        );
        let data = inventory.scan_categories();

        let cache = data.iter().find(|d| d.category == "cache").unwrap();
        assert_eq!(cache.estimated_bytes, 8);
        assert!(cache.running);
        let passwords = data.iter().find(|d| d.category == "passwords").unwrap();
        assert!(passwords.excluded);

        let root = temp.path().to_string_lossy().to_string();
        let result = BrowserPrivacyAnalyzer::new(inventory)
            .analyze(&index(&root), &root, &AnalysisOptions::default(), &NoopProgressSink)
            .expect("browser analysis");
        assert_eq!(result.summary.item_count, 2);
        assert_eq!(result.deletion_plan.target_count, 1);
        assert_eq!(result.deletion_plan.blocked_targets.len(), 1);
        assert!(result.warnings.iter().any(|w| w.contains("running")));
        assert!(result.capability_level == CapabilityLevel::FullPath);
    }

    #[test]
    fn firefox_passwords_and_databases_are_not_targets() {
        let temp = TempDir::new().unwrap();
        write(&temp, "Firefox/Profiles/abc.default/logins.json", b"{}");
        write(&temp, "Firefox/Profiles/abc.default/cookies.sqlite", b"db");
        write(&temp, "Firefox/Profiles/abc.default/storage/foo", b"data");

        let inventory = BrowserPrivacyInventory::with_roots(
            vec![temp.path().join("Firefox")],
            CapabilityLevel::FullPath,
        );
        let data = inventory.scan_categories();
        assert!(data.iter().any(|d| d.category == "passwords" && d.excluded));
        assert!(data.iter().any(|d| d.category == "databases" && d.guided_only));
        assert!(data.iter().any(|d| d.category == "cookies"));
    }

    #[test]
    fn unsupported_platform_falls_back_to_guided_only() {
        let inventory =
            BrowserPrivacyInventory::with_roots(vec![], CapabilityLevel::GuidedOnly);
        assert_eq!(inventory.capability_level(), CapabilityLevel::GuidedOnly);
        assert!(inventory.scan_categories().is_empty());
    }
}
