//! OS-specific application inventory used by the Applications capability.
//! Discovery is read-only: no uninstall commands are ever invoked and no
//! application data is mutated.

use std::collections::HashSet;
use std::path::{Path, PathBuf};

use volward_core::capability_registry::CapabilityProgressSink;
use volward_core::{
    allocated_file_size,
    group_items_by_direct_child, AnalysisConfidence, AnalysisItem, AnalysisOptions,
    AnalysisPreview, AnalysisSummary, Capability, CapabilityAnalysisError,
    CapabilityAnalysisResult, CapabilityAnalyzer, CapabilityLevel, DeletionPlan, Recommendation,
    SnapshotIndex, CAPABILITY_SCHEMA_VERSION,
};

pub const APPLICATION_ANALYZER_VERSION: &str = "applications-v1";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlatformKind {
    Macos,
    Windows,
    Linux,
    Unsupported,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ApplicationCandidate {
    pub app_name: String,
    pub app_path: String,
    pub bundle_id: Option<String>,
    /// Paths owned by the application (support data, containers, config).
    pub owned_paths: Vec<String>,
    /// `high` / `medium` / `low` ownership confidence.
    pub confidence: String,
    /// System-provided application (never a deletion target).
    pub system_app: bool,
    /// Read-only uninstall hint (URI or command) for guided cleanup.
    pub uninstall_hint: Option<String>,
}

/// Discovers installed applications for the current platform.
#[derive(Debug, Clone)]
pub struct ApplicationInventory {
    kind: PlatformKind,
    app_roots: Vec<PathBuf>,
    /// Home-relative support dirs used to derive owned data paths.
    support_roots: Vec<PathBuf>,
    home: Option<PathBuf>,
    capability_level: CapabilityLevel,
}

impl ApplicationInventory {
    pub fn new() -> Self {
        let home = dirs::home_dir();
        let (app_roots, support_roots, capability_level) = platform_layout(home.as_deref());
        let kind = platform_kind();
        Self {
            kind,
            app_roots,
            support_roots,
            home,
            capability_level,
        }
    }

    /// Test fixture constructor: explicit roots and capability level.
    pub fn with_roots(
        app_roots: Vec<PathBuf>,
        support_roots: Vec<PathBuf>,
        home: Option<PathBuf>,
        capability_level: CapabilityLevel,
    ) -> Self {
        let kind = if capability_level == CapabilityLevel::GuidedOnly {
            PlatformKind::Unsupported
        } else {
            PlatformKind::Macos
        };
        Self {
            kind,
            app_roots,
            support_roots,
            home,
            capability_level,
        }
    }

    /// Explicit platform kind for fixture tests on any host.
    pub fn with_kind(
        kind: PlatformKind,
        app_roots: Vec<PathBuf>,
        support_roots: Vec<PathBuf>,
        home: Option<PathBuf>,
    ) -> Self {
        let capability_level = match kind {
            PlatformKind::Unsupported => CapabilityLevel::GuidedOnly,
            _ => CapabilityLevel::FullPath,
        };
        Self {
            kind,
            app_roots,
            support_roots,
            home,
            capability_level,
        }
    }

    pub fn capability_level(&self) -> CapabilityLevel {
        self.capability_level
    }

    pub fn scan(&self) -> Vec<ApplicationCandidate> {
        let mut candidates = Vec::new();
        for root in &self.app_roots {
            match discovered_apps(root, self.kind) {
                Some(apps) => candidates.extend(apps),
                None => candidates.extend(heuristic_apps(root)),
            }
        }
        candidates.sort_by(|a, b| a.app_name.cmp(&b.app_name));
        candidates
    }

    /// Resolves the owned data paths for an app candidate, with conservative
    /// confidence: support/container dirs are medium, unknown matches are low.
    pub fn owned_paths_for(&self, app_name: &str, bundle_id: Option<&str>) -> Vec<(String, String)> {
        let mut owned = Vec::new();
        let mut seen = HashSet::new();
        for root in &self.support_roots {
            let candidates = [app_name, bundle_id.unwrap_or_default()]
                .into_iter()
                .filter(|name| !name.is_empty())
                .map(|name| root.join(name));
            for path in candidates {
                let path_str = path.to_string_lossy().to_string();
                if path.exists() && seen.insert(path_str.clone()) {
                    owned.push((path_str, "medium".to_string()));
                }
            }
        }
        if let Some(home) = &self.home {
            let shared = home.join("Library").join("Containers");
            if let Some(bundle_id) = bundle_id {
                if !bundle_id.is_empty() {
                    let container = shared.join(bundle_id);
                    let container_str = container.to_string_lossy().to_string();
                    if container.exists() && seen.insert(container_str.clone()) {
                        owned.push((container_str, "high".to_string()));
                    }
                }
            }
        }
        owned
    }

    pub fn is_system_path(&self, path: &str) -> bool {
        let normalized = path.replace('\\', "/").to_ascii_lowercase();
        normalized.starts_with("/system/")
            || normalized.starts_with("/usr/share/applications/")
            || normalized.starts_with("/system/applications/")
    }
}

impl Default for ApplicationInventory {
    fn default() -> Self {
        Self::new()
    }
}

/// Analyzer over [`ApplicationInventory`].
pub struct ApplicationAnalyzer {
    inventory: ApplicationInventory,
}

impl ApplicationAnalyzer {
    pub fn new(inventory: ApplicationInventory) -> Self {
        Self { inventory }
    }
}

impl CapabilityAnalyzer for ApplicationAnalyzer {
    fn capability(&self) -> Capability {
        Capability::Applications
    }

    fn analyze(
        &self,
        index: &SnapshotIndex,
        normalized_root: &str,
        _options: &AnalysisOptions,
        _progress: &dyn CapabilityProgressSink,
    ) -> Result<CapabilityAnalysisResult, CapabilityAnalysisError> {
        let candidates = self.inventory.scan();
        let mut items = Vec::new();
        let mut target_paths = Vec::new();
        let mut target_bytes = 0u64;
        let mut blocked_targets = Vec::new();
        let mut warnings = Vec::new();

        for candidate in candidates {
            if candidate.system_app || self.inventory.is_system_path(&candidate.app_path) {
                blocked_targets.push(candidate.app_path.clone());
                warnings.push(format!(
                    "{} is a system application; removal requires system uninstall",
                    candidate.app_name
                ));
                continue;
            }
            items.push(AnalysisItem {
                id: candidate.app_path.clone(),
                path: candidate.app_path.clone(),
                display_name: candidate.app_name.clone(),
                size_bytes: 0,
                is_directory: true,
                modified_at_ms: None,
                recommendation: Recommendation::Keep,
                confidence: AnalysisConfidence::High,
                reason: "application".to_string(),
                evidence: vec![
                    format!("confidence:{}", candidate.confidence),
                    candidate
                        .uninstall_hint
                        .map(|hint| format!("uninstall_hint:{hint}"))
                        .unwrap_or_default(),
                ]
                .into_iter()
                .filter(|e| !e.is_empty())
                .collect(),
                delete_target: None,
                preview: Some(AnalysisPreview {
                    kind: "directory".to_string(),
                    locatable: true,
                }),
            });
            for (path, confidence) in
                self.inventory
                    .owned_paths_for(&candidate.app_name, candidate.bundle_id.as_deref())
            {
                let size_bytes = dir_size(&PathBuf::from(&path));
                target_paths.push(path.clone());
                target_bytes += size_bytes;
                items.push(AnalysisItem {
                    id: path.clone(),
                    path: path.clone(),
                    display_name: file_name(&path),
                    size_bytes,
                    is_directory: true,
                    modified_at_ms: None,
                    recommendation: Recommendation::ReviewNeeded,
                    confidence: if confidence == "high" {
                        AnalysisConfidence::High
                    } else {
                        AnalysisConfidence::Medium
                    },
                    reason: "application_residual".to_string(),
                    evidence: vec![
                        format!("owned_by:{}", candidate.app_name),
                        format!("confidence:{confidence}"),
                    ],
                    delete_target: Some(path.clone()),
                    preview: Some(AnalysisPreview {
                        kind: "directory".to_string(),
                        locatable: true,
                    }),
                });
            }
        }

        warnings.dedup();
        let groups = group_items_by_direct_child(&items, normalized_root);
        let item_count = items.len() as u64;
        let total_bytes = items.iter().map(|item| item.size_bytes).sum();
        let kept_count = items
            .iter()
            .filter(|item| item.recommendation == Recommendation::Keep)
            .count() as u64;
        let review_count = items
            .iter()
            .filter(|item| item.recommendation == Recommendation::ReviewNeeded)
            .count() as u64;

        Ok(CapabilityAnalysisResult {
            schema_version: CAPABILITY_SCHEMA_VERSION,
            capability: Capability::Applications,
            snapshot_id: index.snapshot_id.clone(),
            root_path: normalized_root.to_string(),
            analyzer_version: APPLICATION_ANALYZER_VERSION.to_string(),
            generated_at_ms: index.scanned_at_ms,
            capability_level: self.inventory.capability_level(),
            summary: AnalysisSummary {
                item_count,
                total_bytes,
                safe_count: 0,
                review_count,
                kept_count,
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

fn dir_size(path: &Path) -> u64 {
    if path.is_file() {
        return path.metadata().map(|m| allocated_file_size(&m)).unwrap_or(0);
    }
    let mut total = 0u64;
    if let Ok(entries) = std::fs::read_dir(path) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                total = total.saturating_add(dir_size(&path));
            } else if let Ok(metadata) = path.metadata() {
                total = total.saturating_add(allocated_file_size(&metadata));
            }
        }
    }
    total
}

fn file_name(path: &str) -> String {
    path.rsplit('/')
        .next()
        .filter(|name| !name.is_empty())
        .unwrap_or(path)
        .to_string()
}

fn platform_layout(home: Option<&Path>) -> (Vec<PathBuf>, Vec<PathBuf>, CapabilityLevel) {
    #[cfg(target_os = "macos")]
    {
        let mut app_roots = vec![PathBuf::from("/Applications"), PathBuf::from("/System/Applications")];
        if let Some(home) = home {
            app_roots.push(home.join("Applications"));
        }
        let mut support_roots = vec![];
        if let Some(home) = home {
            support_roots.push(home.join("Library").join("Application Support"));
            support_roots.push(home.join("Library").join("Caches"));
        }
        (app_roots, support_roots, CapabilityLevel::FullPath)
    }
    #[cfg(target_os = "windows")]
    {
        let mut app_roots = vec![PathBuf::from("C:\\Program Files"), PathBuf::from("C:\\Program Files (x86)")];
        if let Some(home) = home {
            app_roots.push(home.join("AppData").join("Local").join("Programs"));
        }
        let mut support_roots = vec![];
        if let Some(home) = home {
            support_roots.push(home.join("AppData").join("Roaming"));
            support_roots.push(home.join("AppData").join("Local"));
        }
        (app_roots, support_roots, CapabilityLevel::FullPath)
    }
    #[cfg(target_os = "linux")]
    {
        let mut app_roots = vec![PathBuf::from("/usr/share/applications"), PathBuf::from("/usr/local/share/applications")];
        if let Some(home) = home {
            app_roots.push(home.join(".local").join("share").join("applications"));
        }
        let mut support_roots = vec![];
        if let Some(home) = home {
            support_roots.push(home.join(".config"));
            support_roots.push(home.join(".local").join("share"));
        }
        (app_roots, support_roots, CapabilityLevel::FullPath)
    }
    #[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
    {
        (vec![], vec![], CapabilityLevel::GuidedOnly)
    }
}

fn platform_kind() -> PlatformKind {
    #[cfg(target_os = "macos")]
    {
        PlatformKind::Macos
    }
    #[cfg(target_os = "windows")]
    {
        PlatformKind::Windows
    }
    #[cfg(target_os = "linux")]
    {
        PlatformKind::Linux
    }
    #[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
    {
        PlatformKind::Unsupported
    }
}

/// macOS `.app` bundles and Windows executable directories.
fn discovered_apps(root: &Path, kind: PlatformKind) -> Option<Vec<ApplicationCandidate>> {
    match kind {
        PlatformKind::Macos => {
        let mut apps = Vec::new();
        let entries = std::fs::read_dir(root).ok()?;
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().map(|ext| ext == "app").unwrap_or(false) && path.is_dir() {
                let app_name = path
                    .file_stem()
                    .map(|s| s.to_string_lossy().to_string())
                    .unwrap_or_default();
                let bundle_id = read_bundle_identifier(&path);
                let system_app = root.to_string_lossy().starts_with("/System");
                apps.push(ApplicationCandidate {
                    app_name,
                    app_path: path.to_string_lossy().to_string(),
                    bundle_id,
                    owned_paths: vec![],
                    confidence: "high".to_string(),
                    system_app,
                    uninstall_hint: Some(format!("open -R {}", path.to_string_lossy())),
                });
            }
        }
        Some(apps)
        }
        PlatformKind::Windows => {
        let mut apps = Vec::new();
        let entries = std::fs::read_dir(root).ok()?;
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                let app_name = path
                    .file_name()
                    .map(|s| s.to_string_lossy().to_string())
                    .unwrap_or_default();
                apps.push(ApplicationCandidate {
                    app_name,
                    app_path: path.to_string_lossy().to_string(),
                    bundle_id: None,
                    owned_paths: vec![],
                    confidence: "medium".to_string(),
                    system_app: false,
                    uninstall_hint: Some("ms-settings:appsfeatures".to_string()),
                });
            }
        }
        Some(apps)
        }
        PlatformKind::Linux => {
        let mut apps = Vec::new();
        let entries = std::fs::read_dir(root).ok()?;
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().map(|ext| ext == "desktop").unwrap_or(false) {
                if let Some(name) = read_desktop_name(&path) {
                    apps.push(ApplicationCandidate {
                        app_name: name,
                        app_path: path.to_string_lossy().to_string(),
                        bundle_id: None,
                        owned_paths: vec![],
                        confidence: "medium".to_string(),
                        system_app: root.to_string_lossy().starts_with("/usr"),
                        uninstall_hint: Some(format!("xdg-open {}", path.to_string_lossy())),
                    });
                }
            }
        }
        Some(apps)
        }
        PlatformKind::Unsupported => {
            let _ = root;
            None
        }
    }
}

/// Windows / unknown layouts: treat immediate subdirectories as apps.
fn heuristic_apps(root: &Path) -> Vec<ApplicationCandidate> {
    let mut apps = Vec::new();
    if let Ok(entries) = std::fs::read_dir(root) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                apps.push(ApplicationCandidate {
                    app_name: path
                        .file_name()
                        .map(|s| s.to_string_lossy().to_string())
                        .unwrap_or_default(),
                    app_path: path.to_string_lossy().to_string(),
                    bundle_id: None,
                    owned_paths: vec![],
                    confidence: "low".to_string(),
                    system_app: false,
                    uninstall_hint: None,
                });
            }
        }
    }
    apps
}

/// Reads CFBundleIdentifier from Info.plist via a tiny XML key scan.
fn read_bundle_identifier(app_path: &Path) -> Option<String> {
    let plist = app_path.join("Contents").join("Info.plist");
    let content = std::fs::read_to_string(plist).ok()?;
    let marker = "<key>CFBundleIdentifier</key>";
    let start = content.find(marker)? + marker.len();
    let rest = &content[start..];
    let value_start = rest.find("<string>")? + "<string>".len();
    let value_end = rest[value_start..].find("</string>")?;
    Some(rest[value_start..value_start + value_end].trim().to_string())
}

/// Reads the `Name=` field from a Linux .desktop file.
fn read_desktop_name(path: &Path) -> Option<String> {
    let content = std::fs::read_to_string(path).ok()?;
    content.lines().find_map(|line| {
        line.strip_prefix("Name=")
            .map(|name| name.trim().to_string())
    })
}

#[cfg(test)]
mod tests {
    use tempfile::TempDir;

    use super::*;

    #[test]
    fn macos_app_bundles_are_discovered_with_owned_paths() {
        let temp = TempDir::new().unwrap();
        let apps = temp.path().join("Applications");
        let support = temp.path().join("Library/Application Support");
        let app = apps.join("Example.app");
        std::fs::create_dir_all(app.join("Contents/MacOS")).unwrap();
        std::fs::write(
            app.join("Contents/Info.plist"),
            r#"<plist><dict><key>CFBundleIdentifier</key><string>com.example.app</string></dict></plist>"#,
        )
        .unwrap();
        std::fs::write(app.join("Contents/MacOS/Example"), b"binary").unwrap();
        let support_dir = support.join("Example");
        std::fs::create_dir_all(&support_dir).unwrap();

        let inventory = ApplicationInventory::with_roots(
            vec![apps.clone()],
            vec![support.clone()],
            Some(temp.path().to_path_buf()),
            CapabilityLevel::FullPath,
        );
        let candidates = inventory.scan();

        assert_eq!(candidates.len(), 1);
        let candidate = &candidates[0];
        assert_eq!(candidate.app_name, "Example");
        assert_eq!(candidate.confidence, "high");
        assert!(!candidate.system_app);
        assert!(candidate.uninstall_hint.as_deref().unwrap().starts_with("open -R"));
        let owned = inventory.owned_paths_for("Example", Some("com.example.app"));
        assert!(
            owned.iter().any(|(path, _)| path == &support_dir.to_string_lossy().to_string()),
            "support dir must be owned"
        );
    }

    #[test]
    fn linux_desktop_entries_are_discovered() {
        let temp = TempDir::new().unwrap();
        let apps = temp.path().join("applications");
        std::fs::create_dir_all(&apps).unwrap();
        std::fs::write(
            apps.join("example.desktop"),
            "[Desktop Entry]\nName=Example App\nExec=example\n",
        )
        .unwrap();

        let inventory = ApplicationInventory::with_kind(
            PlatformKind::Linux,
            vec![apps],
            vec![],
            Some(temp.path().to_path_buf()),
        );
        let candidates = inventory.scan();

        assert_eq!(candidates.len(), 1);
        assert_eq!(candidates[0].app_name, "Example App");
        assert_eq!(candidates[0].confidence, "medium");
    }

    #[test]
    fn system_apps_are_marked_and_shared_paths_blocked() {
        let inventory = ApplicationInventory::new();
        assert!(inventory.is_system_path("/System/Applications/System Settings.app"));
        assert!(inventory.is_system_path("/usr/share/applications/example.desktop"));
        assert!(!inventory.is_system_path("/Users/me/Applications/Example.app"));
    }

    #[test]
    fn unsupported_platform_falls_back_to_guided_only() {
        let inventory = ApplicationInventory::with_roots(
            vec![],
            vec![],
            None,
            CapabilityLevel::GuidedOnly,
        );
        assert_eq!(inventory.capability_level(), CapabilityLevel::GuidedOnly);
        assert!(inventory.scan().is_empty());
    }
}
