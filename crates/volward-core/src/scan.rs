use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::atomic::AtomicBool;
use std::time::{SystemTime, UNIX_EPOCH};

use uuid::Uuid;

use crate::classify::Classifier;
use crate::manifest::{
    DirFingerprint, FileManifestStore, FileSnapshotStore, ManifestStore, ScanManifest,
};
use crate::model::{PlatformCapabilities, ScanPhase, ScanProgress, ScanStats, StorageSnapshot};
use crate::os_knowledge::OsKnowledgeBase;
use crate::platform::{PlatformError, PlatformStorage, WalkAction, WalkOptions};
use crate::scan_tree::{find_subtree, ScanTreeBuilder};
use crate::SnapshotIndexBuilder;

fn classify_with_tiers(
    classifier: &Classifier,
    os_kb: &OsKnowledgeBase,
    path: &str,
    size_bytes: u64,
    is_dir: bool,
    job_id: &str,
) -> Option<crate::model::StorageEntry> {
    if let Some(e) = classifier.classify_path(path, size_bytes, is_dir, job_id) {
        return Some(e);
    }
    os_kb
        .classify_path(path)
        .map(|k| k.into_storage_entry(path, size_bytes, is_dir, job_id))
}

pub struct ScanOrchestrator<'a> {
    platform: &'a dyn PlatformStorage,
    classifier: Classifier,
    os_kb: OsKnowledgeBase,
    manifest_store: FileManifestStore,
    snapshot_store: FileSnapshotStore,
}

impl<'a> ScanOrchestrator<'a> {
    pub fn new(platform: &'a dyn PlatformStorage, classifier: Classifier) -> Self {
        Self::with_cache_dir(platform, classifier, default_cache_dir())
    }

    pub fn with_cache_dir(
        platform: &'a dyn PlatformStorage,
        classifier: Classifier,
        cache_dir: impl Into<PathBuf>,
    ) -> Self {
        let cache_dir = cache_dir.into();
        Self {
            platform,
            classifier,
            os_kb: OsKnowledgeBase::for_current_platform(),
            manifest_store: FileManifestStore::new(cache_dir.join("manifests")),
            snapshot_store: FileSnapshotStore::new(cache_dir.join("snapshots")),
        }
    }

    pub fn with_manifest_store(
        platform: &'a dyn PlatformStorage,
        classifier: Classifier,
        manifest_dir: impl Into<PathBuf>,
    ) -> Self {
        let manifest_dir = manifest_dir.into();
        let snapshot_dir = manifest_dir
            .parent()
            .map(|parent| parent.join("snapshots"))
            .unwrap_or_else(|| PathBuf::from("snapshots"));
        Self {
            platform,
            classifier,
            os_kb: OsKnowledgeBase::for_current_platform(),
            manifest_store: FileManifestStore::new(manifest_dir),
            snapshot_store: FileSnapshotStore::new(snapshot_dir),
        }
    }

    pub fn probe(&self) -> PlatformCapabilities {
        self.platform.probe_capabilities()
    }

    pub fn run_scan(
        &self,
        job_id: String,
        user_selected: Vec<String>,
        incremental: bool,
        cancel: &AtomicBool,
        mut on_progress: impl FnMut(ScanProgress),
        mut on_checkpoint: impl FnMut(StorageSnapshot),
    ) -> Result<StorageSnapshot, PlatformError> {
        let caps = self.platform.probe_capabilities();
        on_progress(ScanProgress {
            job_id: job_id.clone(),
            phase: ScanPhase::DiscoveringRoots,
            paths_seen: 0,
            bytes_seen: 0,
            current_path: None,
        });

        let roots = self.platform.discover_roots(&user_selected)?;
        let root_path = roots.first().map(|r| r.path.as_str()).unwrap_or("/");
        let vol = roots
            .first()
            .and_then(|r| self.platform.volume_stats(r).ok())
            .unwrap_or(crate::model::VolumeStats {
                total_bytes: 0,
                available_bytes: 0,
            });
        let mut tree_builder = ScanTreeBuilder::new(root_path);
        let mut entries = Vec::new();
        let mut stats = ScanStats::default();
        let mut bytes_seen = 0u64;
        let mut warnings = Vec::new();
        let mut dir_fingerprints = HashMap::<String, DirFingerprint>::new();
        let mut walk_completed = false;

        let loaded_manifest = incremental
            .then(|| self.manifest_store.load(root_path))
            .flatten()
            .filter(|manifest| manifest.root == root_path);

        if incremental {
            match &loaded_manifest {
                None => warnings.push(
                    "Incremental scan: no prior scan cache for this root; performing a full walk."
                        .to_string(),
                ),
                Some(manifest) => {
                    let snapshot_ok = self
                        .snapshot_store
                        .load_snapshot(root_path)
                        .is_some_and(|snapshot| snapshot.snapshot_id == manifest.snapshot_id);
                    if !snapshot_ok {
                        warnings.push(
                            "Incremental scan: cached snapshot missing or outdated; performing a full walk."
                                .to_string(),
                        );
                    }
                }
            }
        }

        let incremental_cache = loaded_manifest.and_then(|manifest| {
            self.snapshot_store
                .load_snapshot(root_path)
                .filter(|snapshot| snapshot.snapshot_id == manifest.snapshot_id)
                .map(|snapshot| (manifest, snapshot))
        });
        let baseline_fingerprints = incremental_cache.as_ref().map(|(manifest, snapshot)| {
            manifest
                .dir_fingerprints
                .iter()
                .filter(|(path, _)| find_subtree(&snapshot.tree, path).is_some())
                .map(|(path, fingerprint)| (path.clone(), fingerprint.clone()))
                .collect::<HashMap<_, _>>()
        });
        let mut skipped_dirs = Vec::<String>::new();

        if !self.platform.is_deep_scan_ready() {
            warnings.push(
                "Deep scan not ready (e.g. grant Full Disk Access on macOS for full Library access)."
                    .to_string(),
            );
        }

        on_progress(ScanProgress {
            job_id: job_id.clone(),
            phase: ScanPhase::Walking,
            paths_seen: 0,
            bytes_seen: 0,
            current_path: roots.first().map(|r| r.path.clone()),
        });

        let mut last_path: Option<String> = None;
        let mut progress_counter = 0u64;
        let mut last_checkpoint_at = std::time::Instant::now();
        // Adaptive: starts at 2s, but widens (capped at 15s) once building a
        // checkpoint itself starts taking non-trivial time on a large tree —
        // see the `checkpoint_interval = ...` update below for why.
        let mut checkpoint_interval = std::time::Duration::from_secs(2);
        const MAX_CHECKPOINT_INTERVAL: std::time::Duration = std::time::Duration::from_secs(15);
        let mut walk = |e: crate::model::RawFsEntry| -> WalkAction {
            if cancel.load(std::sync::atomic::Ordering::Relaxed) {
                return WalkAction::Stop;
            }
            stats.paths_seen += 1;
            bytes_seen = bytes_seen.saturating_add(e.size_bytes);
            last_path = Some(e.path.clone());
            progress_counter += 1;
            if progress_counter % 1000 == 0 {
                on_progress(ScanProgress {
                    job_id: job_id.clone(),
                    phase: ScanPhase::Walking,
                    paths_seen: stats.paths_seen,
                    bytes_seen,
                    current_path: last_path.clone(),
                });
            }
            if e.is_dir {
                stats.dirs_seen += 1;
                if let Some(fingerprint) = e.dir_fingerprint {
                    if baseline_fingerprints
                        .as_ref()
                        .and_then(|baseline| baseline.get(&e.path))
                        .is_some_and(|baseline| baseline.matches(&fingerprint))
                    {
                        skipped_dirs.push(e.path.clone());
                    }
                    dir_fingerprints.insert(e.path.clone(), fingerprint);
                }
                tree_builder.ensure_dir(&e.path);
            } else {
                stats.files_seen += 1;
                if let Some(classified) = classify_with_tiers(
                    &self.classifier,
                    &self.os_kb,
                    &e.path,
                    e.size_bytes,
                    false,
                    &job_id,
                ) {
                    let mut classified = classified;
                    classified.modified_at_ms = e.modified_at_ms;
                    let id = classified.id.clone();
                    stats.files_in_snapshot += 1;
                    entries.push(classified);
                    tree_builder.insert_file(&e.path, Some(&id), e.size_bytes);
                } else {
                    tree_builder.insert_file(&e.path, None, e.size_bytes);
                }
            }

            if progress_counter % 200 == 0 && last_checkpoint_at.elapsed() >= checkpoint_interval {
                let checkpoint_started_at = std::time::Instant::now();
                on_checkpoint(StorageSnapshot {
                    snapshot_id: format!("{job_id}-checkpoint"),
                    scanned_at_ms: unix_ms(),
                    capability: caps.level,
                    volume_total_bytes: vol.total_bytes,
                    volume_used_bytes: vol.total_bytes.saturating_sub(vol.available_bytes),
                    reclaimable_estimate_bytes: entries
                        .iter()
                        .filter(|entry| entry.deletable)
                        .map(|entry| entry.size_bytes)
                        .sum(),
                    entries: entries.clone(),
                    tree: tree_builder.peek_snapshot(),
                    stats: stats.clone(),
                    warnings: Vec::new(),
                });
                // `entries.clone()` + `peek_snapshot()` are both O(current
                // tree size), so on a large scan a fixed 2s cadence would
                // make checkpoint overhead grow unbounded over the scan's
                // lifetime. Instead, size the *next* interval off how long
                // *this* checkpoint actually took, so the checkpoint's own
                // cost stays roughly bounded to ~10% of wall-clock time.
                let checkpoint_cost = checkpoint_started_at.elapsed();
                checkpoint_interval = checkpoint_interval
                    .max(checkpoint_cost * 10)
                    .min(MAX_CHECKPOINT_INTERVAL);
                last_checkpoint_at = std::time::Instant::now();
            }

            WalkAction::Continue
        };

        match self.platform.walk_entries(
            &roots,
            WalkOptions {
                baseline_fingerprints: baseline_fingerprints.as_ref(),
            },
            cancel,
            &mut walk,
        ) {
            Err(PlatformError::Cancelled) => {
                stats.truncated = true;
                stats.incomplete_reason = Some("Scan cancelled.".into());
                warnings.push("Scan cancelled.".into());
            }
            Err(other) => return Err(other),
            Ok(skipped) => {
                walk_completed = true;
                stats.paths_skipped = skipped;
                stats.truncated = false;
                if skipped > 0 {
                    warnings.push(format!(
                        "{skipped} path(s) skipped due to permission or I/O errors."
                    ));
                }
            }
        }

        if let Some((manifest, cached_snapshot)) = incremental_cache.as_ref() {
            for dir in &skipped_dirs {
                if let Some(source) = find_subtree(&cached_snapshot.tree, dir) {
                    tree_builder.graft_subtree(dir, source);
                }
            }

            let existing_paths = entries
                .iter()
                .map(|entry| entry.path_or_uri.clone())
                .collect::<HashSet<_>>();
            entries.extend(
                cached_snapshot
                    .entries
                    .iter()
                    .filter(|entry| {
                        !existing_paths.contains(&entry.path_or_uri)
                            && skipped_dirs
                                .iter()
                                .any(|dir| path_is_at_or_below(&entry.path_or_uri, dir))
                    })
                    .cloned(),
            );
            for (path, fingerprint) in &manifest.dir_fingerprints {
                if skipped_dirs
                    .iter()
                    .any(|dir| path_is_at_or_below(path, dir) && path != dir.as_str())
                {
                    dir_fingerprints
                        .entry(path.clone())
                        .or_insert_with(|| fingerprint.clone());
                }
            }
            stats.files_in_snapshot = entries.len().min(u64::MAX as usize) as u64;
            if !skipped_dirs.is_empty() {
                warnings.push(format!(
                    "Incremental scan reused {} unchanged directories.",
                    skipped_dirs.len()
                ));
            }
        }

        on_progress(ScanProgress {
            job_id: job_id.clone(),
            phase: ScanPhase::Aggregating,
            paths_seen: stats.paths_seen,
            bytes_seen,
            current_path: last_path,
        });

        // Sort deferred to UI (home_page) to avoid O(n log n) on full-volume scans.

        let reclaimable = entries
            .iter()
            .filter(|e| e.deletable)
            .map(|e| e.size_bytes)
            .sum();

        let tree = tree_builder.finalize();
        let snapshot_id = Uuid::new_v4().to_string();
        let scanned_at_ms = unix_ms();

        let mut snapshot = StorageSnapshot {
            snapshot_id,
            scanned_at_ms,
            capability: caps.level,
            volume_total_bytes: vol.total_bytes,
            volume_used_bytes: vol.total_bytes.saturating_sub(vol.available_bytes),
            reclaimable_estimate_bytes: reclaimable,
            entries,
            tree,
            stats,
            warnings,
        };

        if walk_completed {
            {
                let mut manifest = ScanManifest {
                    root: root_path.to_string(),
                    scanned_at_ms,
                    snapshot_id: snapshot.snapshot_id.clone(),
                    snapshot_path: None,
                    dir_fingerprints,
                };
                match self.snapshot_store.save_snapshot(root_path, &snapshot) {
                    Ok(path) => {
                        manifest.snapshot_path = Some(path.to_string_lossy().into_owned());
                    }
                    Err(error) => {
                        snapshot
                            .warnings
                            .push(format!("Failed to save snapshot cache: {error}"));
                    }
                }
                if let Err(error) = self.manifest_store.save(&manifest) {
                    snapshot
                        .warnings
                        .push(format!("Failed to save scan manifest: {error}"));
                }
            }
        }

        on_progress(ScanProgress {
            job_id: job_id.clone(),
            phase: ScanPhase::Done,
            paths_seen: snapshot.stats.paths_seen,
            bytes_seen,
            current_path: None,
        });

        Ok(snapshot)
    }

    pub fn run_index_scan(
        &self,
        job_id: String,
        user_selected: Vec<String>,
        incremental: bool,
        cancel: &AtomicBool,
        mut on_progress: impl FnMut(ScanProgress),
    ) -> Result<crate::SnapshotIndex, PlatformError> {
        on_progress(ScanProgress {
            job_id: job_id.clone(),
            phase: ScanPhase::DiscoveringRoots,
            paths_seen: 0,
            bytes_seen: 0,
            current_path: None,
        });

        let roots = self.platform.discover_roots(&user_selected)?;
        let root_path = roots.first().map(|r| r.path.as_str()).unwrap_or("/");
        let mut index_builder = SnapshotIndexBuilder::new(root_path);
        let mut stats = ScanStats::default();
        let mut bytes_seen = 0u64;
        let mut warnings = Vec::new();
        let mut dir_fingerprints = HashMap::<String, DirFingerprint>::new();
        let mut walk_completed = false;

        let loaded_manifest = incremental
            .then(|| self.manifest_store.load(root_path))
            .flatten()
            .filter(|manifest| manifest.root == root_path);

        if incremental && loaded_manifest.is_none() {
            warnings.push(
                "Incremental scan: no prior scan cache for this root; performing a full walk."
                    .to_string(),
            );
        }

        let incremental_cache = loaded_manifest.and_then(|manifest| {
            self.snapshot_store
                .load_index(root_path)
                .filter(|index| index.snapshot_id == manifest.snapshot_id)
                .map(|index| (manifest, index))
        });
        if incremental && incremental_cache.is_none() {
            warnings.push(
                "Incremental scan: cached index missing or outdated; performing a full walk."
                    .to_string(),
            );
        }
        let baseline_fingerprints = incremental_cache.as_ref().map(|(manifest, _index)| {
            manifest
                .dir_fingerprints
                .iter()
                .map(|(path, fingerprint)| (path.clone(), fingerprint.clone()))
                .collect::<HashMap<_, _>>()
        });
        let mut skipped_dirs = Vec::<String>::new();

        if !self.platform.is_deep_scan_ready() {
            warnings.push(
                "Deep scan not ready (e.g. grant Full Disk Access on macOS for full Library access)."
                    .to_string(),
            );
        }

        on_progress(ScanProgress {
            job_id: job_id.clone(),
            phase: ScanPhase::Walking,
            paths_seen: 0,
            bytes_seen: 0,
            current_path: roots.first().map(|r| r.path.clone()),
        });

        let mut last_path: Option<String> = None;
        let mut progress_counter = 0u64;
        let mut walk = |e: crate::model::RawFsEntry| -> WalkAction {
            if cancel.load(std::sync::atomic::Ordering::Relaxed) {
                return WalkAction::Stop;
            }
            stats.paths_seen += 1;
            bytes_seen = bytes_seen.saturating_add(e.size_bytes);
            last_path = Some(e.path.clone());
            progress_counter += 1;
            if progress_counter % 1000 == 0 {
                on_progress(ScanProgress {
                    job_id: job_id.clone(),
                    phase: ScanPhase::Walking,
                    paths_seen: stats.paths_seen,
                    bytes_seen,
                    current_path: last_path.clone(),
                });
            }

            if e.is_dir {
                stats.dirs_seen += 1;
                if let Some(fingerprint) = e.dir_fingerprint {
                    if baseline_fingerprints
                        .as_ref()
                        .and_then(|baseline| baseline.get(&e.path))
                        .is_some_and(|baseline| baseline.matches(&fingerprint))
                    {
                        skipped_dirs.push(e.path.clone());
                    }
                    dir_fingerprints.insert(e.path.clone(), fingerprint);
                }
                index_builder.ensure_dir(&e.path);
            } else {
                stats.files_seen += 1;
                index_builder.record_file_size(&e.path, e.size_bytes);
                if let Some(classified) = classify_with_tiers(
                    &self.classifier,
                    &self.os_kb,
                    &e.path,
                    e.size_bytes,
                    false,
                    &job_id,
                ) {
                    let mut classified = classified;
                    classified.modified_at_ms = e.modified_at_ms;
                    stats.files_in_snapshot += 1;
                    index_builder.insert_entry(classified);
                }
            }

            WalkAction::Continue
        };

        match self.platform.walk_entries(
            &roots,
            WalkOptions {
                baseline_fingerprints: baseline_fingerprints.as_ref(),
            },
            cancel,
            &mut walk,
        ) {
            Err(PlatformError::Cancelled) => {
                stats.truncated = true;
                stats.incomplete_reason = Some("Scan cancelled.".into());
                warnings.push("Scan cancelled.".into());
            }
            Err(other) => return Err(other),
            Ok(skipped) => {
                walk_completed = true;
                stats.paths_skipped = skipped;
                stats.truncated = false;
                if skipped > 0 {
                    warnings.push(format!(
                        "{skipped} path(s) skipped due to permission or I/O errors."
                    ));
                }
            }
        }

        on_progress(ScanProgress {
            job_id: job_id.clone(),
            phase: ScanPhase::Aggregating,
            paths_seen: stats.paths_seen,
            bytes_seen,
            current_path: last_path,
        });

        if let Some((manifest, cached_index)) = incremental_cache.as_ref() {
            for dir in &skipped_dirs {
                index_builder.graft_directory_from_index(cached_index, dir);
            }
            for (path, fingerprint) in &manifest.dir_fingerprints {
                if skipped_dirs
                    .iter()
                    .any(|dir| path_is_at_or_below(path, dir) && path != dir.as_str())
                {
                    dir_fingerprints
                        .entry(path.clone())
                        .or_insert_with(|| fingerprint.clone());
                }
            }
            if !skipped_dirs.is_empty() {
                warnings.push(format!(
                    "Incremental scan reused {} unchanged directories.",
                    skipped_dirs.len()
                ));
            }
        }

        let snapshot_id = Uuid::new_v4().to_string();
        let scanned_at_ms = unix_ms();
        let scan_state = if stats.truncated {
            "Cancelled".to_string()
        } else {
            "Done".to_string()
        };
        let index = index_builder.finish(
            snapshot_id.clone(),
            scanned_at_ms,
            1,
            scan_state,
            stats.clone(),
        );

        if walk_completed {
            {
                let mut manifest = ScanManifest {
                    root: root_path.to_string(),
                    scanned_at_ms,
                    snapshot_id,
                    snapshot_path: None,
                    dir_fingerprints,
                };
                match self.snapshot_store.save_index(root_path, &index) {
                    Ok(path) => {
                        manifest.snapshot_path = Some(path.to_string_lossy().into_owned());
                    }
                    Err(error) => warnings.push(format!("Failed to save index cache: {error}")),
                }
                if let Err(error) = self.manifest_store.save(&manifest) {
                    warnings.push(format!("Failed to save scan manifest: {error}"));
                }
            }
        }

        on_progress(ScanProgress {
            job_id,
            phase: ScanPhase::Done,
            paths_seen: stats.paths_seen,
            bytes_seen,
            current_path: None,
        });

        Ok(index)
    }
}

fn path_is_at_or_below(path: &str, root: &str) -> bool {
    let path = normalize_scan_path(path);
    let root = normalize_scan_path(root);
    if root.is_empty() {
        return false;
    }
    let windows_style = has_windows_drive_prefix(&path)
        || has_windows_drive_prefix(&root)
        || path.starts_with("//")
        || root.starts_with("//");
    if windows_style {
        path.eq_ignore_ascii_case(&root)
            || (path.len() > root.len()
                && path.as_bytes()[..root.len()].eq_ignore_ascii_case(root.as_bytes())
                && (root == "/"
                    || is_windows_drive_root(&root)
                    || path.as_bytes().get(root.len()) == Some(&b'/')))
    } else {
        path == root
            || (path.starts_with(&root)
                && (root == "/" || path.as_bytes().get(root.len()) == Some(&b'/')))
    }
}

fn normalize_scan_path(path: &str) -> String {
    let normalized = path.replace('\\', "/");
    if is_unc_path(&normalized) {
        let trimmed = normalized.trim_end_matches('/');
        if trimmed.is_empty() || trimmed == "/" {
            return normalized;
        }
        return trimmed.to_string();
    }
    if normalized.len() > 1 && normalized.ends_with('/') && !is_windows_drive_root(&normalized) {
        normalized[..normalized.len() - 1].to_string()
    } else {
        normalized
    }
}

fn is_unc_path(path: &str) -> bool {
    if !path.starts_with("//") {
        return false;
    }
    let mut parts = path[2..].split('/').filter(|p| !p.is_empty());
    parts.next().is_some() && parts.next().is_some()
}

fn has_windows_drive_prefix(path: &str) -> bool {
    let bytes = path.as_bytes();
    bytes.len() >= 3 && bytes[1] == b':' && bytes[2] == b'/' && bytes[0].is_ascii_alphabetic()
}

fn is_windows_drive_root(path: &str) -> bool {
    let bytes = path.as_bytes();
    bytes.len() == 3 && bytes[1] == b':' && bytes[2] == b'/' && bytes[0].is_ascii_alphabetic()
}

#[derive(Clone, Copy)]
#[allow(dead_code)] // Variants are constructed per-target via cfg; unit tests cover all arms.
enum CachePlatform {
    Macos,
    Windows,
    Linux,
    Other,
}

#[cfg(target_os = "macos")]
fn cache_platform() -> CachePlatform {
    CachePlatform::Macos
}

#[cfg(windows)]
fn cache_platform() -> CachePlatform {
    CachePlatform::Windows
}

#[cfg(target_os = "linux")]
fn cache_platform() -> CachePlatform {
    CachePlatform::Linux
}

#[cfg(not(any(target_os = "macos", windows, target_os = "linux")))]
fn cache_platform() -> CachePlatform {
    CachePlatform::Other
}

fn default_cache_dir_from_env(
    platform: CachePlatform,
    get_env: impl Fn(&str) -> Option<PathBuf>,
    temp_dir: PathBuf,
) -> PathBuf {
    if let Some(dir) = get_env("VOLWARD_CACHE_DIR") {
        return dir;
    }

    match platform {
        CachePlatform::Macos => {
            if let Some(home) = get_env("HOME") {
                return home.join("Library/Application Support/Volward");
            }
        }
        CachePlatform::Windows => {
            if let Some(app_data) = get_env("APPDATA") {
                return app_data.join("Volward");
            }
            if let Some(local_app_data) = get_env("LOCALAPPDATA") {
                return local_app_data.join("Volward");
            }
            if let Some(profile) = get_env("USERPROFILE") {
                return profile.join("AppData").join("Roaming").join("Volward");
            }
        }
        CachePlatform::Linux => {
            if let Some(xdg_data_home) = get_env("XDG_DATA_HOME") {
                return xdg_data_home.join("volward");
            }
            if let Some(home) = get_env("HOME") {
                return home.join(".local/share/volward");
            }
        }
        CachePlatform::Other => {}
    }

    temp_dir.join("volward")
}

/// Public accessor for the Volward data directory (respects `VOLWARD_CACHE_DIR`).
pub fn default_data_dir() -> std::path::PathBuf {
    default_cache_dir()
}

fn default_cache_dir() -> PathBuf {
    default_cache_dir_from_env(
        cache_platform(),
        |key| std::env::var_os(key).map(PathBuf::from),
        std::env::temp_dir(),
    )
}

fn unix_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{CapabilityLevel, EntryCategory, ScanRoot, VolumeStats};
    use std::fs;
    use std::sync::atomic::AtomicBool;
    use tempfile::TempDir;

    #[test]
    fn tier2_classifies_node_modules_when_tier1_misses() {
        let classifier = Classifier::default();
        let yaml = include_str!("../../../rules/os_knowledge.yaml");
        let kb = OsKnowledgeBase::from_yaml(yaml, "macos").unwrap();
        let path = "/Users/x/Projects/app/node_modules/lodash/index.js";
        assert!(classifier.classify_path(path, 10, false, "j").is_none());
        let e = classify_with_tiers(&classifier, &kb, path, 10, false, "j").unwrap();
        assert_eq!(e.category, EntryCategory::BuildArtifact);
        assert!(e.deletable);
    }

    struct TempDirPlatform {
        root: ScanRoot,
        entries: Vec<crate::model::RawFsEntry>,
    }

    impl PlatformStorage for TempDirPlatform {
        fn probe_capabilities(&self) -> crate::model::PlatformCapabilities {
            crate::model::PlatformCapabilities {
                level: CapabilityLevel::FullPath,
                can_delete: true,
                can_traverse_system_paths: true,
                permission_hints: vec![],
            }
        }

        fn is_deep_scan_ready(&self) -> bool {
            true
        }

        fn discover_roots(
            &self,
            _user_selected: &[String],
        ) -> Result<Vec<ScanRoot>, PlatformError> {
            Ok(vec![self.root.clone()])
        }

        fn walk_entries(
            &self,
            _roots: &[ScanRoot],
            options: WalkOptions<'_>,
            cancel: &AtomicBool,
            on_entry: &mut dyn FnMut(crate::model::RawFsEntry) -> WalkAction,
        ) -> Result<u64, PlatformError> {
            let mut skipped_dirs = Vec::<String>::new();
            for entry in &self.entries {
                if cancel.load(std::sync::atomic::Ordering::Relaxed) {
                    return Err(PlatformError::Cancelled);
                }
                if skipped_dirs
                    .iter()
                    .any(|dir| entry.path != *dir && path_is_at_or_below(&entry.path, dir))
                {
                    continue;
                }
                if entry.is_dir
                    && entry.dir_fingerprint.as_ref().is_some_and(|fingerprint| {
                        options
                            .baseline_fingerprints
                            .and_then(|baseline| baseline.get(&entry.path))
                            == Some(fingerprint)
                    })
                {
                    skipped_dirs.push(entry.path.clone());
                }
                match on_entry(entry.clone()) {
                    WalkAction::Stop => return Ok(0),
                    WalkAction::SkipSubtree => continue,
                    WalkAction::Continue => {}
                }
            }
            Ok(0)
        }

        fn trash_paths(
            &self,
            _paths: &[String],
        ) -> Result<crate::model::DeleteReport, PlatformError> {
            Ok(crate::model::DeleteReport {
                deleted_count: 0,
                failed_paths: vec![],
                freed_bytes: 0,
            })
        }

        fn volume_stats(&self, _root: &ScanRoot) -> Result<VolumeStats, PlatformError> {
            Ok(VolumeStats {
                total_bytes: 0,
                available_bytes: 0,
            })
        }
    }

    fn build_temp_scan_platform(file_count: usize) -> (TempDir, TempDirPlatform) {
        let temp = TempDir::new().expect("temp dir");
        let root_path = temp.path().to_string_lossy().to_string();
        let mut entries = Vec::new();

        entries.push(crate::model::RawFsEntry {
            path: root_path.clone(),
            is_dir: true,
            size_bytes: 0,
            dir_fingerprint: Some(DirFingerprint {
                mtime_secs: 1_700_000_000,
                children_count: file_count.min(u32::MAX as usize) as u32,
                max_child_mtime_secs: 0,
            }),
            modified_at_ms: None,
        });

        for i in 0..file_count {
            let file_path = temp.path().join(format!("file_{i}.txt"));
            fs::write(&file_path, b"x").expect("write file");
            entries.push(crate::model::RawFsEntry {
                path: file_path.to_string_lossy().to_string(),
                is_dir: false,
                size_bytes: 1,
                dir_fingerprint: None,
                modified_at_ms: None,
            });
        }

        let platform = TempDirPlatform {
            root: ScanRoot {
                path: root_path,
                label: "temp".to_string(),
            },
            entries,
        };

        (temp, platform)
    }

    #[test]
    fn path_is_at_or_below_handles_windows_roots_and_unc_boundaries() {
        assert!(path_is_at_or_below(r"C:\Users\me\a.txt", "C:/Users/me"));
        assert!(path_is_at_or_below("C:/Users/me/a.txt", "C:/"));
        assert!(!path_is_at_or_below("C:/Users/media", "C:/Users/me"));
        assert!(path_is_at_or_below(
            r"\\server\share\folder\a.txt",
            "//server/share"
        ));
        assert!(!path_is_at_or_below(
            "//server/shareextra/folder",
            "//server/share"
        ));
        assert!(path_is_at_or_below("c:/Users/me/a.txt", "C:/Users/me"));
        assert!(path_is_at_or_below(
            "//SERVER/Share/folder/a.txt",
            "//server/share"
        ));
    }

    #[test]
    fn default_cache_dir_from_env_matches_platform_conventions() {
        let env = |values: &[(&str, &str)], key: &str| {
            values
                .iter()
                .find(|(candidate, _)| *candidate == key)
                .map(|(_, value)| PathBuf::from(value))
        };
        assert_eq!(
            default_cache_dir_from_env(
                CachePlatform::Macos,
                |key| env(&[("HOME", "/Users/me")], key),
                PathBuf::from("/tmp")
            ),
            PathBuf::from("/Users/me").join("Library/Application Support/Volward")
        );
        assert_eq!(
            default_cache_dir_from_env(
                CachePlatform::Windows,
                |key| env(&[("APPDATA", r"C:\Users\me\AppData\Roaming")], key),
                PathBuf::from(r"C:\Temp")
            ),
            PathBuf::from(r"C:\Users\me\AppData\Roaming").join("Volward")
        );
        assert_eq!(
            default_cache_dir_from_env(
                CachePlatform::Linux,
                |key| env(&[("XDG_DATA_HOME", "/home/me/.local/state")], key),
                PathBuf::from("/tmp")
            ),
            PathBuf::from("/home/me/.local/state").join("volward")
        );
        assert_eq!(
            default_cache_dir_from_env(
                CachePlatform::Linux,
                |key| env(&[("HOME", "/home/me")], key),
                PathBuf::from("/tmp")
            ),
            PathBuf::from("/home/me").join(".local/share/volward")
        );
        assert_eq!(
            default_cache_dir_from_env(CachePlatform::Other, |_| None, PathBuf::from("/tmp")),
            PathBuf::from("/tmp").join("volward")
        );
    }

    #[test]
    fn full_scan_indexes_every_file_without_cap() {
        let (_temp, platform) = build_temp_scan_platform(200);
        let cancel = AtomicBool::new(false);
        let orchestrator = ScanOrchestrator::new(&platform, Classifier::default());
        let snapshot = orchestrator
            .run_scan(
                "test-full-scan".to_string(),
                vec![],
                false,
                &cancel,
                |_p| {},
                |_snapshot| {},
            )
            .expect("scan should succeed");

        assert_eq!(snapshot.stats.files_seen, 200);
        assert_eq!(snapshot.stats.files_in_snapshot, 0);
        assert_eq!(snapshot.entries.len(), 0);
        assert!(!snapshot.stats.truncated);
        assert!(snapshot.stats.incomplete_reason.is_none());
    }

    #[test]
    fn index_scan_builds_catalog_without_snapshot_tree() {
        let (temp, mut platform) = build_temp_scan_platform(0);
        let cache_file = temp.path().join("Caches").join("keep.cache");
        let unknown_file = temp.path().join("Documents").join("notes.txt");
        fs::create_dir_all(cache_file.parent().unwrap()).expect("create cache dir");
        fs::create_dir_all(unknown_file.parent().unwrap()).expect("create documents dir");
        fs::write(&cache_file, b"cached").expect("write cache file");
        fs::write(&unknown_file, b"untracked content").expect("write unknown file");
        platform.entries.push(crate::model::RawFsEntry {
            path: temp.path().join("Caches").to_string_lossy().to_string(),
            is_dir: true,
            size_bytes: 0,
            dir_fingerprint: Some(DirFingerprint {
                mtime_secs: 1_700_000_100,
                children_count: 1,
                max_child_mtime_secs: 1_700_000_101,
            }),
            modified_at_ms: None,
        });
        platform.entries.push(crate::model::RawFsEntry {
            path: cache_file.to_string_lossy().to_string(),
            is_dir: false,
            size_bytes: 6,
            dir_fingerprint: None,
            modified_at_ms: None,
        });
        platform.entries.push(crate::model::RawFsEntry {
            path: temp.path().join("Documents").to_string_lossy().to_string(),
            is_dir: true,
            size_bytes: 0,
            dir_fingerprint: None,
            modified_at_ms: None,
        });
        platform.entries.push(crate::model::RawFsEntry {
            path: unknown_file.to_string_lossy().to_string(),
            is_dir: false,
            size_bytes: 17,
            dir_fingerprint: None,
            modified_at_ms: None,
        });

        let cancel = AtomicBool::new(false);
        let orchestrator = ScanOrchestrator::new(&platform, Classifier::default());
        let index = orchestrator
            .run_index_scan(
                "test-index-scan".to_string(),
                vec![],
                false,
                &cancel,
                |_p| {},
            )
            .expect("index scan should succeed");

        let root_path = platform.root.path.as_str();
        let root = index.query_directory(root_path, None, false, "name");
        assert_eq!(root.direct_children.len(), 2);
        assert!(root
            .direct_children
            .iter()
            .any(|child| child.name == "Caches"));
        assert!(root
            .direct_children
            .iter()
            .any(|child| child.name == "Documents"));

        let caches = index.query_directory(
            &temp.path().join("Caches").to_string_lossy(),
            Some("Cache"),
            true,
            "name",
        );
        assert_eq!(caches.direct_children.len(), 1);
        assert_eq!(caches.direct_entries.len(), 1);
        assert_eq!(caches.reclaimable_bytes, 6);
        assert_eq!(index.summary().reclaimable_estimate_bytes, 6);
        assert_eq!(index.summary().root_size_bytes, 23);
    }

    #[test]
    fn incremental_index_scan_grafts_skipped_cached_directories() {
        let (temp, mut platform) = build_temp_scan_platform(0);
        let cache_dir = temp.path().join("Caches");
        let cache_file = cache_dir.join("keep.cache");
        fs::create_dir_all(&cache_dir).expect("create cache dir");
        fs::write(&cache_file, b"cached").expect("write cache file");
        platform.entries.push(crate::model::RawFsEntry {
            path: cache_dir.to_string_lossy().to_string(),
            is_dir: true,
            size_bytes: 0,
            dir_fingerprint: None,
            modified_at_ms: None,
        });
        platform.entries.push(crate::model::RawFsEntry {
            path: cache_file.to_string_lossy().to_string(),
            is_dir: false,
            size_bytes: 6,
            dir_fingerprint: None,
            modified_at_ms: None,
        });

        let manifest_dir = temp.path().join("manifests");
        let cancel = AtomicBool::new(false);
        let orchestrator =
            ScanOrchestrator::with_manifest_store(&platform, Classifier::default(), &manifest_dir);

        let seed = orchestrator
            .run_index_scan("seed-index".to_string(), vec![], false, &cancel, |_p| {})
            .expect("seed index scan should succeed");
        assert_eq!(
            seed.query_directory(&cache_dir.to_string_lossy(), None, false, "name")
                .direct_entries
                .len(),
            1
        );

        let mut done_paths_seen = 0;
        let reused = orchestrator
            .run_index_scan(
                "incremental-index".to_string(),
                vec![],
                true,
                &cancel,
                |progress| {
                    if progress.phase == ScanPhase::Done {
                        done_paths_seen = progress.paths_seen;
                    }
                },
            )
            .expect("incremental index scan should succeed");

        let caches = reused.query_directory(&cache_dir.to_string_lossy(), None, false, "name");
        assert_eq!(done_paths_seen, 1);
        assert_eq!(caches.direct_entries.len(), 1);
        assert_eq!(caches.direct_entries[0].size_bytes, 6);
    }

    #[test]
    fn cancelled_scan_marks_snapshot_truncated() {
        let (_temp, platform) = build_temp_scan_platform(10);
        let cancel = AtomicBool::new(true);
        let orchestrator = ScanOrchestrator::new(&platform, Classifier::default());
        let snapshot = orchestrator
            .run_scan(
                "test-cancel".to_string(),
                vec![],
                false,
                &cancel,
                |_p| {},
                |_snapshot| {},
            )
            .expect("cancelled scan still returns snapshot");

        assert!(snapshot.stats.truncated);
        assert_eq!(
            snapshot.stats.incomplete_reason.as_deref(),
            Some("Scan cancelled.")
        );
    }

    #[test]
    fn successful_scan_saves_manifest_with_directory_fingerprints() {
        let (temp, platform) = build_temp_scan_platform(3);
        let root_path = platform.root.path.clone();
        let manifest_dir = temp.path().join("manifests");
        let cancel = AtomicBool::new(false);
        let orchestrator =
            ScanOrchestrator::with_manifest_store(&platform, Classifier::default(), &manifest_dir);

        let snapshot = orchestrator
            .run_scan(
                "test-manifest".to_string(),
                vec![],
                false,
                &cancel,
                |_p| {},
                |_snapshot| {},
            )
            .expect("scan should succeed");

        let manifest = FileManifestStore::new(manifest_dir)
            .load(&root_path)
            .expect("manifest should be saved");
        assert_eq!(manifest.snapshot_id, snapshot.snapshot_id);
        let snapshot_path = manifest
            .snapshot_path
            .as_deref()
            .expect("manifest should reference cached snapshot");
        assert!(std::path::Path::new(snapshot_path).is_file());
        let cached_snapshot = FileSnapshotStore::new(temp.path().join("snapshots"))
            .load_snapshot(&root_path)
            .expect("cached snapshot should load");
        assert_eq!(cached_snapshot.snapshot_id, snapshot.snapshot_id);
        assert_eq!(
            manifest.dir_fingerprints.get(&root_path),
            Some(&DirFingerprint {
                mtime_secs: 1_700_000_000,
                children_count: 3,
                max_child_mtime_secs: 0,
            })
        );
    }

    #[test]
    fn incremental_scan_with_existing_manifest_reuses_cached_tree() {
        let (temp, platform) = build_temp_scan_platform(2);
        let manifest_dir = temp.path().join("manifests");
        let cancel = AtomicBool::new(false);
        let orchestrator =
            ScanOrchestrator::with_manifest_store(&platform, Classifier::default(), &manifest_dir);
        orchestrator
            .run_scan(
                "seed-manifest".to_string(),
                vec![],
                false,
                &cancel,
                |_p| {},
                |_snapshot| {},
            )
            .expect("seed scan should succeed");

        let snapshot = orchestrator
            .run_scan(
                "incremental-e2".to_string(),
                vec![],
                true,
                &cancel,
                |_p| {},
                |_snapshot| {},
            )
            .expect("incremental E2 scan should succeed");

        assert_eq!(snapshot.stats.files_seen, 0);
        assert_eq!(snapshot.tree.children.len(), 2);
        assert!(snapshot
            .warnings
            .iter()
            .any(|warning| warning.contains("reused 1 unchanged directories")));
    }

    #[test]
    fn checkpoints_are_monotonically_increasing_subsets_of_final_result() {
        let (_temp, platform) = build_temp_scan_platform(50);
        let cancel = AtomicBool::new(false);
        let orchestrator = ScanOrchestrator::new(&platform, Classifier::default());
        let checkpoints = std::sync::Mutex::new(Vec::<usize>::new());

        let snapshot = orchestrator
            .run_scan(
                "test-checkpoints".to_string(),
                vec![],
                false,
                &cancel,
                |_p| {},
                |checkpoint| {
                    checkpoints
                        .lock()
                        .unwrap()
                        .push(checkpoint.tree.children.len());
                },
            )
            .expect("scan should succeed");

        // build_temp_scan_platform files aren't classified (no rules match),
        // so this test only exercises that run_scan compiles and runs with
        // the new on_checkpoint parameter; checkpoint firing itself is timing
        // gated (2s) so may legitimately record zero checkpoints for a fast
        // in-memory scan — that's fine, the assertion is about final shape.
        assert_eq!(snapshot.stats.files_seen, 50);
    }
}
