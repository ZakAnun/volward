use std::collections::{HashMap, HashSet};
use std::fs::File;
use std::io::{BufWriter, Write};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use platform_desktop::{
    ApplicationAnalyzer, ApplicationInventory, BrowserPrivacyAnalyzer, BrowserPrivacyInventory,
    DesktopPlatform,
};
use volward_core::classify::Classifier;
use volward_core::delete::DeleteOrchestrator;
use volward_core::model::{
    DeleteReport, PlatformCapabilities, ScanProgress, ScanTreeNode, StorageSnapshot,
    TrashEmptyReport,
};
use volward_core::rules::DesktopRules;
use volward_core::scan::ScanOrchestrator;
use volward_core::PlatformStorage;
use volward_core::SnapshotCatalog;
use volward_core::SnapshotIndex;
use volward_core::{
    ai_aggregate_path_from_delete_target, apply_dir_verdict, build_ai_coverage_plan,
    coverage_group_resolution, coverage_local_verdict_page, coverage_plan_page,
    coverage_plan_summary, coverage_tail_page, coverage_tree_page, coverage_tree_summary,
    write_dir_verdict_jsonl,
    build_ai_tree_plan_from_coverage_cache,
    coverage_group_member_paths,
    expand_tree_drill_children_with_index, page_local_coverage_verdicts, CoverageFunnelContext, CoverageFunnelContextMap,
    DirectoryRole, UnclassifiedCoverageCache, UnclassifiedSubtreeIndex,
    AiCandidateBuilder,
    AiCoveragePlan, AiTreePlan, AnalysisOptions, Capability, CapabilityAnalysisError,
    CapabilityAnalysisPhase, CapabilityJobStore, CapabilityRegistry, CleanupCandidateAnalyzer,
    DuplicateFileAnalyzer, LargeFileAnalyzer, NoopProgressSink, OsKnowledgeBase,
    SimilarPhotoAnalyzer,
    DEFAULT_CANDIDATE_CAP,
};

use volward_index_pb::{decode_snapshot_index, schedule_json_index_migration};

use crate::pb_convert::decode_storage_snapshot_from_pb;
use crate::proto;

mod ai;
mod capability;
mod coverage;
mod delete;
mod index_access;
mod index_query;
mod scan;

struct LocalCoverageFunnelCache {
    snapshot_id: String,
    index_version: u64,
    funnel_map: Arc<CoverageFunnelContextMap>,
    classified: Arc<HashSet<String>>,
    /// Built lazily on the first local-verdict page and reused by later pages.
    base_ctx: Option<Arc<CoverageFunnelContext>>,
}

struct UnclassifiedSubtreeIndexCache {
    snapshot_id: String,
    index_version: u64,
    subtree_index: Arc<UnclassifiedSubtreeIndex>,
}

struct UnclassifiedCoverageCacheSlot {
    snapshot_id: String,
    index_version: u64,
    cache: Arc<UnclassifiedCoverageCache>,
}

const MAX_CONCURRENT_CAPABILITY_JOBS: usize = 4;

fn load_classifier(platform: &DesktopPlatform) -> Classifier {
    let path = std::env::var("VOLWARD_RULES_PATH")
        .ok()
        .map(PathBuf::from)
        .or_else(|| {
            let p = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../rules/desktop.yaml");
            p.exists().then_some(p)
        });

    if let Some(path) = path {
        if let Ok(yaml) = std::fs::read_to_string(&path) {
            if let Ok(rules) = DesktopRules::parse_yaml(&yaml) {
                return Classifier::from_rules(&rules, platform.protected_prefixes());
            }
        }
    }
    Classifier::new(platform.protected_prefixes().to_vec())
}

fn load_classifier_from_arc(platform: &Arc<DesktopPlatform>) -> Classifier {
    load_classifier(platform.as_ref())
}

pub struct VolwardEngine {
    platform: Arc<DesktopPlatform>,
    cancel: Arc<AtomicBool>,
    persist_pause: Arc<AtomicBool>,
    is_scanning: Arc<AtomicBool>,
    last_snapshot: Arc<Mutex<Option<StorageSnapshot>>>,
    /// Authoritative path-keyed index rebuilt whenever a new snapshot is set.
    /// Dart queries this via FFI instead of hydrating the full snapshot.
    /// `Arc` so readers take a cheap handle and release the lock immediately;
    /// cloning the index itself under the lock stalls UI-thread queries on large scans.
    last_index: Arc<Mutex<Option<Arc<SnapshotIndex>>>>,
    is_index_loading: Arc<AtomicBool>,
    last_index_load_error: Arc<Mutex<Option<String>>>,
    last_pause_error: Arc<Mutex<Option<String>>>,
    index_load_generation: Arc<std::sync::atomic::AtomicU64>,
    /// Monotonic version counter — incremented each time last_index is rebuilt.
    index_version: Arc<std::sync::atomic::AtomicU64>,
    last_progress: Arc<Mutex<Option<ScanProgress>>>,
    last_checkpoint: Arc<Mutex<Option<StorageSnapshot>>>,
    _scan_handle: Arc<Mutex<Option<std::thread::JoinHandle<()>>>>,
    is_ai_candidates_building: Arc<AtomicBool>,
    ai_candidates_json: Arc<Mutex<Option<String>>>,
    ai_candidates_spill_path: Arc<Mutex<Option<String>>>,
    ai_candidates_generation: Arc<std::sync::atomic::AtomicU64>,
    is_ai_coverage_plan_building: Arc<AtomicBool>,
    ai_coverage_plan_preview_json: Arc<Mutex<Option<String>>>,
    ai_coverage_plan_build_generation: Arc<std::sync::atomic::AtomicU64>,
    local_coverage_funnel_cache: Arc<Mutex<Option<LocalCoverageFunnelCache>>>,
    unclassified_subtree_index_cache: Arc<Mutex<Option<UnclassifiedSubtreeIndexCache>>>,
    unclassified_coverage_cache: Arc<Mutex<Option<UnclassifiedCoverageCacheSlot>>>,
    /// Per `(snapshot_id, index_version)` mutex so concurrent ensure only builds once.
    coverage_cache_build_flights: Arc<Mutex<HashMap<(String, u64), Arc<Mutex<()>>>>>,
    ai_coverage_plan: Arc<Mutex<Option<AiCoveragePlan>>>,
    ai_tree_coverage_plan: Arc<Mutex<Option<AiTreePlan>>>,
    capability_registry: Arc<Mutex<CapabilityRegistry>>,
    /// Async capability jobs keyed by job id; clone-safe interior mutability.
    capability_jobs: CapabilityJobStore,
}

impl Default for VolwardEngine {
    fn default() -> Self {
        Self::new()
    }
}

impl VolwardEngine {
    pub fn new() -> Self {
        volward_index_pb::ensure_registered();
        let platform = Arc::new(DesktopPlatform::new());
        let mut capability_registry = CapabilityRegistry::new();
        capability_registry.register(Arc::new(LargeFileAnalyzer));
        capability_registry.register(Arc::new(CleanupCandidateAnalyzer::new(load_classifier(
            platform.as_ref(),
        ))));
        capability_registry.register(Arc::new(DuplicateFileAnalyzer::new(
            platform.protected_prefixes().to_vec(),
        )));
        capability_registry.register(Arc::new(SimilarPhotoAnalyzer::new(
            platform.protected_prefixes().to_vec(),
        )));
        capability_registry.register(Arc::new(ApplicationAnalyzer::new(
            ApplicationInventory::new(),
        )));
        capability_registry.register(Arc::new(BrowserPrivacyAnalyzer::new(
            BrowserPrivacyInventory::new(),
        )));
        Self {
            platform,
            cancel: Arc::new(AtomicBool::new(false)),
            persist_pause: Arc::new(AtomicBool::new(false)),
            is_scanning: Arc::new(AtomicBool::new(false)),
            last_snapshot: Arc::new(Mutex::new(None)),
            last_index: Arc::new(Mutex::new(None)),
            is_index_loading: Arc::new(AtomicBool::new(false)),
            last_index_load_error: Arc::new(Mutex::new(None)),
            last_pause_error: Arc::new(Mutex::new(None)),
            index_load_generation: Arc::new(std::sync::atomic::AtomicU64::new(0)),
            index_version: Arc::new(std::sync::atomic::AtomicU64::new(0)),
            last_progress: Arc::new(Mutex::new(None)),
            last_checkpoint: Arc::new(Mutex::new(None)),
            _scan_handle: Arc::new(Mutex::new(None)),
            is_ai_candidates_building: Arc::new(AtomicBool::new(false)),
            ai_candidates_json: Arc::new(Mutex::new(None)),
            ai_candidates_spill_path: Arc::new(Mutex::new(None)),
            ai_candidates_generation: Arc::new(std::sync::atomic::AtomicU64::new(0)),
            is_ai_coverage_plan_building: Arc::new(AtomicBool::new(false)),
            ai_coverage_plan_preview_json: Arc::new(Mutex::new(None)),
            ai_coverage_plan_build_generation: Arc::new(std::sync::atomic::AtomicU64::new(0)),
            local_coverage_funnel_cache: Arc::new(Mutex::new(None)),
            unclassified_subtree_index_cache: Arc::new(Mutex::new(None)),
            unclassified_coverage_cache: Arc::new(Mutex::new(None)),
            coverage_cache_build_flights: Arc::new(Mutex::new(HashMap::new())),
            ai_coverage_plan: Arc::new(Mutex::new(None)),
            ai_tree_coverage_plan: Arc::new(Mutex::new(None)),
            capability_registry: Arc::new(Mutex::new(capability_registry)),
            capability_jobs: CapabilityJobStore::new(),
        }
    }

    /// Engine with a pre-registered capability analyzer set (tests / injection).
    pub fn with_capability_registry(registry: CapabilityRegistry) -> Self {
        let engine = Self::new();
        if let Ok(mut current) = engine.capability_registry.lock() {
            *current = registry;
        }
        engine
    }

    pub fn probe_capabilities(&self) -> PlatformCapabilities {
        self.platform.probe_capabilities()
    }

    pub fn is_deep_scan_ready(&self) -> bool {
        self.platform.is_deep_scan_ready()
    }

    pub fn open_permission_settings(&self) -> Result<(), String> {
        self.platform
            .open_permission_settings()
            .map_err(|e| e.to_string())
    }

    pub fn set_last_snapshot(&self, snapshot: StorageSnapshot) {
        self.clear_local_coverage_funnel_cache();
        // Rebuild the path-keyed index atomically alongside the snapshot so
        // Dart can query it immediately without a separate hydration call.
        let version = self.index_version.fetch_add(1, Ordering::Relaxed) + 1;
        let index = SnapshotIndex::from_snapshot_with_version(&snapshot, version);
        if let Ok(mut g) = self.last_index.lock() {
            *g = Some(Arc::new(index));
        }
        if let Ok(mut g) = self.last_snapshot.lock() {
            *g = Some(snapshot);
        }
    }

    pub fn set_last_index(&self, index: SnapshotIndex) {
        self.clear_local_coverage_funnel_cache();
        let version = self.index_version.fetch_add(1, Ordering::Relaxed) + 1;
        if let Ok(mut g) = self.last_index.lock() {
            *g = Some(Arc::new(index));
        }
        let _ = version;
    }

    /// Current catalog version — Dart uses this as `SnapshotQueryKey.version`
    /// so cache invalidation is aligned with the Rust index.
    pub fn index_version(&self) -> u64 {
        self.index_version.load(Ordering::Relaxed)
    }

    pub fn probe_capabilities_json(&self) -> String {
        serde_json::to_string(&self.probe_capabilities()).unwrap_or_else(|_| "{}".to_string())
    }

    pub fn get_last_snapshot_json(&self) -> Option<String> {
        self.get_last_snapshot()
            .and_then(|s| serde_json::to_string(&s).ok())
    }

    pub fn get_last_snapshot_catalog_json(&self) -> Option<String> {
        self.get_last_snapshot()
            .and_then(|s| serde_json::to_string(&SnapshotCatalog::from(&s)).ok())
    }

    pub fn get_last_progress_json(&self) -> Option<String> {
        self.get_last_progress()
            .and_then(|p| serde_json::to_string(&p).ok())
    }

    pub fn get_last_checkpoint(&self) -> Option<StorageSnapshot> {
        self.last_checkpoint.lock().ok().and_then(|g| g.clone())
    }

    /// Serializes the last checkpoint directly to `path`. Returns
    /// `error:no checkpoint` if the current scan hasn't produced one yet.
    pub fn write_last_checkpoint_to_path(&self, path: &str) -> Result<String, String> {
        let guard = self
            .last_checkpoint
            .lock()
            .map_err(|e| format!("lock checkpoint: {e}"))?;
        let snapshot = guard
            .as_ref()
            .ok_or_else(|| "error:no checkpoint".to_string())?;
        let file = File::create(path).map_err(|e| format!("error:create checkpoint: {e}"))?;
        let mut writer = BufWriter::new(file);
        serde_json::to_writer(&mut writer, snapshot)
            .map_err(|e| format!("error:serialize checkpoint: {e}"))?;
        writer
            .flush()
            .map_err(|e| format!("error:flush checkpoint: {e}"))?;
        Ok(snapshot.snapshot_id.clone())
    }

    /// Encodes the last checkpoint as protobuf and writes it atomically to
    /// `path` (temp file + rename), so a concurrent reader never observes a
    /// truncated file. Returns `error:no checkpoint` if none exists yet.
    pub fn write_last_checkpoint_to_path_pb(&self, path: &str) -> Result<String, String> {
        let guard = self
            .last_checkpoint
            .lock()
            .map_err(|e| format!("lock checkpoint: {e}"))?;
        let snapshot = guard
            .as_ref()
            .ok_or_else(|| "error:no checkpoint".to_string())?;
        let id = snapshot.snapshot_id.clone();
        write_snapshot_pb_atomic(snapshot, path)?;
        Ok(id)
    }

    /// Single-level, non-recursive directory listing (see
    /// `PlatformStorage::quick_list_dir`). Safe to call while a scan is
    /// running — it does not touch `is_scanning`/shared scan state.
    pub fn quick_list_dir_json(&self, path: &str) -> String {
        match self.platform.quick_list_dir(path) {
            Ok(entries) => serde_json::to_string(&entries).unwrap_or_else(|_| "[]".to_string()),
            Err(e) => serde_json::json!({ "error": e.to_string() }).to_string(),
        }
    }

    pub fn set_last_snapshot_json(&self, json: &str) -> Result<(), String> {
        let snapshot: StorageSnapshot =
            serde_json::from_str(json).map_err(|e| format!("invalid snapshot json: {e}"))?;
        self.set_last_snapshot(snapshot);
        Ok(())
    }

    /// Serializes the last snapshot directly to [path] without an intermediate Dart copy.
    /// Returns the snapshot_id on success, or `error:…` on failure.
    pub fn write_last_snapshot_to_path(&self, path: &str) -> Result<String, String> {
        let guard = self
            .last_snapshot
            .lock()
            .map_err(|e| format!("lock snapshot: {e}"))?;
        let snapshot = guard
            .as_ref()
            .ok_or_else(|| "error:no snapshot".to_string())?;
        let file = File::create(path).map_err(|e| format!("error:create snapshot: {e}"))?;
        let mut writer = BufWriter::new(file);
        serde_json::to_writer(&mut writer, snapshot)
            .map_err(|e| format!("error:serialize snapshot: {e}"))?;
        writer
            .flush()
            .map_err(|e| format!("error:flush snapshot: {e}"))?;
        Ok(snapshot.snapshot_id.clone())
    }

    pub fn write_last_snapshot_catalog_to_path(&self, path: &str) -> Result<String, String> {
        let guard = self
            .last_snapshot
            .lock()
            .map_err(|e| format!("lock snapshot: {e}"))?;
        let snapshot = guard
            .as_ref()
            .ok_or_else(|| "error:no snapshot".to_string())?;
        let catalog = SnapshotCatalog::from(snapshot);
        let file = File::create(path).map_err(|e| format!("error:create catalog: {e}"))?;
        let mut writer = BufWriter::new(file);
        serde_json::to_writer(&mut writer, &catalog)
            .map_err(|e| format!("error:serialize catalog: {e}"))?;
        writer
            .flush()
            .map_err(|e| format!("error:flush catalog: {e}"))?;
        Ok(catalog.snapshot_id)
    }

    pub fn load_snapshot_catalog_from_path(&self, path: &str) -> Result<String, String> {
        let json = std::fs::read_to_string(path).map_err(|e| format!("read catalog: {e}"))?;
        let catalog: SnapshotCatalog =
            serde_json::from_str(&json).map_err(|e| format!("invalid catalog json: {e}"))?;
        serde_json::to_string(&catalog).map_err(|e| format!("serialize catalog: {e}"))
    }

    /// Encodes the last snapshot as protobuf and writes it atomically to
    /// `path` (temp file + rename). Returns the snapshot_id on success.
    pub fn write_last_snapshot_to_path_pb(&self, path: &str) -> Result<String, String> {
        let guard = self
            .last_snapshot
            .lock()
            .map_err(|e| format!("lock snapshot: {e}"))?;
        let snapshot = guard
            .as_ref()
            .ok_or_else(|| "error:no snapshot".to_string())?;
        let id = snapshot.snapshot_id.clone();
        write_snapshot_pb_atomic(snapshot, path)?;
        Ok(id)
    }

    /// Loads snapshot from [path] into this engine (single parse, for delete operations).
    pub fn load_last_snapshot_from_path(&self, path: &str) -> Result<(), String> {
        if path.ends_with(".pb") {
            let bytes = std::fs::read(path).map_err(|e| format!("read snapshot pb: {e}"))?;
            let snapshot = decode_storage_snapshot_from_pb(&bytes)?;
            self.set_last_snapshot(snapshot);
            return Ok(());
        }
        let json = std::fs::read_to_string(path).map_err(|e| format!("read snapshot: {e}"))?;
        self.set_last_snapshot_json(&json)
    }

    /// Explicit clearing entry point for engine-local Coverage caches.
    /// Explicit index setters clear these before publishing. Asynchronous scan and
    /// load retain their existing publication order and cache-reader checks.
    /// This helper does not coordinate those jobs.
    pub(crate) fn clear_local_coverage_funnel_cache(&self) {
        if let Ok(mut guard) = self.local_coverage_funnel_cache.lock() {
            *guard = None;
        }
        if let Ok(mut guard) = self.unclassified_subtree_index_cache.lock() {
            *guard = None;
        }
        if let Ok(mut guard) = self.unclassified_coverage_cache.lock() {
            *guard = None;
        }
    }

    pub fn delete_entries_json(
        &self,
        snapshot_id: &str,
        entry_ids: Vec<String>,
        dry_run: bool,
    ) -> String {
        match self.delete_entries(snapshot_id, entry_ids, dry_run) {
            Ok(report) => serde_json::to_string(&report).unwrap_or_else(|_| "{}".to_string()),
            Err(e) => serde_json::json!({ "error": e }).to_string(),
        }
    }


}

/// Encodes `snapshot` as protobuf and writes it atomically to `path`.
///
/// Writes to a sibling temp file (`<path>.tmp.<id>`) then renames onto `path`.
/// `rename` is atomic on the same filesystem, so a concurrent reader sees
/// either the previous file or the fully-written new one — never a truncated
/// stream. This removes the read-while-writing race the JSON path has.
fn write_snapshot_pb_atomic(snapshot: &StorageSnapshot, path: &str) -> Result<String, String> {
    use prost::Message;

    let msg = proto::StorageSnapshot::from(snapshot);
    let bytes = msg.encode_to_vec();

    let tmp = format!("{path}.tmp.{}", snapshot.snapshot_id);
    {
        let file = File::create(&tmp).map_err(|e| format!("error:create pb tmp: {e}"))?;
        let mut writer = BufWriter::new(file);
        writer
            .write_all(&bytes)
            .map_err(|e| format!("error:write pb: {e}"))?;
        writer.flush().map_err(|e| format!("error:flush pb: {e}"))?;
    }
    std::fs::rename(&tmp, path).map_err(|e| {
        // Best-effort cleanup so a failed rename doesn't leak temp files.
        let _ = std::fs::remove_file(&tmp);
        format!("error:rename pb: {e}")
    })?;
    Ok(snapshot.snapshot_id.clone())
}

fn index_target_path_size(index: &SnapshotIndex, target: &str) -> Option<(String, u64)> {
    let target = normalize_facade_path(target);
    let parent = parent_path_of(&target)?;
    let query = index.query_directory(&parent, None, false, "name");
    query
        .direct_children
        .into_iter()
        .find(|node| facade_paths_equal(&node.path, &target))
        .map(|node| (node.path, node.size_bytes))
}

fn resolve_index_ai_aggregate_paths(
    index: &SnapshotIndex,
    target: &str,
) -> Result<Vec<(String, u64)>, String> {
    let parent = ai_aggregate_path_from_delete_target(target)
        .ok_or_else(|| "Invalid AI aggregate delete target".to_string())?;
    let kb = OsKnowledgeBase::for_current_platform();
    let classified = index.classified_paths();
    let files = index.unclassified_files();
    let indexed_prefixes = volward_core::indexed_local_exclusion_prefixes(index);
    let set = AiCandidateBuilder::from_unclassified_files(&files, &classified, &kb, &indexed_prefixes)
        .annotate_ai_cleanup_patterns()
        .aggregate_by_dir(20)
        .cap_top_n(DEFAULT_CANDIDATE_CAP)
        .build();
    let valid = set.candidates.iter().any(|candidate| {
        candidate.path == parent && candidate.delete_target.as_deref() == Some(target)
    });
    if !valid {
        return Err("AI aggregate candidate is no longer valid".to_string());
    }
    Ok(files
        .into_iter()
        .filter(|(path, _)| {
            parent_path_of(path)
                .as_deref()
                .is_some_and(|candidate_parent| facade_paths_equal(candidate_parent, parent))
                && !classified.contains(path)
                && kb.classify_path(path).is_none()
        })
        .collect())
}

fn resolve_snapshot_ai_aggregate_paths(
    snapshot: &StorageSnapshot,
    target: &str,
) -> Result<Vec<(String, u64)>, String> {
    let parent = ai_aggregate_path_from_delete_target(target)
        .ok_or_else(|| "Invalid AI aggregate delete target".to_string())?;
    let kb = OsKnowledgeBase::for_current_platform();
    let classified: std::collections::HashSet<String> = snapshot
        .entries
        .iter()
        .map(|entry| entry.path_or_uri.clone())
        .collect();
    let set = AiCandidateBuilder::from_tree(&snapshot.tree, &classified, &kb)
        .annotate_ai_cleanup_patterns()
        .aggregate_by_dir(20)
        .cap_top_n(DEFAULT_CANDIDATE_CAP)
        .build();
    let valid = set.candidates.iter().any(|candidate| {
        candidate.path == parent && candidate.delete_target.as_deref() == Some(target)
    });
    if !valid {
        return Err("AI aggregate candidate is no longer valid".to_string());
    }
    let node = find_tree_node(&snapshot.tree, parent)
        .ok_or_else(|| "AI aggregate directory is no longer present".to_string())?;
    Ok(node
        .children
        .iter()
        .filter(|child| {
            !child.is_dir
                && !classified.contains(&child.path)
                && kb.classify_path(&child.path).is_none()
        })
        .map(|child| (child.path.clone(), child.size_bytes))
        .collect())
}

fn snapshot_target_path_size(
    root: &ScanTreeNode,
    entries: &[volward_core::model::StorageEntry],
    target: &str,
) -> Option<(String, u64)> {
    if let Some(entry) = entries.iter().find(|entry| entry.id == target) {
        return Some((entry.path_or_uri.clone(), entry.size_bytes));
    }
    find_tree_node(root, target).map(|node| (node.path.clone(), node.size_bytes))
}

fn find_tree_node<'a>(node: &'a ScanTreeNode, target: &str) -> Option<&'a ScanTreeNode> {
    let target = normalize_facade_path(target);
    if facade_paths_equal(&normalize_facade_path(&node.path), &target) {
        return Some(node);
    }
    for child in &node.children {
        if let Some(found) = find_tree_node(child, &target) {
            return Some(found);
        }
    }
    None
}

fn parent_path_of(path: &str) -> Option<String> {
    let normalized = normalize_facade_path(path);
    if let Some(share) = unc_share_root(&normalized) {
        if share.eq_ignore_ascii_case(&normalized) {
            return Some(share);
        }
    }
    match normalized.rfind('/') {
        Some(2) if has_windows_drive_prefix(&normalized) => Some(normalized[..3].to_string()),
        Some(0) => Some("/".to_string()),
        Some(i) if i > 0 => Some(normalized[..i].to_string()),
        _ => {
            if is_windows_drive_root(&normalized) {
                Some(normalized)
            } else {
                None
            }
        }
    }
}

fn normalize_facade_path(path: &str) -> String {
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

fn unc_share_root(path: &str) -> Option<String> {
    if !is_unc_path(path) {
        return None;
    }
    let mut parts = path[2..].split('/').filter(|p| !p.is_empty());
    let server = parts.next()?;
    let share = parts.next()?;
    Some(format!("//{server}/{share}"))
}

fn facade_paths_equal(left: &str, right: &str) -> bool {
    let windows_style = has_windows_drive_prefix(left)
        || has_windows_drive_prefix(right)
        || left.starts_with("//")
        || right.starts_with("//");
    if windows_style {
        left.eq_ignore_ascii_case(right)
    } else {
        left == right
    }
}

fn has_windows_drive_prefix(path: &str) -> bool {
    let bytes = path.as_bytes();
    bytes.len() >= 3 && bytes[1] == b':' && bytes[2] == b'/' && bytes[0].is_ascii_alphabetic()
}

fn is_windows_drive_root(path: &str) -> bool {
    has_windows_drive_prefix(path) && path.len() == 3
}

fn parse_capability(value: &str) -> Option<Capability> {
    serde_json::from_str::<Capability>(&format!("\"{value}\"")).ok()
}

fn parse_capability_options(
    options_json: &str,
    capability: Capability,
    snapshot_id: &str,
) -> Result<AnalysisOptions, CapabilityAnalysisError> {
    serde_json::from_str::<AnalysisOptions>(options_json).map_err(|error| {
        CapabilityAnalysisError::for_request(
            "invalid_options",
            format!("options JSON: {error}"),
            capability,
            snapshot_id,
        )
    })
}

fn capability_error_json(error: &CapabilityAnalysisError) -> String {
    serde_json::json!({ "error": error }).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc::{self, Receiver, Sender};
    use volward_core::model::{
        CapabilityLevel, EntryCategory, RiskLevel, ScanStats, ScanTreeNode, SourceType,
        StorageEntry, StorageSnapshot,
    };
    use volward_core::{
        AnalysisOptions, AnalysisSummary, Capability, CapabilityAnalysisError,
        CapabilityAnalysisResult, CapabilityAnalyzer, CapabilityRegistry, DeletionPlan,
        CAPABILITY_SCHEMA_VERSION,
    };

    #[test]
    fn pause_scan_requests_persistence_and_cancellation() {
        let engine = VolwardEngine::new();

        engine.pause_current_scan();

        assert!(engine.persist_pause.load(Ordering::Acquire));
        assert!(engine.cancel.load(Ordering::Acquire));
    }

    #[test]
    fn pause_persist_error_is_observable_to_caller() {
        let engine = VolwardEngine::new();
        *engine.last_pause_error.lock().unwrap() = Some("pause save failed".to_string());

        assert_eq!(
            engine.get_last_pause_error().as_deref(),
            Some("pause save failed")
        );
    }

    struct BlockingAnalyzer {
        capability: Capability,
        started: Mutex<Option<Sender<()>>>,
        release: Mutex<Receiver<()>>,
    }

    impl CapabilityAnalyzer for BlockingAnalyzer {
        fn capability(&self) -> Capability {
            self.capability
        }

        fn analyze(
            &self,
            index: &SnapshotIndex,
            normalized_root: &str,
            _options: &AnalysisOptions,
            _progress: &dyn volward_core::CapabilityProgressSink,
        ) -> Result<CapabilityAnalysisResult, CapabilityAnalysisError> {
            if let Some(started) = self.started.lock().unwrap().take() {
                started.send(()).unwrap();
            }
            self.release.lock().unwrap().recv().unwrap();
            Ok(capability_result_for(index, normalized_root, self.capability))
        }
    }

    fn minimal_snapshot() -> StorageSnapshot {
        StorageSnapshot {
            snapshot_id: "test-snap".to_string(),
            scanned_at_ms: 1,
            capability: CapabilityLevel::FullPath,
            volume_total_bytes: 100,
            volume_used_bytes: 50,
            reclaimable_estimate_bytes: 10,
            entries: vec![StorageEntry {
                id: "e1".to_string(),
                display_name: "file".to_string(),
                path_or_uri: "/tmp/file".to_string(),
                size_bytes: 10,
                category: EntryCategory::Cache,
                risk_level: RiskLevel::Low,
                source_type: SourceType::File,
                deletable: true,
                reason: "test".to_string(),
                modified_at_ms: None,
            }],
            tree: ScanTreeNode {
                name: "root".to_string(),
                path: "/".to_string(),
                is_dir: true,
                size_bytes: 10,
                entry_id: None,
                children: vec![],
            },
            stats: ScanStats::default(),
            warnings: vec![],
        }
    }

    fn capability_result_for(
        index: &SnapshotIndex,
        root_path: &str,
        capability: Capability,
    ) -> CapabilityAnalysisResult {
        CapabilityAnalysisResult {
            schema_version: CAPABILITY_SCHEMA_VERSION,
            capability,
            snapshot_id: index.snapshot_id.clone(),
            root_path: root_path.to_string(),
            analyzer_version: "fake-v1".to_string(),
            generated_at_ms: 1,
            capability_level: CapabilityLevel::FullPath,
            summary: AnalysisSummary::default(),
            groups: vec![],
            next_cursor: None,
            deletion_plan: DeletionPlan {
                snapshot_id: index.snapshot_id.clone(),
                target_count: 0,
                target_bytes: 0,
                targets: vec![],
                blocked_targets: vec![],
                requires_confirmation: true,
            },
            warnings: vec![],
        }
    }

    fn options_json() -> String {
        serde_json::to_string(&AnalysisOptions {
            root_path: "/".to_string(),
            ..AnalysisOptions::default()
        })
        .unwrap()
    }

    fn blocking_engine() -> (VolwardEngine, Receiver<()>, Sender<()>) {
        let (started_tx, started_rx) = mpsc::channel();
        let (release_tx, release_rx) = mpsc::channel();
        let mut registry = CapabilityRegistry::new();
        registry.register(Arc::new(BlockingAnalyzer {
            capability: Capability::LargeFiles,
            started: Mutex::new(Some(started_tx)),
            release: Mutex::new(release_rx),
        }));
        let engine = VolwardEngine::with_capability_registry(registry);
        engine.set_last_snapshot(minimal_snapshot());
        (engine, started_rx, release_tx)
    }

    fn capability_name(capability: Capability) -> &'static str {
        match capability {
            Capability::LargeFiles => "large_files",
            Capability::CleanupCandidates => "cleanup_candidates",
            Capability::DuplicateFiles => "duplicate_files",
            Capability::SimilarPhotos => "similar_photos",
            Capability::Applications => "applications",
            Capability::BrowserPrivacy => "browser_privacy",
            Capability::SpaceAnalysis => "space_analysis",
        }
    }

    fn start_capability_job(engine: &VolwardEngine) -> String {
        let raw = engine.start_capability_analysis_json(
            "test-snap",
            "large_files",
            &options_json(),
        );
        let value: serde_json::Value = serde_json::from_str(&raw).expect("start response JSON");
        value["job_id"].as_str().expect("job_id").to_string()
    }

    fn wait_for_completed_status(engine: &VolwardEngine, job_id: &str) -> serde_json::Value {
        for _ in 0..100 {
            let raw = engine.get_capability_job_status_json(job_id);
            let status: serde_json::Value = serde_json::from_str(&raw).unwrap();
            if status["progress"]["phase"] == "completed"
                || status["progress"]["cancelled"] == true
            {
                return status;
            }
            std::thread::sleep(std::time::Duration::from_millis(5));
        }
        panic!("capability job did not finish");
    }

    #[test]
    fn capability_analysis_rejects_snapshot_mismatch_and_unsupported_capability() {
        let engine = VolwardEngine::new();
        engine.set_last_snapshot(minimal_snapshot());

        let mismatch: serde_json::Value = serde_json::from_str(
            &engine.analyze_capability_json("stale", "large_files", &options_json()),
        )
        .unwrap();
        assert_eq!(mismatch["error"]["code"], "snapshot_mismatch");

        // All analyzer-backed capabilities are registered by `new()`; an
        // unregistered capability must still return a structured error.
        let unsupported: serde_json::Value = serde_json::from_str(
            &engine.analyze_capability_json("test-snap", "space_analysis", &options_json()),
        )
        .unwrap();
        assert_eq!(unsupported["error"]["code"], "unsupported_capability");
    }

    #[test]
    fn async_capability_job_reports_progress_and_cancels_without_result() {
        let (engine, started, release) = blocking_engine();
        let job_id = start_capability_job(&engine);
        started.recv().unwrap();

        let active: serde_json::Value = serde_json::from_str(
            &engine.get_capability_job_status_json(&job_id),
        )
        .unwrap();
        assert_eq!(active["progress"]["phase"], "inspecting");
        assert!(engine.cancel_capability_analysis(&job_id));
        release.send(()).unwrap();

        let cancelled = wait_for_completed_status(&engine, &job_id);
        assert_eq!(cancelled["progress"]["cancelled"], true);
        assert!(cancelled["result"].is_null());
    }

    #[test]
    fn async_capability_job_rejects_result_when_snapshot_changes() {
        let (engine, started, release) = blocking_engine();
        let job_id = start_capability_job(&engine);
        started.recv().unwrap();

        let mut replacement = minimal_snapshot();
        replacement.snapshot_id = "replacement-snap".to_string();
        engine.set_last_snapshot(replacement);
        release.send(()).unwrap();

        let completed = wait_for_completed_status(&engine, &job_id);
        assert!(completed["result"].is_null());
        let error = completed["progress"]["error"].as_str().unwrap();
        let error: serde_json::Value = serde_json::from_str(error).unwrap();
        assert_eq!(error["code"], "snapshot_mismatch");
    }

    #[test]
    fn capability_jobs_are_capped_when_many_are_in_flight() {
        let capabilities = [
            Capability::LargeFiles,
            Capability::CleanupCandidates,
            Capability::DuplicateFiles,
            Capability::SimilarPhotos,
        ];
        let mut registry = CapabilityRegistry::new();
        let mut starteds = Vec::new();
        let mut releases = Vec::new();
        for capability in capabilities {
            let (started_tx, started_rx) = mpsc::channel();
            let (release_tx, release_rx) = mpsc::channel();
            registry.register(Arc::new(BlockingAnalyzer {
                capability,
                started: Mutex::new(Some(started_tx)),
                release: Mutex::new(release_rx),
            }));
            starteds.push(started_rx);
            releases.push(release_tx);
        }
        let engine = VolwardEngine::with_capability_registry(registry);
        engine.set_last_snapshot(minimal_snapshot());

        for (capability, started) in capabilities.iter().zip(starteds.iter()) {
            let raw = engine.start_capability_analysis_json(
                "test-snap",
                capability_name(*capability),
                &options_json(),
            );
            let value: serde_json::Value = serde_json::from_str(&raw).unwrap();
            assert!(value["job_id"].is_string(), "{raw}");
            started.recv().unwrap();
        }

        let busy = engine.start_capability_analysis_json(
            "test-snap",
            capability_name(Capability::LargeFiles),
            &options_json(),
        );
        let value: serde_json::Value = serde_json::from_str(&busy).unwrap();
        assert_eq!(value["error"]["code"], "busy", "{busy}");

        for release in releases {
            release.send(()).unwrap();
        }
    }

    #[test]
    fn build_ai_candidates_json_caps_aggregates_and_lists_build_artifacts() {
        let engine = VolwardEngine::new();
        let temp = tempfile::TempDir::new().unwrap();
        let scratch_root = temp.path().join("scratch");
        std::fs::create_dir_all(&scratch_root).unwrap();
        let mut snapshot = minimal_snapshot();
        snapshot.entries.push(StorageEntry {
            id: "e-node".to_string(),
            display_name: "node_modules".to_string(),
            path_or_uri: "/Users/x/app/node_modules".to_string(),
            size_bytes: 4096,
            category: EntryCategory::BuildArtifact,
            risk_level: RiskLevel::Low,
            source_type: SourceType::Directory,
            deletable: true,
            reason: "build artifact".to_string(),
            modified_at_ms: None,
        });
        // 250 unclassified siblings fold into one aggregate candidate.
        // Sizes are physical allocated bytes so dry-run deletion can revalidate.
        let mut children = Vec::with_capacity(250);
        let mut child_allocated = 0u64;
        for i in 0..250u32 {
            let path = scratch_root.join(format!("blob_{i}.dat"));
            std::fs::write(&path, [0u8]).unwrap();
            child_allocated =
                volward_core::model::allocated_file_size(&std::fs::metadata(&path).unwrap());
            children.push(ScanTreeNode {
                name: format!("blob_{i}.dat"),
                path: path.to_string_lossy().to_string(),
                is_dir: false,
                size_bytes: child_allocated,
                entry_id: None,
                children: vec![],
            });
        }
        snapshot.tree.children.push(ScanTreeNode {
            name: "scratch".to_string(),
            path: scratch_root.to_string_lossy().to_string(),
            is_dir: true,
            size_bytes: child_allocated.saturating_mul(250),
            entry_id: None,
            children,
        });
        engine.set_last_snapshot(snapshot);

        let json = engine.build_ai_candidates_json("test-snap");
        let parsed: serde_json::Value = serde_json::from_str(&json).expect("valid json: {json}");
        let candidates = parsed["unknown_candidates"].as_array().expect("candidates");
        assert_eq!(candidates.len(), 1, "{json}");
        assert_eq!(
            candidates[0]["path"],
            scratch_root.to_string_lossy().to_string()
        );
        assert_eq!(
            candidates[0]["member_paths"].as_array().map(Vec::len),
            Some(200),
            "{json}"
        );
        assert_eq!(
            candidates[0]["delete_target"],
            format!("volward-ai-aggregate:v1:{}", scratch_root.to_string_lossy())
        );
        assert!(candidates[0].get("delete_member_paths").is_none(), "{json}");
        assert_eq!(parsed["truncated"], false);
        assert_eq!(parsed["total_raw_count"], 250);
        assert_eq!(parsed["candidates_total_before_cap"], 1);

        let pre = parsed["pre_classified"].as_array().expect("pre_classified");
        assert!(
            pre.iter()
                .any(|e| e["path"] == "/Users/x/app/node_modules" && e["confidence"] == "high"),
            "{json}"
        );

        let token = candidates[0]["delete_target"].as_str().unwrap().to_string();
        let report = engine.delete_entries_json("test-snap", vec![token], true);
        assert!(report.contains(r#""deleted_count":250"#), "{report}");
        let expected_freed = child_allocated.saturating_mul(250);
        assert!(
            report.contains(&format!(r#""freed_bytes":{expected_freed}"#)),
            "{report}"
        );
    }

    #[test]
    fn write_last_snapshot_roundtrip() {
        let engine = VolwardEngine::new();
        let snapshot = minimal_snapshot();
        let expected_id = snapshot.snapshot_id.clone();
        engine.set_last_snapshot(snapshot);

        let path = std::env::temp_dir().join(format!(
            "volward-write-snapshot-{}.json",
            std::process::id()
        ));
        let path_str = path.to_string_lossy();

        let id = engine
            .write_last_snapshot_to_path(&path_str)
            .expect("write should succeed");
        assert_eq!(id, expected_id);

        let engine2 = VolwardEngine::new();
        engine2
            .load_last_snapshot_from_path(&path_str)
            .expect("load should succeed");
        let loaded = engine2.get_last_snapshot().expect("snapshot loaded");
        assert_eq!(loaded.snapshot_id, expected_id);

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn load_last_snapshot_from_path_accepts_pb_snapshot() {
        use prost::Message;

        let snapshot = minimal_snapshot();
        let expected_id = snapshot.snapshot_id.clone();
        let path = std::env::temp_dir().join(format!(
            "volward-pb-snapshot-{}.pb",
            std::process::id()
        ));
        let bytes = proto::StorageSnapshot::from(&snapshot).encode_to_vec();
        std::fs::write(&path, bytes).expect("write pb snapshot");

        let engine = VolwardEngine::new();
        engine
            .load_last_snapshot_from_path(&path.to_string_lossy())
            .expect("pb snapshot should load");
        let loaded = engine.get_last_snapshot().expect("snapshot loaded");
        assert_eq!(loaded.snapshot_id, expected_id);

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn load_index_from_path_accepts_pb_index() {
        use prost::Message;

        use volward_index_pb::snapshot_index_to_proto;

        let index = SnapshotIndex::from(&minimal_snapshot());
        let expected_id = index.snapshot_id.clone();
        let path = std::env::temp_dir().join(format!(
            "volward-pb-index-{}.pb",
            std::process::id()
        ));

        let pb = snapshot_index_to_proto(&index);
        std::fs::write(&path, pb.encode_to_vec()).expect("write pb index");

        let engine = VolwardEngine::new();
        engine
            .load_index_from_path(&path.to_string_lossy())
            .expect("pb index should load");
        let summary_json = engine
            .get_index_summary_json()
            .expect("index summary should exist");
        assert!(summary_json.contains(&expected_id));

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn load_index_from_path_accepts_legacy_snapshot_json() {
        let snapshot = minimal_snapshot();
        let expected_id = snapshot.snapshot_id.clone();
        let path = std::env::temp_dir().join(format!(
            "volward-legacy-snapshot-index-{}.json",
            std::process::id()
        ));

        let file = File::create(&path).expect("create legacy snapshot");
        serde_json::to_writer(BufWriter::new(file), &snapshot).expect("write legacy snapshot");

        let engine = VolwardEngine::new();
        engine
            .load_index_from_path(&path.to_string_lossy())
            .expect("legacy snapshot should load as index");
        let summary_json = engine
            .get_index_summary_json()
            .expect("index summary should exist");
        assert!(summary_json.contains(&expected_id));

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn delete_entries_json_allows_explicit_non_deletable_media_in_index_mode() {
        let engine = VolwardEngine::new();
        let temp = tempfile::TempDir::new().unwrap();
        let movie = temp.path().join("movie.mov");
        std::fs::write(&movie, vec![0u8; 120]).unwrap();
        let movie_path = movie.to_string_lossy().to_string();
        let movie_bytes =
            volward_core::model::allocated_file_size(&std::fs::metadata(&movie).unwrap());
        let mut snapshot = minimal_snapshot();
        snapshot.entries.push(StorageEntry {
            id: "e3".to_string(),
            display_name: "movie.mov".to_string(),
            path_or_uri: movie_path.clone(),
            size_bytes: movie_bytes,
            category: EntryCategory::Media,
            risk_level: RiskLevel::High,
            source_type: SourceType::File,
            deletable: false,
            reason: "media".to_string(),
            modified_at_ms: None,
        });
        engine.set_last_snapshot(snapshot);

        let report = engine.delete_entries_json("test-snap", vec!["e3".to_string()], true);
        assert!(report.contains(r#""deleted_count":1"#), "{report}");
        assert!(
            report.contains(&format!(r#""freed_bytes":{movie_bytes}"#)),
            "{report}"
        );
        assert!(!report.contains(r#""error""#), "{report}");
        let _ = movie_path;
    }

    #[test]
    fn delete_entries_json_allows_directory_paths_in_index_mode() {
        let engine = VolwardEngine::new();
        let temp = tempfile::TempDir::new().unwrap();
        let users_dir = temp.path().join("Users");
        std::fs::create_dir_all(&users_dir).unwrap();
        let notes = users_dir.join("notes.txt");
        std::fs::write(&notes, vec![0u8; 40]).unwrap();
        let users_path = users_dir.to_string_lossy().to_string();
        let mut snapshot = minimal_snapshot();
        snapshot.tree.children.push(ScanTreeNode {
            name: "Users".to_string(),
            path: users_path.clone(),
            is_dir: true,
            size_bytes: 40,
            entry_id: None,
            children: vec![ScanTreeNode {
                name: "notes.txt".to_string(),
                path: notes.to_string_lossy().to_string(),
                is_dir: false,
                size_bytes: 40,
                entry_id: Some("dir-child".to_string()),
                children: vec![],
            }],
        });
        engine.set_last_snapshot(snapshot);

        let report = engine.delete_entries_json("test-snap", vec![users_path.clone()], true);
        assert!(report.contains(r#""deleted_count":1"#), "{report}");
        assert!(report.contains(r#""freed_bytes":40"#), "{report}");
        assert!(!report.contains(r#""error""#), "{report}");
        let _ = users_path;
    }

    #[test]
    fn async_load_index_from_path_accepts_pb_index() {
        use prost::Message;

        use volward_index_pb::snapshot_index_to_proto;

        let index = SnapshotIndex::from(&minimal_snapshot());
        let expected_id = index.snapshot_id.clone();
        let path = std::env::temp_dir().join(format!(
            "volward-async-pb-index-{}.pb",
            std::process::id()
        ));

        let pb = snapshot_index_to_proto(&index);
        std::fs::write(&path, pb.encode_to_vec()).expect("write pb index");

        let engine = VolwardEngine::new();
        assert_eq!(
            engine.start_load_index_from_path_async(path.to_string_lossy().into_owned()),
            "ok"
        );
        while engine.is_index_loading() {
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        assert!(engine.get_last_index_load_error().is_none());
        let summary_json = engine
            .get_index_summary_json()
            .expect("index summary should exist");
        assert!(summary_json.contains(&expected_id));

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn async_load_index_from_path_accepts_legacy_snapshot_json() {
        let snapshot = minimal_snapshot();
        let expected_id = snapshot.snapshot_id.clone();
        let path = std::env::temp_dir().join(format!(
            "volward-async-legacy-snapshot-index-{}.json",
            std::process::id()
        ));

        let file = File::create(&path).expect("create legacy snapshot");
        serde_json::to_writer(BufWriter::new(file), &snapshot).expect("write legacy snapshot");

        let engine = VolwardEngine::new();
        assert_eq!(
            engine.start_load_index_from_path_async(path.to_string_lossy().into_owned()),
            "ok"
        );
        while engine.is_index_loading() {
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        assert!(engine.get_last_index_load_error().is_none());
        let summary_json = engine
            .get_index_summary_json()
            .expect("index summary should exist");
        assert!(summary_json.contains(&expected_id));

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn invalidated_async_index_load_does_not_publish_stale_error() {
        let engine = VolwardEngine::new();
        let missing_path = std::env::temp_dir().join(format!(
            "volward-missing-index-{}-{}.json",
            std::process::id(),
            uuid::Uuid::new_v4()
        ));

        assert_eq!(
            engine.start_load_index_from_path_async(missing_path.to_string_lossy().into_owned()),
            "ok"
        );
        engine.invalidate_index_load();
        assert!(!engine.is_index_loading());

        std::thread::sleep(std::time::Duration::from_millis(50));

        assert!(!engine.is_index_loading());
        assert!(engine.get_last_index_load_error().is_none());
    }

    #[test]
    fn invalidate_index_load_allows_immediate_retry() {
        let engine = VolwardEngine::new();
        let first_path = std::env::temp_dir().join(format!(
            "volward-first-missing-index-{}-{}.json",
            std::process::id(),
            uuid::Uuid::new_v4()
        ));
        let second_path = std::env::temp_dir().join(format!(
            "volward-second-missing-index-{}-{}.json",
            std::process::id(),
            uuid::Uuid::new_v4()
        ));

        assert_eq!(
            engine.start_load_index_from_path_async(first_path.to_string_lossy().into_owned()),
            "ok"
        );
        engine.invalidate_index_load();
        assert!(!engine.is_index_loading());
        assert_eq!(
            engine.start_load_index_from_path_async(second_path.to_string_lossy().into_owned()),
            "ok"
        );
        while engine.is_index_loading() {
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
    }

    #[test]
    fn stale_async_worker_does_not_clear_loading_for_superseding_load() {
        let snapshot = minimal_snapshot();
        let slow_path = std::env::temp_dir().join(format!(
            "volward-slow-index-{}-{}.json",
            std::process::id(),
            uuid::Uuid::new_v4()
        ));
        let fast_path = std::env::temp_dir().join(format!(
            "volward-fast-index-{}-{}.json",
            std::process::id(),
            uuid::Uuid::new_v4()
        ));

        {
            let file = File::create(&slow_path).expect("create slow index");
            serde_json::to_writer(BufWriter::new(file), &SnapshotIndex::from(&snapshot))
                .expect("write slow index");
        }
        {
            let file = File::create(&fast_path).expect("create fast index");
            serde_json::to_writer(BufWriter::new(file), &SnapshotIndex::from(&snapshot))
                .expect("write fast index");
        }

        let engine = VolwardEngine::new();
        assert_eq!(
            engine.start_load_index_from_path_async(slow_path.to_string_lossy().into_owned()),
            "ok"
        );
        engine.invalidate_index_load();
        assert_eq!(
            engine.start_load_index_from_path_async(fast_path.to_string_lossy().into_owned()),
            "ok"
        );
        while engine.is_index_loading() {
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        assert!(engine.get_last_index_load_error().is_none());
        assert!(
            engine
                .get_index_summary_json()
                .expect("superseding load should publish")
                .contains(&snapshot.snapshot_id)
        );

        let _ = std::fs::remove_file(&slow_path);
        let _ = std::fs::remove_file(&fast_path);
    }

    #[test]
    fn repeated_async_index_load_start_is_busy_or_retries_after_prior_load() {
        let engine = VolwardEngine::new();
        let first_path = std::env::temp_dir().join(format!(
            "volward-first-missing-index-{}-{}.json",
            std::process::id(),
            uuid::Uuid::new_v4()
        ));
        let second_path = std::env::temp_dir().join(format!(
            "volward-second-missing-index-{}-{}.json",
            std::process::id(),
            uuid::Uuid::new_v4()
        ));

        assert_eq!(
            engine.start_load_index_from_path_async(first_path.to_string_lossy().into_owned()),
            "ok"
        );
        let second_start =
            engine.start_load_index_from_path_async(second_path.to_string_lossy().into_owned());
        assert!(second_start == "ok" || second_start.starts_with("busy:"));
        while engine.is_index_loading() {
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        assert_eq!(
            engine.start_load_index_from_path_async(second_path.to_string_lossy().into_owned()),
            "ok"
        );
        while engine.is_index_loading() {
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
    }

    #[test]
    fn checkpoint_starts_empty_and_quick_list_dir_reports_unsupported_error() {
        let engine = VolwardEngine::new();
        assert!(engine.get_last_checkpoint().is_none());

        // No real directory needed: an obviously-missing path exercises the
        // error path end-to-end through the JSON encoding.
        let json = engine.quick_list_dir_json("/definitely/does/not/exist/volward-test");
        assert!(json.contains("error"));
    }

    #[test]
    fn parent_path_of_handles_windows_drive_root_children() {
        assert_eq!(parent_path_of("C:/pagefile.sys").as_deref(), Some("C:/"));
        assert_eq!(
            parent_path_of(r"C:\Users\me\a.txt").as_deref(),
            Some("C:/Users/me")
        );
        assert_eq!(
            parent_path_of("/Users/x/a.txt").as_deref(),
            Some("/Users/x")
        );
        assert_eq!(
            parent_path_of("//server/share/a/b.txt").as_deref(),
            Some("//server/share/a")
        );
        assert_eq!(
            parent_path_of("//server/share").as_deref(),
            Some("//server/share")
        );
    }

    #[test]
    fn coverage_plan_builds_from_index_and_pages_without_truncation() {
        use volward_core::index::SnapshotIndexBuilder;
        use volward_core::model::ScanStats;

        let engine = VolwardEngine::new();
        let root = "/Users/x";
        let mut builder = SnapshotIndexBuilder::new(root);
        for i in 0..120 {
            let path = if i % 2 == 0 {
                format!("/Users/x/Library/Caches/cursor/f{i}.bin")
            } else {
                format!("/Users/x/plain/f{i}.bin")
            };
            builder.record_file_size(&path, (i + 1) as u64);
        }
        let index = builder.finish(
            "coverage-snap".to_string(),
            1,
            1,
            "Done".to_string(),
            ScanStats::default(),
        );
        engine.set_last_index(index);

        let summary = engine.build_ai_coverage_plan_json("coverage-snap");
        assert!(summary.contains(r#""total_unclassified":60"#), "{summary}");
        assert!(summary.contains(r#""group_rows":0"#), "{summary}");
        assert!(summary.contains(r#""plan_version":2"#), "{summary}");
        assert!(summary.contains(r#""local_safe_files":60"#), "{summary}");
        assert!(summary.contains(r#""tree_pending_files":60"#), "{summary}");

        let page1 = engine.next_ai_coverage_page_json("coverage-snap", 2, 0, 40);
        let parsed: serde_json::Value = serde_json::from_str(&page1).unwrap();
        assert_eq!(parsed["rows"].as_array().unwrap().len(), 40);
        assert_eq!(parsed["next_cursor"], 40);

        let page2 = engine.next_ai_coverage_page_json("coverage-snap", 2, 40, 40);
        let parsed2: serde_json::Value = serde_json::from_str(&page2).unwrap();
        assert_eq!(parsed2["rows"].as_array().unwrap().len(), 20);
        assert_eq!(parsed2["next_cursor"], serde_json::Value::Null);
    }

    #[test]
    fn coverage_group_resolution_returns_all_members() {
        use volward_core::index::SnapshotIndexBuilder;
        use volward_core::model::ScanStats;

        let engine = VolwardEngine::new();
        let root = "/Users/x";
        let mut builder = SnapshotIndexBuilder::new(root);
        for i in 0..250 {
            builder.record_file_size(
                &format!("/Users/x/Library/Caches/cursor/f{i}.bin"),
                (i + 1) as u64,
            );
        }
        builder.record_file_size("/Users/x/Library/Caches/cursor/Code/nested.bin", 1);
        let index = builder.finish(
            "coverage-snap2".to_string(),
            1,
            1,
            "Done".to_string(),
            ScanStats::default(),
        );
        engine.set_last_index(index);

        engine.build_ai_coverage_plan_json("coverage-snap2");
        let json = engine.resolve_ai_coverage_group_json(
            "coverage-snap2",
            "/Users/x/Library/Caches/cursor",
        );
        let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed["members"].as_array().unwrap().len(), 251, "{json}");
    }

    #[test]
    fn coverage_plan_rejects_snapshot_mismatch() {
        let engine = VolwardEngine::new();
        let summary = engine.build_ai_coverage_plan_json("missing-snap");
        assert!(
            summary.contains("error:no index or snapshot loaded"),
            "{summary}"
        );
    }

    #[test]
    fn coverage_pages_report_missing_plan_without_building_one() {
        use volward_core::AI_COVERAGE_TREE_PLAN_VERSION;

        let engine = VolwardEngine::new();
        assert_eq!(
            engine.next_ai_coverage_page_json("missing-snap", 2, 0, 40),
            "error:coverage plan not built"
        );
        assert_eq!(
            engine.next_ai_tree_coverage_page_json(
                "missing-snap",
                AI_COVERAGE_TREE_PLAN_VERSION,
                0,
                40,
            ),
            "error:tree coverage plan not built"
        );
        assert_eq!(
            engine.next_ai_tail_coverage_page_json(
                "missing-snap",
                AI_COVERAGE_TREE_PLAN_VERSION,
                0,
                40,
            ),
            "error:tree coverage plan not built"
        );
    }

    #[test]
    fn local_coverage_verdicts_json_pages() {
        use volward_core::index::SnapshotIndexBuilder;
        use volward_core::model::{EntryCategory, RiskLevel, ScanStats, SourceType, StorageEntry};

        fn classified(path: &str) -> StorageEntry {
            StorageEntry {
                id: format!("id:{path}"),
                display_name: path.rsplit('/').next().unwrap_or(path).to_string(),
                path_or_uri: path.to_string(),
                size_bytes: 1,
                category: EntryCategory::Cache,
                risk_level: RiskLevel::Low,
                source_type: SourceType::File,
                deletable: true,
                reason: "test".to_string(),
                modified_at_ms: None,
            }
        }

        let engine = VolwardEngine::new();
        let mut builder = SnapshotIndexBuilder::new("/Users/x");
        builder.insert_entry(classified(
            "/Users/x/Library/Caches/myapp/anchor.bin",
        ));
        builder.record_file_size("/Users/x/Library/Caches/myapp/sibling.bin", 100);
        builder.record_file_size("/Users/x/MyProj/Cargo.toml", 10);
        builder.record_file_size("/Users/x/loose.dat", 5);
        let index = builder.finish(
            "local-verdicts-snap".to_string(),
            1,
            1,
            "Done".to_string(),
            ScanStats::default(),
        );
        engine.set_last_index(index);

        let page1 = engine.list_local_coverage_verdicts_json("local-verdicts-snap", 0, 1);
        let parsed1: serde_json::Value = serde_json::from_str(&page1).unwrap();
        assert_eq!(parsed1["verdicts"].as_array().unwrap().len(), 1);
        let cursor1 = parsed1["next_cursor"].as_u64().expect("next page cursor");

        let page2 = engine.list_local_coverage_verdicts_json("local-verdicts-snap", cursor1, 100);
        let parsed2: serde_json::Value = serde_json::from_str(&page2).unwrap();
        assert!(parsed2["verdicts"].as_array().unwrap().len() >= 1);
        assert!(parsed2["next_cursor"].is_null());
    }

    #[test]
    fn coverage_plan_summary_includes_funnel_stats() {
        use volward_core::index::SnapshotIndexBuilder;
        use volward_core::model::{EntryCategory, RiskLevel, ScanStats, SourceType, StorageEntry};

        fn classified(path: &str) -> StorageEntry {
            StorageEntry {
                id: format!("id:{path}"),
                display_name: path.rsplit('/').next().unwrap_or(path).to_string(),
                path_or_uri: path.to_string(),
                size_bytes: 1,
                category: EntryCategory::Cache,
                risk_level: RiskLevel::Low,
                source_type: SourceType::File,
                deletable: true,
                reason: "test".to_string(),
                modified_at_ms: None,
            }
        }

        let engine = VolwardEngine::new();
        let root = "/Users/x";
        let mut builder = SnapshotIndexBuilder::new(root);
        builder.insert_entry(classified(
            "/Users/x/Library/Caches/myapp/anchor.bin",
        ));
        builder.record_file_size("/Users/x/Library/Caches/myapp/sibling.bin", 100);
        builder.record_file_size("/Users/x/MyProj/Cargo.toml", 10);
        builder.record_file_size("/Users/x/MyProj/src/main.rs", 20);
        builder.record_file_size("/Users/x/loose.dat", 5);
        builder.record_file_size("/Users/x/project/llm-output/note.md", 5);
        let index = builder.finish(
            "coverage-funnel-snap".to_string(),
            1,
            1,
            "Done".to_string(),
            ScanStats::default(),
        );
        engine.set_last_index(index);

        let summary = engine.build_ai_coverage_plan_json("coverage-funnel-snap");
        let parsed: serde_json::Value = serde_json::from_str(&summary).unwrap();
        assert!(parsed["local_safe_files"].as_u64().unwrap_or(0) >= 1);
        assert!(parsed["local_keep_files"].as_u64().unwrap_or(0) >= 1);
        assert!(parsed["tail_files"].as_u64().unwrap_or(0) >= 1);
        assert!(parsed["tree_pending_files"].as_u64().unwrap_or(0) >= 1);
    }

    #[test]
    #[cfg(debug_assertions)]
    fn concurrent_tree_plan_builds_unclassified_cache_once() {
        use std::sync::Arc;
        use std::thread;
        use volward_core::index::SnapshotIndexBuilder;
        use volward_core::model::ScanStats;

        let dir = std::env::temp_dir().join("volward-facade-concurrent-cache");
        let _ = std::fs::remove_dir_all(&dir);
        std::env::set_var("VOLWARD_CACHE_DIR", dir.to_string_lossy().as_ref());

        volward_core::debug_reset_unclassified_cache_build_count();
        let engine = Arc::new(VolwardEngine::new());
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.record_file_size("/root/a.dat", 100);
        builder.record_file_size("/root/b.dat", 200);
        let index = builder.finish(
            "concurrent-cache-snap".to_string(),
            1,
            9,
            "Done".to_string(),
            ScanStats::default(),
        );
        engine.set_last_index(index);
        engine.clear_local_coverage_funnel_cache();

        let e1 = Arc::clone(&engine);
        let e2 = Arc::clone(&engine);
        let h1 = thread::spawn(move || e1.build_ai_tree_plan_json("concurrent-cache-snap"));
        let h2 = thread::spawn(move || e2.build_ai_tree_plan_json("concurrent-cache-snap"));
        assert!(!h1.join().unwrap().starts_with("error:"));
        assert!(!h2.join().unwrap().starts_with("error:"));
        assert_eq!(volward_core::debug_unclassified_cache_build_count(), 1);
        let _ = std::fs::remove_dir_all(&dir);
        std::env::remove_var("VOLWARD_CACHE_DIR");
    }

    #[test]
    fn coverage_sidecar_restores_cache_after_memory_clear() {
        use volward_core::index::SnapshotIndexBuilder;
        use volward_core::model::ScanStats;

        let dir = std::env::temp_dir().join("volward-facade-sidecar-restore");
        let _ = std::fs::remove_dir_all(&dir);
        std::env::set_var("VOLWARD_CACHE_DIR", dir.to_string_lossy().as_ref());

        let engine = VolwardEngine::new();
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.record_file_size("/root/a.dat", 100);
        let index = builder.finish(
            "sidecar-restore-snap".to_string(),
            1,
            7,
            "Done".to_string(),
            ScanStats::default(),
        );
        engine.set_last_index(index);
        let first = engine.build_ai_tree_plan_json("sidecar-restore-snap");
        assert!(!first.starts_with("error:"));
        assert!(
            volward_core::coverage_cache_bin_path("sidecar-restore-snap").exists(),
            "first build should persist sidecar bin"
        );

        engine.clear_local_coverage_funnel_cache();
        let second = engine.build_ai_tree_plan_json("sidecar-restore-snap");
        assert_eq!(first, second);

        let _ = std::fs::remove_dir_all(&dir);
        std::env::remove_var("VOLWARD_CACHE_DIR");
    }

    #[test]
    fn coverage_unified_cache_reused_for_second_tree_plan() {
        use volward_core::index::SnapshotIndexBuilder;
        use volward_core::model::ScanStats;

        let engine = VolwardEngine::new();
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.record_file_size("/root/a.dat", 100);
        let index = builder.finish(
            "tree-cache-snap".to_string(),
            1,
            1,
            "Done".to_string(),
            ScanStats::default(),
        );
        engine.set_last_index(index);
        let first = engine.build_ai_tree_plan_json("tree-cache-snap");
        assert!(!first.starts_with("error:"));
        let second = engine.build_ai_tree_plan_json("tree-cache-snap");
        assert_eq!(first, second);
        let guard = engine.unclassified_coverage_cache.lock().unwrap();
        assert!(guard.is_some());
    }

    #[test]
    fn coverage_tree_plan_builds_and_pages() {
        use volward_core::index::SnapshotIndexBuilder;
        use volward_core::model::ScanStats;
        use volward_core::AI_COVERAGE_TREE_PLAN_VERSION;

        let engine = VolwardEngine::new();
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.ensure_dir("/root/proj/src");
        builder.ensure_dir("/root/proj/llm-output");
        builder.ensure_dir("/root/unknown_storage");
        builder.record_file_size("/root/proj/Cargo.toml", 10);
        builder.record_file_size("/root/proj/src/main.rs", 200);
        builder.record_file_size("/root/proj/llm-output/out.md", 50);
        builder.record_file_size("/root/unknown_storage/misc.dat", 500);
        let index = builder.finish(
            "tree-coverage-snap".to_string(),
            1,
            1,
            "Done".to_string(),
            ScanStats::default(),
        );
        engine.set_last_index(index);

        let summary = engine.build_ai_tree_plan_json("tree-coverage-snap");
        let parsed: serde_json::Value = serde_json::from_str(&summary).unwrap();
        assert_eq!(
            parsed["plan_version"].as_u64(),
            Some(AI_COVERAGE_TREE_PLAN_VERSION)
        );
        assert_eq!(parsed["seed_node_count"].as_u64(), Some(1));
        assert_eq!(parsed["tail_file_count"].as_u64(), Some(1));
        assert_eq!(parsed["estimated_tree_credits"].as_u64(), Some(1));
        assert_eq!(parsed["estimated_tail_credits"].as_u64(), Some(1));

        let tree_page = engine.next_ai_tree_coverage_page_json(
            "tree-coverage-snap",
            AI_COVERAGE_TREE_PLAN_VERSION,
            0,
            1,
        );
        let tree_parsed: serde_json::Value = serde_json::from_str(&tree_page).unwrap();
        assert_eq!(tree_parsed["nodes"].as_array().unwrap().len(), 1);
        assert_eq!(tree_parsed["next_cursor"], serde_json::Value::Null);
        assert_eq!(
            tree_parsed["nodes"][0]["path"].as_str(),
            Some("/root/unknown_storage")
        );

        let tail_page = engine.next_ai_tail_coverage_page_json(
            "tree-coverage-snap",
            AI_COVERAGE_TREE_PLAN_VERSION,
            0,
            1,
        );
        let tail_parsed: serde_json::Value = serde_json::from_str(&tail_page).unwrap();
        assert_eq!(tail_parsed["rows"].as_array().unwrap().len(), 1);
        assert_eq!(tail_parsed["next_cursor"], serde_json::Value::Null);
        assert_eq!(
            tail_parsed["rows"][0]["path"].as_str(),
            Some("/root/proj/llm-output/out.md")
        );
    }

    #[test]
    fn apply_dir_verdict_json_propagates_under_storage_dir() {
        use volward_core::index::SnapshotIndexBuilder;
        use volward_core::model::ScanStats;

        let engine = VolwardEngine::new();
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.ensure_dir("/root/storage");
        builder.record_file_size("/root/storage/a.dat", 100);
        builder.record_file_size("/root/other/outside.dat", 10);
        let index = builder.finish(
            "apply-dir-snap".to_string(),
            1,
            1,
            "Done".to_string(),
            ScanStats::default(),
        );
        engine.set_last_index(index);

        let raw = engine.apply_ai_dir_verdict_json(
            "apply-dir-snap",
            "/root/storage",
            "safe_to_remove",
            "high",
            "storage_like",
        );
        let parsed: serde_json::Value = serde_json::from_str(&raw).unwrap();
        let verdicts = parsed["verdicts"].as_array().unwrap();
        assert_eq!(verdicts.len(), 1);
        assert_eq!(verdicts[0]["path"].as_str(), Some("/root/storage/a.dat"));
        assert_eq!(verdicts[0]["verdict"].as_str(), Some("safe_to_remove"));
    }

    #[test]
    fn apply_dir_verdict_to_file_appends_jsonl_rows() {
        use volward_core::index::SnapshotIndexBuilder;
        use volward_core::model::ScanStats;

        let engine = VolwardEngine::new();
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.record_file_size("/root/storage/a.dat", 100);
        builder.record_file_size("/root/storage/b.dat", 5);
        builder.record_file_size("/root/other/outside.dat", 10);
        let index = builder.finish(
            "apply-dir-file-snap".to_string(),
            1,
            1,
            "Done".to_string(),
            ScanStats::default(),
        );
        engine.set_last_index(index);

        let dir = tempfile::tempdir().unwrap();
        let out = dir.path().join("verdicts.jsonl");
        std::fs::write(&out, "{\"path\":\"/existing\"}\n").unwrap();
        let raw = engine.apply_ai_dir_verdict_to_file(
            "apply-dir-file-snap",
            "/root/storage",
            "keep",
            "high",
            "unknown",
            out.to_str().unwrap(),
        );
        let parsed: serde_json::Value = serde_json::from_str(&raw).unwrap();
        assert_eq!(parsed["count"].as_u64(), Some(2));

        let text = std::fs::read_to_string(&out).unwrap();
        let lines: Vec<&str> = text.lines().collect();
        assert_eq!(lines.len(), 3);
        assert_eq!(lines[0], "{\"path\":\"/existing\"}");
        let mut paths: Vec<String> = lines[1..]
            .iter()
            .map(|line| {
                let row: serde_json::Value = serde_json::from_str(line).unwrap();
                assert_eq!(row["verdict"].as_str(), Some("keep"));
                assert_eq!(row["coverage_source"].as_str(), Some("dir_propagate:/root/storage"));
                row["path"].as_str().unwrap().to_string()
            })
            .collect();
        paths.sort();
        assert_eq!(paths, vec!["/root/storage/a.dat", "/root/storage/b.dat"]);
    }
}
