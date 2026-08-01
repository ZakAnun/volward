use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::model::{EntryCategory, StorageEntry, StorageSnapshot};

// ---------------------------------------------------------------------------
// Query structs (returned to callers / serialised to Dart over FFI)
// ---------------------------------------------------------------------------

/// Lightweight node descriptor returned in query results.
/// Mirrors the Dart `SnapshotNodeRecord` class field-for-field.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SnapshotNodeRecord {
    pub path: String,
    pub name: String,
    pub is_directory: bool,
    pub size_bytes: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub entry_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub category: Option<String>,
    pub deletable: bool,
    pub scanned: bool,
    #[serde(default)]
    pub category_mask: u64,
    #[serde(default)]
    pub deletable_category_mask: u64,
    #[serde(default)]
    pub deletable_file_count: u64,
}

/// Entry-level detail returned alongside directory query results.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SnapshotEntryRecord {
    pub id: String,
    pub path: String,
    pub parent_path: String,
    pub display_name: String,
    pub size_bytes: u64,
    pub category: String,
    pub deletable: bool,
}

/// Result of a single `query_directory` / `refresh_directory` call.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SnapshotQueryResult {
    pub snapshot_id: String,
    pub version: u64,
    pub path: String,
    pub direct_children: Vec<SnapshotNodeRecord>,
    pub direct_entries: Vec<SnapshotEntryRecord>,
    pub total_bytes: u64,
    pub reclaimable_bytes: u64,
}

/// Lightweight catalog summary for Dart/UI state.
///
/// This lets the UI render counts and root metadata without hydrating the full
/// recursive snapshot tree.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SnapshotIndexSummary {
    pub snapshot_id: String,
    pub root_path: String,
    pub root_size_bytes: u64,
    pub scanned_at_ms: i64,
    pub version: u64,
    pub scan_state: String,
    pub reclaimable_estimate_bytes: u64,
    pub entry_count: u64,
    pub deletable_count: u64,
    pub category_counts: HashMap<String, u64>,
    pub deletable_counts: HashMap<String, u64>,
}

// ---------------------------------------------------------------------------
// Internal index records (not sent over FFI — held inside SnapshotIndex)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
struct DirectoryRecord {
    parent_path: Option<String>,
    name: String,
    size_bytes: u64,
    scanned: bool,
    peek_scanned: bool,
    category_mask: u64,
    deletable_category_mask: u64,
    deletable_file_count: u64,
}

/// Public-facing directory record (exposed via `directory_record()`).
#[derive(Debug, Clone)]
pub struct SnapshotDirectoryRecord {
    pub path: String,
    pub parent_path: Option<String>,
    pub name: String,
    pub size_bytes: u64,
    pub scanned: bool,
    pub peek_scanned: bool,
}

// ---------------------------------------------------------------------------
// SnapshotIndex — the authoritative in-memory catalog
// ---------------------------------------------------------------------------

/// Authoritative path-keyed index built from a `StorageSnapshot`.
///
/// Holds all fields required by Design §5.2:
/// - `snapshot_id`, `root_path`, `scanned_at_ms`, `version`
/// - `directory_by_path` (with `parent_path`)
/// - `entry_by_id`
/// - `children_by_path` (fast child lookup)
/// - `category_counts`, `deletable_counts`
/// - `reclaimable_estimate_bytes`, `scan_state`
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SnapshotIndex {
    pub snapshot_id: String,
    pub root_path: String,
    pub scanned_at_ms: i64,
    /// Monotonic version counter — incremented each time the index is rebuilt
    /// from a new snapshot.  Dart uses this as the `version` field in
    /// `SnapshotQueryKey` so cross-boundary cache invalidation is reliable.
    pub version: u64,
    pub scan_state: String,
    pub reclaimable_estimate_bytes: u64,

    directory_by_path: HashMap<String, DirectoryRecord>,
    entry_by_id: HashMap<String, SnapshotEntryRecord>,
    /// path -> entry_id for O(1) lookup in query_directory (avoids linear scan).
    entry_by_path: HashMap<String, String>,
    /// path -> ordered child paths (dirs before files, sorted by size desc)
    children_by_path: HashMap<String, Vec<String>>,
    category_counts: HashMap<String, u64>,
    deletable_counts: HashMap<String, u64>,
}

impl SnapshotIndex {
    // ------------------------------------------------------------------
    // Construction
    // ------------------------------------------------------------------

    pub fn from_snapshot(snapshot: &StorageSnapshot) -> Self {
        Self::from_snapshot_with_version(snapshot, 1)
    }

    pub fn from_snapshot_with_version(snapshot: &StorageSnapshot, version: u64) -> Self {
        let root_path = snapshot.tree.path.clone();

        let mut directory_by_path: HashMap<String, DirectoryRecord> = HashMap::new();
        let mut entry_by_id: HashMap<String, SnapshotEntryRecord> = HashMap::new();
        let mut entry_by_path: HashMap<String, String> = HashMap::new(); // path -> id
        let mut children_by_path: HashMap<String, Vec<String>> = HashMap::new();
        let mut category_counts: HashMap<String, u64> = HashMap::new();
        let mut deletable_counts: HashMap<String, u64> = HashMap::new();

        // Build entry lookup from the flat entries list.
        for entry in &snapshot.entries {
            let cat = format!("{:?}", entry.category);
            *category_counts.entry(cat.clone()).or_insert(0) += 1;
            if entry.deletable {
                *deletable_counts.entry(cat.clone()).or_insert(0) += 1;
            }
            let parent = parent_path_of(&entry.path_or_uri);
            entry_by_path.insert(entry.path_or_uri.clone(), entry.id.clone());
            entry_by_id.insert(
                entry.id.clone(),
                SnapshotEntryRecord {
                    id: entry.id.clone(),
                    path: entry.path_or_uri.clone(),
                    parent_path: parent,
                    display_name: entry.display_name.clone(),
                    size_bytes: entry.size_bytes,
                    category: format!("{:?}", entry.category),
                    deletable: entry.deletable,
                },
            );
        }

        // Walk the tree recursively to build directory records and
        // children_by_path.
        walk_tree(
            &snapshot.tree,
            None,
            &mut directory_by_path,
            &mut children_by_path,
            &entry_by_path,
            &entry_by_id,
        );

        Self {
            snapshot_id: snapshot.snapshot_id.clone(),
            root_path,
            scanned_at_ms: snapshot.scanned_at_ms,
            version,
            scan_state: "Done".to_string(),
            reclaimable_estimate_bytes: snapshot.reclaimable_estimate_bytes,
            directory_by_path,
            entry_by_id,
            entry_by_path,
            children_by_path,
            category_counts,
            deletable_counts,
        }
    }

    // ------------------------------------------------------------------
    // Accessors
    // ------------------------------------------------------------------

    pub fn category_counts(&self) -> &HashMap<String, u64> {
        &self.category_counts
    }

    pub fn deletable_counts(&self) -> &HashMap<String, u64> {
        &self.deletable_counts
    }

    pub fn reclaimable_estimate_bytes(&self) -> u64 {
        self.reclaimable_estimate_bytes
    }

    pub fn summary(&self) -> SnapshotIndexSummary {
        SnapshotIndexSummary {
            snapshot_id: self.snapshot_id.clone(),
            root_path: self.root_path.clone(),
            root_size_bytes: self
                .directory_by_path
                .get(&self.root_path)
                .map(|dir| dir.size_bytes)
                .unwrap_or(0),
            scanned_at_ms: self.scanned_at_ms,
            version: self.version,
            scan_state: self.scan_state.clone(),
            reclaimable_estimate_bytes: self.reclaimable_estimate_bytes,
            entry_count: self.entry_by_id.len().min(u64::MAX as usize) as u64,
            deletable_count: self.deletable_counts.values().sum(),
            category_counts: self.category_counts.clone(),
            deletable_counts: self.deletable_counts.clone(),
        }
    }

    pub fn summary_json(&self) -> Result<String, String> {
        serde_json::to_string(&self.summary()).map_err(|e| format!("error:serialize: {e}"))
    }

    pub fn deletable_entries_for_ids(&self, entry_ids: &[String]) -> Vec<SnapshotEntryRecord> {
        entry_ids
            .iter()
            .filter_map(|id| self.entry_by_id.get(id))
            .filter(|entry| entry.deletable)
            .cloned()
            .collect()
    }

    pub fn directory_record(&self, path: &str) -> Option<SnapshotDirectoryRecord> {
        self.directory_by_path
            .get(path)
            .map(|r| SnapshotDirectoryRecord {
                path: path.to_string(),
                parent_path: r.parent_path.clone(),
                name: r.name.clone(),
                size_bytes: r.size_bytes,
                scanned: r.scanned,
                peek_scanned: r.peek_scanned,
            })
    }

    // ------------------------------------------------------------------
    // Query
    // ------------------------------------------------------------------

    /// Returns direct children of `path` with optional filter and sort.
    /// This is a pure in-memory operation — no file-system access.
    pub fn query_directory(
        &self,
        path: &str,
        category_filter: Option<&str>,
        deletable_only: bool,
        sort_mode: &str,
    ) -> SnapshotQueryResult {
        let child_paths = match self.children_by_path.get(path) {
            Some(v) => v,
            None => {
                return SnapshotQueryResult {
                    snapshot_id: self.snapshot_id.clone(),
                    version: self.version,
                    path: path.to_string(),
                    direct_children: vec![],
                    direct_entries: vec![],
                    total_bytes: 0,
                    reclaimable_bytes: 0,
                };
            }
        };

        let mut direct_children: Vec<SnapshotNodeRecord> = Vec::new();
        let mut direct_entries: Vec<SnapshotEntryRecord> = Vec::new();
        let mut total_bytes: u64 = 0;
        let mut reclaimable_bytes: u64 = 0;

        for child_path in child_paths {
            // Try as directory first.
            if let Some(dir) = self.directory_by_path.get(child_path.as_str()) {
                if !passes_dir_filter(
                    dir,
                    category_filter,
                    deletable_only,
                    &self.children_by_path,
                    &self.entry_by_id,
                ) {
                    continue;
                }
                direct_children.push(SnapshotNodeRecord {
                    path: child_path.clone(),
                    name: dir.name.clone(),
                    is_directory: true,
                    size_bytes: dir.size_bytes,
                    entry_id: None,
                    category: Some("Folder".to_string()),
                    deletable: false,
                    scanned: dir.scanned,
                    category_mask: dir.category_mask,
                    deletable_category_mask: dir.deletable_category_mask,
                    deletable_file_count: dir.deletable_file_count,
                });
                total_bytes += dir.size_bytes;
                continue;
            }

            // Try as entry (file) — O(1) via path-keyed index.
            if let Some(entry_id) = self.entry_by_path.get(child_path.as_str()) {
                if let Some(entry) = self.entry_by_id.get(entry_id.as_str()) {
                    if !passes_entry_filter(entry, category_filter, deletable_only) {
                        continue;
                    }
                    total_bytes += entry.size_bytes;
                    if entry.deletable {
                        reclaimable_bytes += entry.size_bytes;
                    }
                    direct_children.push(SnapshotNodeRecord {
                        path: entry.path.clone(),
                        name: entry.display_name.clone(),
                        is_directory: false,
                        size_bytes: entry.size_bytes,
                        entry_id: Some(entry.id.clone()),
                        category: Some(entry.category.clone()),
                        deletable: entry.deletable,
                        scanned: true,
                        category_mask: category_mask_for_name(&entry.category),
                        deletable_category_mask: if entry.deletable {
                            category_mask_for_name(&entry.category)
                        } else {
                            0
                        },
                        deletable_file_count: if entry.deletable { 1 } else { 0 },
                    });
                    direct_entries.push(entry.clone());
                }
            }
        }

        // Apply sort.
        apply_sort(&mut direct_children, sort_mode);
        apply_entry_sort(&mut direct_entries, sort_mode);

        SnapshotQueryResult {
            snapshot_id: self.snapshot_id.clone(),
            version: self.version,
            path: path.to_string(),
            direct_children,
            direct_entries,
            total_bytes,
            reclaimable_bytes,
        }
    }

    /// Re-queries the existing index for `path` using default filter/sort.
    /// Pure in-memory — does not touch the file system or start a scan.
    pub fn refresh_directory(&self, path: &str) -> SnapshotQueryResult {
        self.query_directory(path, None, false, "size_desc")
    }

    /// Serialises a `query_directory` result to JSON.
    pub fn query_directory_json(
        &self,
        path: &str,
        category_filter: Option<&str>,
        deletable_only: bool,
        sort_mode: &str,
    ) -> Result<String, String> {
        let result = self.query_directory(path, category_filter, deletable_only, sort_mode);
        serde_json::to_string(&result).map_err(|e| format!("error:serialize: {e}"))
    }

    /// Serialises a `refresh_directory` result to JSON.
    pub fn refresh_directory_json(&self, path: &str) -> Result<String, String> {
        let result = self.refresh_directory(path);
        serde_json::to_string(&result).map_err(|e| format!("error:serialize: {e}"))
    }
}

impl From<&StorageSnapshot> for SnapshotIndex {
    fn from(snapshot: &StorageSnapshot) -> Self {
        Self::from_snapshot(snapshot)
    }
}

/// Incremental builder used by the scanner to avoid materialising a recursive
/// `StorageSnapshot` before creating the catalog.
pub struct SnapshotIndexBuilder {
    root_path: String,
    directory_by_path: HashMap<String, DirectoryRecord>,
    entry_by_id: HashMap<String, SnapshotEntryRecord>,
    entry_by_path: HashMap<String, String>,
    children_by_path: HashMap<String, Vec<String>>,
    category_counts: HashMap<String, u64>,
    deletable_counts: HashMap<String, u64>,
    reclaimable_estimate_bytes: u64,
}

impl SnapshotIndexBuilder {
    pub fn new(root_path: &str) -> Self {
        let root_path = normalize_path(root_path);
        let root_name = name_of(&root_path);
        let mut directory_by_path = HashMap::new();
        directory_by_path.insert(
            root_path.clone(),
            DirectoryRecord {
                parent_path: None,
                name: root_name,
                size_bytes: 0,
                scanned: true,
                peek_scanned: false,
                category_mask: 0,
                deletable_category_mask: 0,
                deletable_file_count: 0,
            },
        );
        let mut children_by_path = HashMap::new();
        children_by_path.insert(root_path.clone(), Vec::new());
        Self {
            root_path,
            directory_by_path,
            entry_by_id: HashMap::new(),
            entry_by_path: HashMap::new(),
            children_by_path,
            category_counts: HashMap::new(),
            deletable_counts: HashMap::new(),
            reclaimable_estimate_bytes: 0,
        }
    }

    pub fn ensure_dir(&mut self, path: &str) {
        let path = normalize_path(path);
        if !path_is_at_or_below(&path, &self.root_path) {
            return;
        }
        self.ensure_dir_internal(&path);
    }

    pub fn record_file_size(&mut self, path: &str, size_bytes: u64) {
        let path = normalize_path(path);
        if !path_is_at_or_below(&path, &self.root_path) {
            return;
        }
        let parent_path = parent_path_of_for_root(&path, &self.root_path);
        self.ensure_dir_internal(&parent_path);
        self.propagate_file_size(&parent_path, size_bytes);
    }

    pub fn insert_entry(&mut self, entry: StorageEntry) {
        if !path_is_at_or_below(&entry.path_or_uri, &self.root_path) {
            return;
        }
        let parent_path = parent_path_of_for_root(&entry.path_or_uri, &self.root_path);
        self.ensure_dir_internal(&parent_path);

        let category = category_string(&entry.category).to_string();
        let category_mask = category_mask_for_name(&category);
        *self.category_counts.entry(category.clone()).or_insert(0) += 1;
        if entry.deletable {
            *self.deletable_counts.entry(category.clone()).or_insert(0) += 1;
            self.reclaimable_estimate_bytes = self
                .reclaimable_estimate_bytes
                .saturating_add(entry.size_bytes);
        }

        let id = entry.id.clone();
        let path = entry.path_or_uri.clone();
        self.entry_by_path.insert(path.clone(), id.clone());
        self.entry_by_id.insert(
            id,
            SnapshotEntryRecord {
                id: entry.id,
                path: path.clone(),
                parent_path: parent_path.clone(),
                display_name: entry.display_name,
                size_bytes: entry.size_bytes,
                category,
                deletable: entry.deletable,
            },
        );
        self.add_child_once(&parent_path, &path);
        self.propagate_entry_metadata(&parent_path, category_mask, entry.deletable);
    }

    pub fn graft_directory_from_index(&mut self, source: &SnapshotIndex, dir_path: &str) {
        let dir_path = normalize_path(dir_path);
        let Some(source_dir) = source.directory_by_path.get(&dir_path).cloned() else {
            return;
        };
        if !path_is_at_or_below(&dir_path, &self.root_path) {
            return;
        }

        let parent_path = if dir_path == self.root_path {
            None
        } else {
            let parent_path = parent_path_of_for_root(&dir_path, &self.root_path);
            self.ensure_dir_internal(&parent_path);
            self.add_child_once(&parent_path, &dir_path);
            Some(parent_path)
        };

        let mut directory_paths = source
            .directory_by_path
            .keys()
            .filter(|path| path_is_at_or_below(path, &dir_path))
            .cloned()
            .collect::<Vec<_>>();
        directory_paths.sort_by_key(|path| path.len());

        for path in directory_paths {
            if let Some(record) = source.directory_by_path.get(&path) {
                self.directory_by_path.insert(path.clone(), record.clone());
            }
            if let Some(children) = source.children_by_path.get(&path) {
                self.children_by_path.insert(path, children.clone());
            }
        }

        for entry in source
            .entry_by_id
            .values()
            .filter(|entry| path_is_at_or_below(&entry.path, &dir_path))
        {
            let category = entry.category.clone();
            *self.category_counts.entry(category.clone()).or_insert(0) += 1;
            if entry.deletable {
                *self.deletable_counts.entry(category).or_insert(0) += 1;
                self.reclaimable_estimate_bytes = self
                    .reclaimable_estimate_bytes
                    .saturating_add(entry.size_bytes);
            }
            self.entry_by_path
                .insert(entry.path.clone(), entry.id.clone());
            self.entry_by_id.insert(entry.id.clone(), entry.clone());
        }

        if let Some(parent_path) = parent_path {
            self.propagate_grafted_directory_to_ancestors(&parent_path, &source_dir);
        }
    }

    pub fn finish(
        self,
        snapshot_id: String,
        scanned_at_ms: i64,
        version: u64,
        scan_state: String,
    ) -> SnapshotIndex {
        SnapshotIndex {
            snapshot_id,
            root_path: self.root_path,
            scanned_at_ms,
            version,
            scan_state,
            reclaimable_estimate_bytes: self.reclaimable_estimate_bytes,
            directory_by_path: self.directory_by_path,
            entry_by_id: self.entry_by_id,
            entry_by_path: self.entry_by_path,
            children_by_path: self.children_by_path,
            category_counts: self.category_counts,
            deletable_counts: self.deletable_counts,
        }
    }

    fn ensure_dir_internal(&mut self, path: &str) {
        if self.directory_by_path.contains_key(path) {
            return;
        }
        if path == self.root_path {
            return;
        }

        let parent_path = parent_path_of_for_root(path, &self.root_path);
        self.ensure_dir_internal(&parent_path);
        self.directory_by_path.insert(
            path.to_string(),
            DirectoryRecord {
                parent_path: Some(parent_path.clone()),
                name: name_of(path),
                size_bytes: 0,
                scanned: true,
                peek_scanned: false,
                category_mask: 0,
                deletable_category_mask: 0,
                deletable_file_count: 0,
            },
        );
        self.children_by_path.entry(path.to_string()).or_default();
        self.add_child_once(&parent_path, path);
    }

    fn add_child_once(&mut self, parent_path: &str, child_path: &str) {
        let children = self
            .children_by_path
            .entry(parent_path.to_string())
            .or_default();
        if !children.iter().any(|existing| existing == child_path) {
            children.push(child_path.to_string());
        }
    }

    fn propagate_file_size(&mut self, parent_path: &str, size_bytes: u64) {
        let mut current = Some(parent_path.to_string());
        while let Some(path) = current {
            let next = self
                .directory_by_path
                .get(&path)
                .and_then(|dir| dir.parent_path.clone());
            if let Some(dir) = self.directory_by_path.get_mut(&path) {
                dir.size_bytes = dir.size_bytes.saturating_add(size_bytes);
            }
            current = next;
        }
    }

    fn propagate_entry_metadata(&mut self, parent_path: &str, category_mask: u64, deletable: bool) {
        let mut current = Some(parent_path.to_string());
        while let Some(path) = current {
            let next = self
                .directory_by_path
                .get(&path)
                .and_then(|dir| dir.parent_path.clone());
            if let Some(dir) = self.directory_by_path.get_mut(&path) {
                dir.category_mask |= category_mask;
                if deletable {
                    dir.deletable_category_mask |= category_mask;
                    dir.deletable_file_count = dir.deletable_file_count.saturating_add(1);
                }
            }
            current = next;
        }
    }

    fn propagate_grafted_directory_to_ancestors(
        &mut self,
        parent_path: &str,
        source_dir: &DirectoryRecord,
    ) {
        let mut current = Some(parent_path.to_string());
        while let Some(path) = current {
            let next = self
                .directory_by_path
                .get(&path)
                .and_then(|dir| dir.parent_path.clone());
            if let Some(dir) = self.directory_by_path.get_mut(&path) {
                dir.size_bytes = dir.size_bytes.saturating_add(source_dir.size_bytes);
                dir.category_mask |= source_dir.category_mask;
                dir.deletable_category_mask |= source_dir.deletable_category_mask;
                dir.deletable_file_count = dir
                    .deletable_file_count
                    .saturating_add(source_dir.deletable_file_count);
            }
            current = next;
        }
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn normalize_path(path: &str) -> String {
    if path.len() > 1 && path.ends_with('/') {
        path[..path.len() - 1].to_string()
    } else if path.is_empty() {
        "/".to_string()
    } else {
        path.to_string()
    }
}

fn name_of(path: &str) -> String {
    path.rsplit('/')
        .next()
        .filter(|s| !s.is_empty())
        .unwrap_or(path)
        .to_string()
}

fn parent_path_of(path: &str) -> String {
    match path.rfind('/') {
        Some(i) if i > 0 => path[..i].to_string(),
        _ => "/".to_string(),
    }
}

fn parent_path_of_for_root(path: &str, root_path: &str) -> String {
    if path == root_path {
        return root_path.to_string();
    }
    path.rfind('/')
        .map(|idx| path[..idx].to_string())
        .filter(|parent| path_is_at_or_below(parent, root_path))
        .unwrap_or_else(|| root_path.to_string())
}

fn path_is_at_or_below(path: &str, root: &str) -> bool {
    path == root
        || (path.starts_with(root)
            && (root == "/" || path.as_bytes().get(root.len()) == Some(&b'/')))
}

fn walk_tree(
    node: &crate::model::ScanTreeNode,
    parent: Option<&str>,
    directory_by_path: &mut HashMap<String, DirectoryRecord>,
    children_by_path: &mut HashMap<String, Vec<String>>,
    entry_by_path: &HashMap<String, String>,
    entry_by_id: &HashMap<String, SnapshotEntryRecord>,
) -> (u64, u64, u64) {
    if !node.is_dir {
        // Files are indexed via entry_by_id; just register as child of parent.
        if let Some(p) = parent {
            children_by_path
                .entry(p.to_string())
                .or_default()
                .push(node.path.clone());
        }
        if let Some(entry_id) = entry_by_path.get(&node.path) {
            if let Some(entry) = entry_by_id.get(entry_id) {
                let mask = category_mask_for_name(&entry.category);
                return (
                    mask,
                    if entry.deletable { mask } else { 0 },
                    if entry.deletable { 1 } else { 0 },
                );
            }
        }
        return (0, 0, 0);
    }

    let name = node.name.clone();
    let mut category_mask = 0u64;
    let mut deletable_category_mask = 0u64;
    let mut deletable_file_count = 0u64;
    let rec = DirectoryRecord {
        parent_path: parent.map(|s| s.to_string()),
        name,
        size_bytes: node.size_bytes,
        scanned: true,
        peek_scanned: false,
        category_mask: 0,
        deletable_category_mask: 0,
        deletable_file_count: 0,
    };
    if let Some(p) = parent {
        children_by_path
            .entry(p.to_string())
            .or_default()
            .push(node.path.clone());
    }
    // Initialise an empty children vec for this dir so query_directory always
    // finds an entry even for empty dirs.
    children_by_path.entry(node.path.clone()).or_default();

    for child in &node.children {
        let (child_mask, child_deletable_mask, child_deletable_count) = walk_tree(
            child,
            Some(&node.path),
            directory_by_path,
            children_by_path,
            entry_by_path,
            entry_by_id,
        );
        category_mask |= child_mask;
        deletable_category_mask |= child_deletable_mask;
        deletable_file_count += child_deletable_count;
    }

    directory_by_path.insert(
        node.path.clone(),
        DirectoryRecord {
            category_mask,
            deletable_category_mask,
            deletable_file_count,
            ..rec
        },
    );
    (category_mask, deletable_category_mask, deletable_file_count)
}

fn passes_entry_filter(
    entry: &SnapshotEntryRecord,
    category_filter: Option<&str>,
    deletable_only: bool,
) -> bool {
    if deletable_only && !entry.deletable {
        return false;
    }
    if let Some(cat) = category_filter {
        if entry.category != cat {
            return false;
        }
    }
    true
}

fn passes_dir_filter(
    _dir: &DirectoryRecord,
    _category_filter: Option<&str>,
    _deletable_only: bool,
    _children_by_path: &HashMap<String, Vec<String>>,
    _entry_by_id: &HashMap<String, SnapshotEntryRecord>,
) -> bool {
    // For now directories always pass — filtering is applied at the file level.
    // A future pass can compute subtree category masks and apply here.
    true
}

fn apply_sort(nodes: &mut Vec<SnapshotNodeRecord>, sort_mode: &str) {
    // Dirs always before files.
    nodes.sort_by(|a, b| {
        match (a.is_directory, b.is_directory) {
            (true, false) => std::cmp::Ordering::Less,
            (false, true) => std::cmp::Ordering::Greater,
            _ => match sort_mode {
                "name" | "name_asc" => a.name.to_lowercase().cmp(&b.name.to_lowercase()),
                "size_asc" => a.size_bytes.cmp(&b.size_bytes),
                _ => b.size_bytes.cmp(&a.size_bytes), // size_desc default
            },
        }
    });
}

fn apply_entry_sort(entries: &mut Vec<SnapshotEntryRecord>, sort_mode: &str) {
    entries.sort_by(|a, b| match sort_mode {
        "name" | "name_asc" => a
            .display_name
            .to_lowercase()
            .cmp(&b.display_name.to_lowercase()),
        "size_asc" => a.size_bytes.cmp(&b.size_bytes),
        _ => b.size_bytes.cmp(&a.size_bytes),
    });
}

// ---------------------------------------------------------------------------
// Category mask helpers (mirrors Dart ScanEntryRecord.categoryMaskFor)
// ---------------------------------------------------------------------------

pub fn category_string(cat: &EntryCategory) -> &'static str {
    match cat {
        EntryCategory::Cache => "Cache",
        EntryCategory::Temp => "Temp",
        EntryCategory::Media => "Media",
        EntryCategory::AppData => "AppData",
        EntryCategory::Orphan => "Orphan",
        EntryCategory::Duplicate => "Duplicate",
        EntryCategory::System => "System",
        EntryCategory::Unknown => "Unknown",
    }
}

fn category_mask_for_name(category: &str) -> u64 {
    match category {
        "Cache" => 1 << 0,
        "Temp" => 1 << 1,
        "Media" => 1 << 2,
        "System" => 1 << 3,
        _ => 1 << 4,
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{
        CapabilityLevel, EntryCategory, RiskLevel, ScanStats, ScanTreeNode, SourceType,
        StorageEntry, StorageSnapshot,
    };

    fn build_test_snapshot() -> StorageSnapshot {
        StorageSnapshot {
            snapshot_id: "snap-1".to_string(),
            scanned_at_ms: 1,
            capability: CapabilityLevel::FullPath,
            volume_total_bytes: 0,
            volume_used_bytes: 0,
            reclaimable_estimate_bytes: 100,
            tree: ScanTreeNode {
                name: "root".to_string(),
                path: "/root".to_string(),
                is_dir: true,
                size_bytes: 100,
                entry_id: None,
                children: vec![
                    ScanTreeNode {
                        name: "Documents".to_string(),
                        path: "/root/Documents".to_string(),
                        is_dir: true,
                        size_bytes: 40,
                        entry_id: None,
                        children: vec![ScanTreeNode {
                            name: "a.txt".to_string(),
                            path: "/root/Documents/a.txt".to_string(),
                            is_dir: false,
                            size_bytes: 40,
                            entry_id: Some("e1".to_string()),
                            children: vec![],
                        }],
                    },
                    ScanTreeNode {
                        name: "Downloads".to_string(),
                        path: "/root/Downloads".to_string(),
                        is_dir: true,
                        size_bytes: 0,
                        entry_id: None,
                        children: vec![],
                    },
                ],
            },
            stats: ScanStats {
                paths_seen: 3,
                dirs_seen: 2,
                files_seen: 1,
                files_in_snapshot: 1,
                paths_skipped: 0,
                truncated: false,
                incomplete_reason: None,
            },
            warnings: vec![],
            entries: vec![StorageEntry {
                id: "e1".to_string(),
                display_name: "a.txt".to_string(),
                path_or_uri: "/root/Documents/a.txt".to_string(),
                size_bytes: 40,
                category: EntryCategory::Cache,
                risk_level: RiskLevel::Low,
                source_type: SourceType::File,
                deletable: true,
                reason: "cache".to_string(),
            }],
        }
    }

    #[test]
    fn query_directory_returns_only_direct_children_and_correct_counts() {
        let snapshot = build_test_snapshot();
        let catalog = SnapshotIndex::from(&snapshot);

        let result = catalog.query_directory("/root/Documents", None, false, "name");
        assert_eq!(result.direct_children.len(), 1, "expected 1 direct child");
        assert_eq!(result.direct_children[0].path, "/root/Documents/a.txt");
        assert_eq!(result.direct_entries.len(), 1);
        assert_eq!(result.reclaimable_bytes, 40);
        assert!(result.direct_children[0].category_mask != 0);

        let dir = catalog.directory_record("/root/Documents").unwrap();
        assert_eq!(dir.parent_path.as_deref(), Some("/root"));

        assert!(
            catalog.category_counts().contains_key("Cache"),
            "Cache count missing"
        );
        assert_eq!(catalog.reclaimable_estimate_bytes(), 100);
    }

    #[test]
    fn query_root_returns_two_direct_children() {
        let snapshot = build_test_snapshot();
        let catalog = SnapshotIndex::from(&snapshot);
        let result = catalog.query_directory("/root", None, false, "name");
        assert_eq!(result.direct_children.len(), 2);
        let names: Vec<_> = result
            .direct_children
            .iter()
            .map(|n| n.name.as_str())
            .collect();
        assert!(names.contains(&"Documents"));
        assert!(names.contains(&"Downloads"));
    }

    #[test]
    fn query_unknown_path_returns_empty() {
        let snapshot = build_test_snapshot();
        let catalog = SnapshotIndex::from(&snapshot);
        let result = catalog.query_directory("/root/nonexistent", None, false, "name");
        assert!(result.direct_children.is_empty());
    }

    #[test]
    fn refresh_directory_is_pure_query_no_scan() {
        let snapshot = build_test_snapshot();
        let catalog = SnapshotIndex::from(&snapshot);
        let q = catalog.query_directory("/root/Documents", None, false, "size_desc");
        let r = catalog.refresh_directory("/root/Documents");
        assert_eq!(q.direct_children.len(), r.direct_children.len());
        assert_eq!(q.reclaimable_bytes, r.reclaimable_bytes);
    }

    #[test]
    fn version_is_propagated_into_query_result() {
        let snapshot = build_test_snapshot();
        let catalog = SnapshotIndex::from_snapshot_with_version(&snapshot, 42);
        let result = catalog.query_directory("/root", None, false, "name");
        assert_eq!(result.version, 42);
    }
}
