use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::model::{EntryCategory, StorageSnapshot};

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

// ---------------------------------------------------------------------------
// Internal index records (not sent over FFI — held inside SnapshotIndex)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
struct DirectoryRecord {
    path: String,
    parent_path: Option<String>,
    name: String,
    size_bytes: u64,
    scanned: bool,
    peek_scanned: bool,
    /// Ordered list of direct child paths (dirs first, then files).
    child_paths: Vec<String>,
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

    pub fn directory_record(&self, path: &str) -> Option<SnapshotDirectoryRecord> {
        self.directory_by_path
            .get(path)
            .map(|r| SnapshotDirectoryRecord {
                path: r.path.clone(),
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
                    path: dir.path.clone(),
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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn parent_path_of(path: &str) -> String {
    match path.rfind('/') {
        Some(i) if i > 0 => path[..i].to_string(),
        _ => "/".to_string(),
    }
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
        path: node.path.clone(),
        parent_path: parent.map(|s| s.to_string()),
        name,
        size_bytes: node.size_bytes,
        scanned: true,
        peek_scanned: false,
        child_paths: node.children.iter().map(|c| c.path.clone()).collect(),
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
