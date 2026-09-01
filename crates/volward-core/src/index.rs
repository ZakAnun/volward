use std::collections::{HashMap, HashSet};

use serde::ser::{SerializeSeq, SerializeStruct};
use serde::{Deserialize, Serialize};

use crate::model::{EntryCategory, ScanStats, StorageEntry, StorageSnapshot};
use crate::string_table::StringTable;

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
/// This is the FFI-facing type — fields are owned Strings because the
/// struct crosses the FFI boundary as JSON.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SnapshotEntryRecord {
    pub id: String,
    pub path: String,
    pub parent_path: String,
    pub display_name: String,
    pub size_bytes: u64,
    pub category: String,
    pub deletable: bool,
    pub modified_at_ms: Option<i64>,
}

/// Lightweight flat file record used by capability analyzers. Produced by
/// [`SnapshotIndex::capability_files_page`] in bounded, cursor-paginated
/// pages; never clones the recursive tree.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CapabilityFileRecord {
    pub path: String,
    pub size_bytes: u64,
    /// Classified category when the file has a StorageEntry row
    /// (e.g. "Cache", "BuildArtifact"); `None` for unclassified files.
    pub category: Option<String>,
    pub deletable: bool,
    pub modified_at_ms: Option<i64>,
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
    pub stats: ScanStats,
    pub entry_count: u64,
    pub deletable_count: u64,
    pub category_counts: HashMap<String, u64>,
    pub deletable_counts: HashMap<String, u64>,
}

// ---------------------------------------------------------------------------
// Internal index records (u32-keyed, not sent over FFI)
// ---------------------------------------------------------------------------

/// Internal directory record — all string fields interned to u32 IDs.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct DirectoryRecord {
    parent: Option<u32>,
    name: u32,
    size_bytes: u64,
    scanned: bool,
    peek_scanned: bool,
    category_mask: u64,
    deletable_category_mask: u64,
    deletable_file_count: u64,
}

/// Internal entry record — all string fields interned to u32 IDs.
/// Converted to `SnapshotEntryRecord` (String fields) at query boundaries.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct EntryRecord {
    id: u32,
    path: u32,
    parent_path: u32,
    display_name: u32,
    size_bytes: u64,
    category: u32,
    deletable: bool,
    #[serde(default)]
    modified_at_ms: Option<i64>,
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
/// All internal path references use interned `u32` IDs via `StringTable`.
/// Each unique path string is stored exactly once; all HashMap keys and
/// record fields are 4-byte integers. This eliminates the 3–5× duplication
/// that occurred when paths were stored as owned Strings in multiple maps.
#[derive(Debug, Clone)]
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
    pub stats: ScanStats,

    /// String interning table — every unique path/name/category stored once.
    table: StringTable,
    /// Interned ID of `root_path`.
    root_id: u32,
    /// dir path-id → record
    directory_by_id: HashMap<u32, DirectoryRecord>,
    /// entry-id (interned "{seed}:{path}") → record
    entry_by_id: HashMap<u32, EntryRecord>,
    /// path-id → entry-id (for O(1) lookup in query_directory)
    entry_id_by_path: HashMap<u32, u32>,
    /// path-id → file size for files that are not classified StorageEntry rows.
    file_size_by_path: HashMap<u32, u64>,
    /// dir path-id → child path-ids (dirs and files, in insertion order)
    children_by_id: HashMap<u32, Vec<u32>>,
    /// ≤ 8 keys, kept as String for the public summary() API
    category_counts: HashMap<String, u64>,
    deletable_counts: HashMap<String, u64>,
}

// Custom serde: compact wire format (string table + u32 ids).
// format_version=4 adds file_size_by_path for unclassified file sizes.
// format_version=5 adds optional modified_at_ms on entry records.
// Readers also accept 2/3 (pre-size-map caches) via #[serde(default)].
impl Serialize for SnapshotIndex {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        let mut st = serializer.serialize_struct("SnapshotIndexSerde", 17)?;
        st.serialize_field("format_version", &5u32)?;
        st.serialize_field("snapshot_id", &self.snapshot_id)?;
        st.serialize_field("root_path", &self.root_path)?;
        st.serialize_field("scanned_at_ms", &self.scanned_at_ms)?;
        st.serialize_field("version", &self.version)?;
        st.serialize_field("scan_state", &self.scan_state)?;
        st.serialize_field(
            "reclaimable_estimate_bytes",
            &self.reclaimable_estimate_bytes,
        )?;
        st.serialize_field("stats", &self.stats)?;
        st.serialize_field("strings", &StringTableStrings(&self.table))?;
        st.serialize_field("root_id", &self.root_id)?;
        st.serialize_field("directories", &TupleMapEntries(&self.directory_by_id))?;
        st.serialize_field("entries", &TupleMapEntries(&self.entry_by_id))?;
        st.serialize_field("entry_id_by_path", &TupleMapEntries(&self.entry_id_by_path))?;
        st.serialize_field(
            "file_size_by_path",
            &TupleMapEntries(&self.file_size_by_path),
        )?;
        st.serialize_field("children", &TupleMapEntries(&self.children_by_id))?;
        st.serialize_field("category_counts", &self.category_counts)?;
        st.serialize_field("deletable_counts", &self.deletable_counts)?;
        st.end()
    }
}

impl<'de> Deserialize<'de> for SnapshotIndex {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        use serde::de::Error;
        let s = SnapshotIndexSerde::deserialize(deserializer)?;
        if s.format_version != 2 && s.format_version != 3 && s.format_version != 4 && s.format_version != 5 {
            return Err(D::Error::custom(format!(
                "unsupported SnapshotIndex format_version {} (expected 2, 3, 4, or 5)",
                s.format_version
            )));
        }
        if s.root_id as usize >= s.strings.len() {
            return Err(D::Error::custom(format!(
                "invalid SnapshotIndex root_id {} for {} strings",
                s.root_id,
                s.strings.len()
            )));
        }
        Ok(SnapshotIndex::from(s))
    }
}

struct StringTableStrings<'a>(&'a StringTable);

impl Serialize for StringTableStrings<'_> {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        let mut seq = serializer.serialize_seq(Some(self.0.len()))?;
        for (_, s) in self.0.iter() {
            seq.serialize_element(s)?;
        }
        seq.end()
    }
}

struct TupleMapEntries<'a, T>(&'a HashMap<u32, T>);

impl<T: Serialize> Serialize for TupleMapEntries<'_, T> {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        let mut seq = serializer.serialize_seq(Some(self.0.len()))?;
        for (k, v) in self.0 {
            seq.serialize_element(&(*k, v))?;
        }
        seq.end()
    }
}

/// Shadow struct for compact serialization.
#[derive(Serialize, Deserialize)]
struct SnapshotIndexSerde {
    format_version: u32,
    snapshot_id: String,
    root_path: String,
    scanned_at_ms: i64,
    version: u64,
    scan_state: String,
    reclaimable_estimate_bytes: u64,
    #[serde(default)]
    stats: ScanStats,
    strings: Vec<Box<str>>,
    root_id: u32,
    directories: Vec<(u32, DirectoryRecord)>,
    entries: Vec<(u32, EntryRecord)>,
    entry_id_by_path: Vec<(u32, u32)>,
    #[serde(default)]
    file_size_by_path: Vec<(u32, u64)>,
    children: Vec<(u32, Vec<u32>)>,
    category_counts: HashMap<String, u64>,
    deletable_counts: HashMap<String, u64>,
}

impl From<SnapshotIndexSerde> for SnapshotIndex {
    fn from(s: SnapshotIndexSerde) -> Self {
        let table = StringTable::from_strings(s.strings);
        let mut index = Self {
            snapshot_id: s.snapshot_id,
            root_path: s.root_path,
            scanned_at_ms: s.scanned_at_ms,
            version: s.version,
            scan_state: s.scan_state,
            reclaimable_estimate_bytes: s.reclaimable_estimate_bytes,
            stats: s.stats,
            table,
            root_id: s.root_id,
            directory_by_id: s.directories.into_iter().collect(),
            entry_by_id: s.entries.into_iter().collect(),
            entry_id_by_path: s.entry_id_by_path.into_iter().collect(),
            file_size_by_path: s.file_size_by_path.into_iter().collect(),
            children_by_id: s.children.into_iter().collect(),
            category_counts: s.category_counts,
            deletable_counts: s.deletable_counts,
        };
        index.compact_storage();
        index
    }
}

impl SnapshotIndex {
    // ------------------------------------------------------------------
    // Construction
    // ------------------------------------------------------------------

    pub fn from_snapshot(snapshot: &StorageSnapshot) -> Self {
        Self::from_snapshot_with_version(snapshot, 1)
    }

    pub fn from_snapshot_with_version(snapshot: &StorageSnapshot, version: u64) -> Self {
        let root_path = normalize_path(&snapshot.tree.path);
        let mut table = StringTable::default();
        let root_id = table.intern(&root_path);

        let mut directory_by_id: HashMap<u32, DirectoryRecord> = HashMap::new();
        let mut entry_by_id: HashMap<u32, EntryRecord> = HashMap::new();
        let mut entry_id_by_path: HashMap<u32, u32> = HashMap::new();
        let mut file_size_by_path: HashMap<u32, u64> = HashMap::new();
        let mut children_by_id: HashMap<u32, Vec<u32>> = HashMap::new();
        let mut category_counts: HashMap<String, u64> = HashMap::new();
        let mut deletable_counts: HashMap<String, u64> = HashMap::new();

        // Build entry lookup from the flat entries list.
        for entry in &snapshot.entries {
            let cat = format!("{:?}", entry.category);
            *category_counts.entry(cat.clone()).or_insert(0) += 1;
            if entry.deletable {
                *deletable_counts.entry(cat.clone()).or_insert(0) += 1;
            }
            let path = canonicalize_under_root(&entry.path_or_uri, &root_path);
            let parent_str = parent_path_of_for_root(&path, &root_path);
            let id_id = table.intern(&entry.id);
            let path_id = table.intern(&path);
            let parent_id = table.intern(&parent_str);
            let display_name_id = table.intern(&entry.display_name);
            let category_id = table.intern(&cat);

            entry_id_by_path.insert(path_id, id_id);
            entry_by_id.insert(
                id_id,
                EntryRecord {
                    id: id_id,
                    path: path_id,
                    parent_path: parent_id,
                    display_name: display_name_id,
                    size_bytes: entry.size_bytes,
                    category: category_id,
                    deletable: entry.deletable,
                    modified_at_ms: entry.modified_at_ms,
                },
            );
        }

        // Walk the tree recursively to build directory records and
        // children_by_id.
        walk_tree(
            &snapshot.tree,
            None,
            &root_path,
            &mut table,
            &mut directory_by_id,
            &mut children_by_id,
            &entry_id_by_path,
            &entry_by_id,
            &mut file_size_by_path,
        );

        let mut index = Self {
            snapshot_id: snapshot.snapshot_id.clone(),
            root_path,
            scanned_at_ms: snapshot.scanned_at_ms,
            version,
            scan_state: "Done".to_string(),
            reclaimable_estimate_bytes: snapshot.reclaimable_estimate_bytes,
            stats: snapshot.stats.clone(),
            table,
            root_id,
            directory_by_id,
            entry_by_id,
            entry_id_by_path,
            file_size_by_path,
            children_by_id,
            category_counts,
            deletable_counts,
        };
        index.compact_storage();
        index
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
                .directory_by_id
                .get(&self.root_id)
                .map(|dir| dir.size_bytes)
                .unwrap_or(0),
            scanned_at_ms: self.scanned_at_ms,
            version: self.version,
            scan_state: self.scan_state.clone(),
            reclaimable_estimate_bytes: self.reclaimable_estimate_bytes,
            stats: self.stats.clone(),
            entry_count: self.entry_by_id.len().min(u64::MAX as usize) as u64,
            deletable_count: self.deletable_counts.values().sum(),
            category_counts: self.category_counts.clone(),
            deletable_counts: self.deletable_counts.clone(),
        }
    }

    pub fn summary_json(&self) -> Result<String, String> {
        serde_json::to_string(&self.summary()).map_err(|e| format!("error:serialize: {e}"))
    }

    /// Replaces the directory subtree at `target_path` with a freshly scanned
    /// subtree (from a peek/scoped scan), and bumps the index version.
    ///
    /// This is the Rust-side counterpart of a peek-scan merge: the peek engine
    /// produces a small `StorageSnapshot` rooted at `target_path`, and instead
    /// of only updating the Dart overlay we splice that authoritative listing
    /// into the catalog so `query_directory` (which the UI reads when the
    /// index API is active) reflects the on-disk truth.
    ///
    /// Returns the new version on success, or an error string when the target
    /// is not at-or-below the index root.
    pub fn replace_directory_with_subtree(
        &mut self,
        target_path: &str,
        subtree: &crate::model::ScanTreeNode,
        subtree_entries: &[crate::model::StorageEntry],
    ) -> Result<u64, String> {
        let normalized = normalize_index_path(target_path);
        if !path_is_at_or_below(&normalized, &self.root_path) {
            return Err(format!(
                "error:target {normalized} is outside index root {}",
                self.root_path
            ));
        }
        if !subtree.is_dir || !paths_equal(&normalize_index_path(&subtree.path), &normalized) {
            return Err(format!(
                "error:subtree root {} does not match target {normalized}",
                subtree.path
            ));
        }
        let normalized = canonicalize_under_root(&normalized, &self.root_path);
        if let Some(entry) = subtree_entries
            .iter()
            .find(|entry| !path_is_at_or_below(&entry.path_or_uri, &normalized))
        {
            return Err(format!(
                "error:entry {} is outside target {normalized}",
                entry.path_or_uri
            ));
        }

        let target_id = self.table.intern(&normalized);
        let parent_id_opt = if paths_equal(&normalized, &self.root_path) {
            None
        } else {
            self.directory_by_id
                .get(&target_id)
                .and_then(|dir| dir.parent)
                .or_else(|| {
                    let parent_str = parent_path_of_for_root(&normalized, &self.root_path);
                    self.table.get_id(&parent_str)
                })
        };

        let mut old_directory_ids = HashSet::new();
        let mut old_leaf_path_ids = HashSet::new();
        let mut pending_directories = vec![target_id];
        while let Some(directory_id) = pending_directories.pop() {
            if !old_directory_ids.insert(directory_id) {
                continue;
            }
            if let Some(children) = self.children_by_id.get(&directory_id) {
                for child_id in children {
                    if self.directory_by_id.contains_key(child_id) {
                        pending_directories.push(*child_id);
                    } else {
                        old_leaf_path_ids.insert(*child_id);
                    }
                }
            }
        }
        let old_entry_ids: Vec<(u32, u32)> = old_leaf_path_ids
            .iter()
            .filter_map(|path_id| {
                self.entry_id_by_path
                    .get(path_id)
                    .copied()
                    .map(|entry_id| (entry_id, *path_id))
            })
            .collect();
        let old_file_path_ids: HashSet<u32> = old_leaf_path_ids
            .iter()
            .copied()
            .filter(|path_id| self.file_size_by_path.contains_key(path_id))
            .collect();
        let removed_child_ids: HashSet<u32> = old_directory_ids
            .iter()
            .copied()
            .chain(old_entry_ids.iter().map(|(_, path_id)| *path_id))
            .chain(old_file_path_ids.iter().copied())
            .collect();

        for directory_id in &old_directory_ids {
            self.directory_by_id.remove(directory_id);
            self.children_by_id.remove(directory_id);
        }
        for (entry_id, path_id) in &old_entry_ids {
            if let Some(entry) = self.entry_by_id.remove(entry_id) {
                let category = self.table.resolve(entry.category).to_string();
                decrement_count(&mut self.category_counts, &category);
                if entry.deletable {
                    decrement_count(&mut self.deletable_counts, &category);
                    self.reclaimable_estimate_bytes = self
                        .reclaimable_estimate_bytes
                        .saturating_sub(entry.size_bytes);
                }
            }
            self.entry_id_by_path.remove(path_id);
        }
        for path_id in &old_file_path_ids {
            self.file_size_by_path.remove(path_id);
        }
        for children in self.children_by_id.values_mut() {
            children.retain(|child_id| !removed_child_ids.contains(child_id));
        }

        // Index the subtree's classified entries first so walk_tree can resolve
        // entry metadata (category/deletable) for file leaves by path.
        for entry in subtree_entries {
            let cat = format!("{:?}", entry.category);
            *self.category_counts.entry(cat.clone()).or_insert(0) += 1;
            if entry.deletable {
                *self.deletable_counts.entry(cat.clone()).or_insert(0) += 1;
                self.reclaimable_estimate_bytes = self
                    .reclaimable_estimate_bytes
                    .saturating_add(entry.size_bytes);
            }
            let path = canonicalize_under_root(&entry.path_or_uri, &self.root_path);
            let parent_str = parent_path_of_for_root(&path, &self.root_path);
            let stable_entry_id = stable_scoped_entry_id(&path);
            let id_id = self.table.intern(&stable_entry_id);
            let path_id = self.table.intern(&path);
            let parent_id = self.table.intern(&parent_str);
            let display_name_id = self.table.intern(&entry.display_name);
            let category_id = self.table.intern(&cat);
            self.entry_id_by_path.insert(path_id, id_id);
            self.entry_by_id.insert(
                id_id,
                EntryRecord {
                    id: id_id,
                    path: path_id,
                    parent_path: parent_id,
                    display_name: display_name_id,
                    size_bytes: entry.size_bytes,
                    category: category_id,
                    deletable: entry.deletable,
                    modified_at_ms: entry.modified_at_ms,
                },
            );
        }

        let mut canonical_subtree = subtree.clone();
        canonical_subtree.path = normalized.clone();
        walk_tree(
            &canonical_subtree,
            parent_id_opt,
            &self.root_path,
            &mut self.table,
            &mut self.directory_by_id,
            &mut self.children_by_id,
            &self.entry_id_by_path,
            &self.entry_by_id,
            &mut self.file_size_by_path,
        );

        // Mark the replaced directory as authoritative (peek-scanned) so it is
        // not regressed by a later, less-complete checkpoint view.
        if let Some(dir) = self.directory_by_id.get_mut(&target_id) {
            dir.scanned = true;
            dir.peek_scanned = true;
        }

        self.stats.files_in_snapshot = self.entry_by_id.len().min(u64::MAX as usize) as u64;
        self.recompute_ancestor_aggregates(parent_id_opt);

        self.version += 1;
        Ok(self.version)
    }

    fn recompute_ancestor_aggregates(&mut self, mut directory_id: Option<u32>) {
        while let Some(current_id) = directory_id {
            let next = self
                .directory_by_id
                .get(&current_id)
                .and_then(|directory| directory.parent);
            let mut size_bytes = 0u64;
            let mut category_mask = 0u64;
            let mut deletable_category_mask = 0u64;
            let mut deletable_file_count = 0u64;

            if let Some(children) = self.children_by_id.get(&current_id) {
                for child_id in children {
                    if let Some(directory) = self.directory_by_id.get(child_id) {
                        size_bytes = size_bytes.saturating_add(directory.size_bytes);
                        category_mask |= directory.category_mask;
                        deletable_category_mask |= directory.deletable_category_mask;
                        deletable_file_count =
                            deletable_file_count.saturating_add(directory.deletable_file_count);
                    } else if let Some(entry_id) = self.entry_id_by_path.get(child_id) {
                        if let Some(entry) = self.entry_by_id.get(entry_id) {
                            size_bytes = size_bytes.saturating_add(entry.size_bytes);
                            let mask = category_mask_for_name(self.table.resolve(entry.category));
                            category_mask |= mask;
                            if entry.deletable {
                                deletable_category_mask |= mask;
                                deletable_file_count = deletable_file_count.saturating_add(1);
                            }
                        }
                    } else if let Some(file_size) = self.file_size_by_path.get(child_id) {
                        size_bytes = size_bytes.saturating_add(*file_size);
                    }
                }
            }

            if let Some(directory) = self.directory_by_id.get_mut(&current_id) {
                directory.size_bytes = size_bytes;
                directory.category_mask = category_mask;
                directory.deletable_category_mask = deletable_category_mask;
                directory.deletable_file_count = deletable_file_count;
            }
            directory_id = next;
        }
    }

    pub(crate) fn compact_storage(&mut self) {
        self.table.compact();
        self.directory_by_id.shrink_to_fit();
        self.entry_by_id.shrink_to_fit();
        self.entry_id_by_path.shrink_to_fit();
        self.file_size_by_path.shrink_to_fit();
        for children in self.children_by_id.values_mut() {
            children.shrink_to_fit();
        }
        self.children_by_id.shrink_to_fit();
        self.category_counts.shrink_to_fit();
        self.deletable_counts.shrink_to_fit();
    }

    pub fn deletable_entries_for_ids(&self, entry_ids: &[String]) -> Vec<SnapshotEntryRecord> {
        self.entries_for_ids(entry_ids)
            .into_iter()
            .filter(|entry| entry.deletable)
            .collect()
    }

    /// Returns all indexed entries matching the provided ids, regardless of
    /// their `deletable` classification.
    pub fn entries_for_ids(&self, entry_ids: &[String]) -> Vec<SnapshotEntryRecord> {
        entry_ids
            .iter()
            .filter_map(|id| self.table.get_id(id))
            .filter_map(|id_id| self.entry_by_id.get(&id_id))
            .map(|entry| self.materialize_entry(entry))
            .collect()
    }

    pub fn directory_record(&self, path: &str) -> Option<SnapshotDirectoryRecord> {
        let path_id = self.resolve_path_id(path)?;
        self.directory_by_id
            .get(&path_id)
            .map(|r| SnapshotDirectoryRecord {
                path: self.table.resolve(path_id).to_string(),
                parent_path: r.parent.map(|p| self.table.resolve(p).to_string()),
                name: self.table.resolve(r.name).to_string(),
                size_bytes: r.size_bytes,
                scanned: r.scanned,
                peek_scanned: r.peek_scanned,
            })
    }

    /// Paths that already have a Tier-1/Tier-2 `StorageEntry`.
    pub fn classified_paths(&self) -> HashSet<String> {
        self.entry_id_by_path
            .keys()
            .map(|path_id| self.table.resolve(*path_id).to_string())
            .collect()
    }

    /// Indexed entries whose category matches `category` (e.g. `"BuildArtifact"`),
    /// largest first. Used by the AI pre-check to show Tier-2 hits that are
    /// already safe to remove without asking the model.
    pub fn entries_with_category(&self, category: &str) -> Vec<SnapshotEntryRecord> {
        let Some(category_id) = self.table.get_id(category) else {
            return vec![];
        };
        let mut records: Vec<SnapshotEntryRecord> = self
            .entry_by_id
            .values()
            .filter(|entry| entry.category == category_id)
            .map(|entry| self.materialize_entry(entry))
            .collect();
        records.sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes).then(a.path.cmp(&b.path)));
        records
    }

    /// True when `path` is a directory in this index.
    pub fn is_directory(&self, path: &str) -> bool {
        self.resolve_path_id(path)
            .is_some_and(|path_id| self.directory_by_id.contains_key(&path_id))
    }

    /// Unclassified files with sizes (index `file_size_by_path`).
    pub fn unclassified_files(&self) -> Vec<(String, u64)> {
        self.file_size_by_path
            .iter()
            .filter(|(path_id, _)| !self.entry_id_by_path.contains_key(path_id))
            .map(|(path_id, size)| (self.table.resolve(*path_id).to_string(), *size))
            .collect()
    }

    /// Returns a bounded page of all flat file records (classified entries
    /// plus unclassified size records), ordered by size descending then path
    /// ascending, continuing after `cursor` (a path string). Used by
    /// capability analyzers so tens of thousands of candidates never cross
    /// the FFI boundary in one call.
    pub fn capability_files_page(
        &self,
        cursor: Option<&str>,
        page_size: usize,
    ) -> (Vec<CapabilityFileRecord>, Option<String>) {
        let page_size = page_size.max(1);
        let mut files: Vec<CapabilityFileRecord> = Vec::new();
        for entry in self.entry_by_id.values() {
            if self.directory_by_id.contains_key(&entry.path) {
                continue;
            }
            files.push(CapabilityFileRecord {
                path: self.table.resolve(entry.path).to_string(),
                size_bytes: entry.size_bytes,
                category: Some(self.table.resolve(entry.category).to_string()),
                deletable: entry.deletable,
                modified_at_ms: entry.modified_at_ms,
            });
        }
        for (path_id, size_bytes) in &self.file_size_by_path {
            if self.entry_id_by_path.contains_key(path_id)
                || self.directory_by_id.contains_key(path_id)
            {
                continue;
            }
            files.push(CapabilityFileRecord {
                path: self.table.resolve(*path_id).to_string(),
                size_bytes: *size_bytes,
                category: None,
                deletable: false,
                modified_at_ms: None,
            });
        }
        files.sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes).then(a.path.cmp(&b.path)));

        let mut page = Vec::with_capacity(page_size.min(files.len()));
        let mut next_cursor = None;
        let mut started = cursor.is_none();
        for file in files {
            if !started {
                if Some(file.path.as_str()) == cursor {
                    started = true;
                }
                continue;
            }
            if page.len() >= page_size {
                next_cursor = Some(file.path);
                break;
            }
            page.push(file);
        }
        (page, next_cursor)
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
        let empty_result = |path: &str| SnapshotQueryResult {
            snapshot_id: self.snapshot_id.clone(),
            version: self.version,
            path: path.to_string(),
            direct_children: vec![],
            direct_entries: vec![],
            total_bytes: 0,
            reclaimable_bytes: 0,
        };

        let canonical_path = if path_is_at_or_below(path, &self.root_path) {
            canonicalize_under_root(path, &self.root_path)
        } else {
            normalize_path(path)
        };
        let path_id = match self.table.get_id(&canonical_path) {
            Some(id) => id,
            None => return empty_result(&canonical_path),
        };
        let child_ids = match self.children_by_id.get(&path_id) {
            Some(v) => v,
            None => return empty_result(&canonical_path),
        };

        let mut direct_children: Vec<SnapshotNodeRecord> = Vec::new();
        let mut direct_entries: Vec<SnapshotEntryRecord> = Vec::new();
        let mut total_bytes: u64 = 0;
        let mut reclaimable_bytes: u64 = 0;

        for &child_id in child_ids {
            // Try as directory first.
            if let Some(dir) = self.directory_by_id.get(&child_id) {
                direct_children.push(SnapshotNodeRecord {
                    path: self.table.resolve(child_id).to_string(),
                    name: self.table.resolve(dir.name).to_string(),
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
            if let Some(&entry_id) = self.entry_id_by_path.get(&child_id) {
                if let Some(entry) = self.entry_by_id.get(&entry_id) {
                    let category_str = self.table.resolve(entry.category);
                    if !passes_entry_filter(entry, category_str, category_filter, deletable_only) {
                        continue;
                    }
                    total_bytes += entry.size_bytes;
                    if entry.deletable {
                        reclaimable_bytes += entry.size_bytes;
                    }
                    let mask = category_mask_for_name(category_str);
                    direct_children.push(SnapshotNodeRecord {
                        path: self.table.resolve(entry.path).to_string(),
                        name: self.table.resolve(entry.display_name).to_string(),
                        is_directory: false,
                        size_bytes: entry.size_bytes,
                        entry_id: Some(self.table.resolve(entry.id).to_string()),
                        category: Some(category_str.to_string()),
                        deletable: entry.deletable,
                        scanned: true,
                        category_mask: mask,
                        deletable_category_mask: if entry.deletable { mask } else { 0 },
                        deletable_file_count: if entry.deletable { 1 } else { 0 },
                    });
                    direct_entries.push(self.materialize_entry(entry));
                }
            }

            if let Some(size_bytes) = self.file_size_by_path.get(&child_id) {
                if category_filter.is_some() || deletable_only {
                    continue;
                }
                let path = self.table.resolve(child_id);
                direct_children.push(SnapshotNodeRecord {
                    path: path.to_string(),
                    name: name_of(path),
                    is_directory: false,
                    size_bytes: *size_bytes,
                    entry_id: Some(path.to_string()),
                    category: Some("Unknown".to_string()),
                    deletable: false,
                    scanned: true,
                    category_mask: category_mask_for_name("Unknown"),
                    deletable_category_mask: 0,
                    deletable_file_count: 0,
                });
                total_bytes += *size_bytes;
            }
        }

        // Apply sort.
        apply_sort(&mut direct_children, sort_mode);
        apply_entry_sort(&mut direct_entries, sort_mode);

        SnapshotQueryResult {
            snapshot_id: self.snapshot_id.clone(),
            version: self.version,
            path: canonical_path,
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

    fn resolve_path_id(&self, path: &str) -> Option<u32> {
        let canonical = if path_is_at_or_below(path, &self.root_path) {
            canonicalize_under_root(path, &self.root_path)
        } else {
            normalize_path(path)
        };
        self.table.get_id(&canonical)
    }

    /// Convert an internal u32-keyed EntryRecord to the FFI-facing
    /// SnapshotEntryRecord with owned Strings.
    fn materialize_entry(&self, entry: &EntryRecord) -> SnapshotEntryRecord {
        SnapshotEntryRecord {
            id: self.table.resolve(entry.id).to_string(),
            path: self.table.resolve(entry.path).to_string(),
            parent_path: self.table.resolve(entry.parent_path).to_string(),
            display_name: self.table.resolve(entry.display_name).to_string(),
            size_bytes: entry.size_bytes,
            category: self.table.resolve(entry.category).to_string(),
            deletable: entry.deletable,
            modified_at_ms: entry.modified_at_ms,
        }
    }
}

impl From<&StorageSnapshot> for SnapshotIndex {
    fn from(snapshot: &StorageSnapshot) -> Self {
        Self::from_snapshot(snapshot)
    }
}

/// Incremental builder used by the scanner to avoid materialising a recursive
/// `StorageSnapshot` before creating the catalog.
///
/// Internally uses interned u32 IDs for all path references; public method
/// signatures accept `&str` paths and convert internally.
pub struct SnapshotIndexBuilder {
    root_path: String,
    root_id: u32,
    table: StringTable,
    directory_by_id: HashMap<u32, DirectoryRecord>,
    entry_by_id: HashMap<u32, EntryRecord>,
    entry_id_by_path: HashMap<u32, u32>,
    file_size_by_path: HashMap<u32, u64>,
    children_by_id: HashMap<u32, Vec<u32>>,
    category_counts: HashMap<String, u64>,
    deletable_counts: HashMap<String, u64>,
    reclaimable_estimate_bytes: u64,
}

impl SnapshotIndexBuilder {
    pub fn new(root_path: &str) -> Self {
        let root_path = normalize_path(root_path);
        let root_name = name_of(&root_path);
        let mut table = StringTable::default();
        let root_id = table.intern(&root_path);
        let root_name_id = table.intern(&root_name);
        let mut directory_by_id = HashMap::new();
        directory_by_id.insert(
            root_id,
            DirectoryRecord {
                parent: None,
                name: root_name_id,
                size_bytes: 0,
                scanned: true,
                peek_scanned: false,
                category_mask: 0,
                deletable_category_mask: 0,
                deletable_file_count: 0,
            },
        );
        let mut children_by_id = HashMap::new();
        children_by_id.insert(root_id, Vec::new());
        Self {
            root_path,
            root_id,
            table,
            directory_by_id,
            entry_by_id: HashMap::new(),
            entry_id_by_path: HashMap::new(),
            file_size_by_path: HashMap::new(),
            children_by_id,
            category_counts: HashMap::new(),
            deletable_counts: HashMap::new(),
            reclaimable_estimate_bytes: 0,
        }
    }

    pub fn ensure_dir(&mut self, path: &str) {
        let path = canonicalize_under_root(path, &self.root_path);
        if !path_is_at_or_below(&path, &self.root_path) {
            return;
        }
        let path_id = self.table.intern(&path);
        self.ensure_dir_internal(path_id);
    }

    pub fn record_file_size(&mut self, path: &str, size_bytes: u64) {
        let path = canonicalize_under_root(path, &self.root_path);
        if !path_is_at_or_below(&path, &self.root_path) {
            return;
        }
        let parent_str = parent_path_of_for_root(&path, &self.root_path);
        let parent_id = self.table.intern(&parent_str);
        let path_id = self.table.intern(&path);
        self.ensure_dir_internal(parent_id);
        self.file_size_by_path.insert(path_id, size_bytes);
        self.add_child_once(parent_id, path_id);
        self.propagate_file_size(parent_id, size_bytes);
    }

    pub fn insert_entry(&mut self, entry: StorageEntry) {
        let path = canonicalize_under_root(&entry.path_or_uri, &self.root_path);
        if !path_is_at_or_below(&path, &self.root_path) {
            return;
        }
        let parent_str = parent_path_of_for_root(&path, &self.root_path);
        let parent_id = self.table.intern(&parent_str);
        self.ensure_dir_internal(parent_id);

        let category = category_string(&entry.category).to_string();
        let category_mask = category_mask_for_name(&category);
        *self.category_counts.entry(category.clone()).or_insert(0) += 1;
        if entry.deletable {
            *self.deletable_counts.entry(category.clone()).or_insert(0) += 1;
            self.reclaimable_estimate_bytes = self
                .reclaimable_estimate_bytes
                .saturating_add(entry.size_bytes);
        }

        let id_id = self.table.intern(&entry.id);
        let path_id = self.table.intern(&path);
        let parent_path_id = self.table.intern(&parent_str);
        let display_name_id = self.table.intern(&entry.display_name);
        let category_id = self.table.intern(&category);

        self.entry_id_by_path.insert(path_id, id_id);
        self.file_size_by_path.remove(&path_id);
        self.entry_by_id.insert(
            id_id,
            EntryRecord {
                id: id_id,
                path: path_id,
                parent_path: parent_path_id,
                display_name: display_name_id,
                size_bytes: entry.size_bytes,
                category: category_id,
                deletable: entry.deletable,
                modified_at_ms: entry.modified_at_ms,
            },
        );
        self.add_child_once(parent_id, path_id);
        self.propagate_entry_metadata(parent_id, category_mask, entry.deletable);
    }

    pub fn graft_directory_from_index(&mut self, source: &SnapshotIndex, dir_path: &str) {
        let dir_path = canonicalize_under_root(dir_path, &self.root_path);
        if !path_is_at_or_below(&dir_path, &self.root_path) {
            return;
        }
        let Some(source_dir_id) = source.resolve_path_id(&dir_path) else {
            return;
        };
        let Some(source_dir) = source.directory_by_id.get(&source_dir_id).cloned() else {
            return;
        };

        let dir_path_id = self.table.intern(&dir_path);
        let parent_id = if paths_equal(&dir_path, &self.root_path) {
            None
        } else {
            let parent_str = parent_path_of_for_root(&dir_path, &self.root_path);
            let pid = self.table.intern(&parent_str);
            self.ensure_dir_internal(pid);
            self.add_child_once(pid, dir_path_id);
            Some(pid)
        };

        // Collect all directory IDs from the source that are under dir_path.
        // We must re-intern each path into our table since IDs differ across tables.
        let mut dir_pairs: Vec<(u32, u32)> = Vec::new(); // (source_id, our_id)
        for &src_id in source.directory_by_id.keys() {
            let src_path = source.table.resolve(src_id);
            if path_is_at_or_below(src_path, &dir_path) {
                let our_id = self.table.intern(src_path);
                dir_pairs.push((src_id, our_id));
            }
        }
        // Sort by path length so parents are processed before children.
        dir_pairs.sort_by_key(|(src_id, _)| source.table.resolve(*src_id).len());

        for (src_id, our_id) in &dir_pairs {
            if let Some(record) = source.directory_by_id.get(src_id) {
                let parent = record
                    .parent
                    .map(|p| self.table.intern(source.table.resolve(p)));
                let name = self.table.intern(source.table.resolve(record.name));
                self.directory_by_id.insert(
                    *our_id,
                    DirectoryRecord {
                        parent,
                        name,
                        size_bytes: record.size_bytes,
                        scanned: record.scanned,
                        peek_scanned: record.peek_scanned,
                        category_mask: record.category_mask,
                        deletable_category_mask: record.deletable_category_mask,
                        deletable_file_count: record.deletable_file_count,
                    },
                );
            }
            if let Some(children) = source.children_by_id.get(src_id) {
                let our_children: Vec<u32> = children
                    .iter()
                    .map(|&child_src_id| {
                        let child_path = source.table.resolve(child_src_id);
                        self.table.intern(child_path)
                    })
                    .collect();
                self.children_by_id.insert(*our_id, our_children);
            }
        }

        // Graft entries under dir_path.
        for entry in source.entry_by_id.values() {
            let entry_path = source.table.resolve(entry.path);
            if !path_is_at_or_below(entry_path, &dir_path) {
                continue;
            }
            let category_str = source.table.resolve(entry.category).to_string();
            *self
                .category_counts
                .entry(category_str.clone())
                .or_insert(0) += 1;
            if entry.deletable {
                *self.deletable_counts.entry(category_str).or_insert(0) += 1;
                self.reclaimable_estimate_bytes = self
                    .reclaimable_estimate_bytes
                    .saturating_add(entry.size_bytes);
            }
            let id_id = self.table.intern(source.table.resolve(entry.id));
            let path_id = self.table.intern(entry_path);
            let parent_path_id = self.table.intern(source.table.resolve(entry.parent_path));
            let display_name_id = self.table.intern(source.table.resolve(entry.display_name));
            let category_id = self.table.intern(source.table.resolve(entry.category));

            self.entry_id_by_path.insert(path_id, id_id);
            self.entry_by_id.insert(
                id_id,
                EntryRecord {
                    id: id_id,
                    path: path_id,
                    parent_path: parent_path_id,
                    display_name: display_name_id,
                    size_bytes: entry.size_bytes,
                    category: category_id,
                    deletable: entry.deletable,
                    modified_at_ms: entry.modified_at_ms,
                },
            );
        }

        for (&path_id, &size_bytes) in &source.file_size_by_path {
            let path = source.table.resolve(path_id);
            if !path_is_at_or_below(path, &dir_path) {
                continue;
            }
            let our_path_id = self.table.intern(path);
            self.file_size_by_path.insert(our_path_id, size_bytes);
        }

        if let Some(parent_id) = parent_id {
            self.propagate_grafted_directory_to_ancestors(parent_id, &source_dir);
        }
    }

    pub fn finish(
        self,
        snapshot_id: String,
        scanned_at_ms: i64,
        version: u64,
        scan_state: String,
        stats: ScanStats,
    ) -> SnapshotIndex {
        let mut index = SnapshotIndex {
            snapshot_id,
            root_path: self.root_path,
            scanned_at_ms,
            version,
            scan_state,
            reclaimable_estimate_bytes: self.reclaimable_estimate_bytes,
            stats,
            table: self.table,
            root_id: self.root_id,
            directory_by_id: self.directory_by_id,
            entry_by_id: self.entry_by_id,
            entry_id_by_path: self.entry_id_by_path,
            file_size_by_path: self.file_size_by_path,
            children_by_id: self.children_by_id,
            category_counts: self.category_counts,
            deletable_counts: self.deletable_counts,
        };
        index.compact_storage();
        index
    }

    fn ensure_dir_internal(&mut self, path_id: u32) {
        if self.directory_by_id.contains_key(&path_id) {
            return;
        }
        if path_id == self.root_id {
            return;
        }

        let path_str = self.table.resolve(path_id).to_string();
        if paths_equal(&path_str, &self.root_path) {
            return;
        }
        let parent_str = parent_path_of_for_root(&path_str, &self.root_path);
        let parent_id = self.table.intern(&parent_str);
        self.ensure_dir_internal(parent_id);

        let name_id = {
            let name = name_of(&path_str);
            self.table.intern(&name)
        };

        self.directory_by_id.insert(
            path_id,
            DirectoryRecord {
                parent: Some(parent_id),
                name: name_id,
                size_bytes: 0,
                scanned: true,
                peek_scanned: false,
                category_mask: 0,
                deletable_category_mask: 0,
                deletable_file_count: 0,
            },
        );
        self.children_by_id.entry(path_id).or_default();
        self.add_child_once(parent_id, path_id);
    }

    fn add_child_once(&mut self, parent_id: u32, child_id: u32) {
        let children = self.children_by_id.entry(parent_id).or_default();
        if !children.contains(&child_id) {
            children.push(child_id);
        }
    }

    fn propagate_file_size(&mut self, parent_id: u32, size_bytes: u64) {
        let mut current = Some(parent_id);
        while let Some(pid) = current {
            let next = self.directory_by_id.get(&pid).and_then(|dir| dir.parent);
            if let Some(dir) = self.directory_by_id.get_mut(&pid) {
                dir.size_bytes = dir.size_bytes.saturating_add(size_bytes);
            }
            current = next;
        }
    }

    fn propagate_entry_metadata(&mut self, parent_id: u32, category_mask: u64, deletable: bool) {
        let mut current = Some(parent_id);
        while let Some(pid) = current {
            let next = self.directory_by_id.get(&pid).and_then(|dir| dir.parent);
            if let Some(dir) = self.directory_by_id.get_mut(&pid) {
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
        parent_id: u32,
        source_dir: &DirectoryRecord,
    ) {
        let mut current = Some(parent_id);
        while let Some(pid) = current {
            let next = self.directory_by_id.get(&pid).and_then(|dir| dir.parent);
            if let Some(dir) = self.directory_by_id.get_mut(&pid) {
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

fn normalize_path(path: &str) -> String {
    let normalized = path.replace('\\', "/");
    if is_unc_path(&normalized) {
        let trimmed = normalized.trim_end_matches('/');
        if trimmed == "/" || trimmed.is_empty() {
            return normalized;
        }
        if unc_share_root(trimmed).as_deref() == Some(trimmed) {
            return trimmed.to_string();
        }
        return trimmed.trim_end_matches('/').to_string();
    }
    if normalized.len() > 1 && normalized.ends_with('/') && !is_windows_drive_root(&normalized) {
        normalized[..normalized.len() - 1].to_string()
    } else if path.is_empty() {
        "/".to_string()
    } else {
        normalized
    }
}

fn name_of(path: &str) -> String {
    path.rsplit('/')
        .next()
        .filter(|s| !s.is_empty())
        .unwrap_or(path)
        .to_string()
}

#[cfg(test)]
fn parent_path_of(path: &str) -> String {
    let path = normalize_path(path);
    if let Some(share) = unc_share_root(&path) {
        if paths_equal(&share, &path) {
            return share;
        }
    }
    match path.rfind('/') {
        Some(2) if has_windows_drive_prefix(&path) => path[..3].to_string(),
        Some(i) if i > 0 => path[..i].to_string(),
        _ => {
            if is_windows_drive_root(&path) {
                path
            } else {
                "/".to_string()
            }
        }
    }
}

fn parent_path_of_for_root(path: &str, root_path: &str) -> String {
    let path = canonicalize_under_root(path, root_path);
    let root_path = normalize_path(root_path);
    if paths_equal(&path, &root_path) {
        return root_path;
    }
    if is_windows_drive_root(&root_path) {
        return path
            .rfind('/')
            .map(|idx| {
                let parent = &path[..idx];
                if paths_equal(parent, &root_path[..root_path.len() - 1]) {
                    root_path.clone()
                } else {
                    canonicalize_under_root(parent, &root_path)
                }
            })
            .unwrap_or(root_path);
    }
    if unc_share_root(&root_path).is_some() {
        return path
            .rfind('/')
            .map(|idx| {
                let parent = &path[..idx];
                if paths_equal(parent, &root_path) {
                    root_path.clone()
                } else if path_is_at_or_below(parent, &root_path) {
                    canonicalize_under_root(parent, &root_path)
                } else {
                    root_path.clone()
                }
            })
            .unwrap_or(root_path);
    }
    path.rfind('/')
        .map(|idx| path[..idx].to_string())
        .filter(|parent| path_is_at_or_below(parent, &root_path))
        .unwrap_or(root_path)
}

fn canonicalize_under_root(path: &str, root_path: &str) -> String {
    let path = normalize_path(path);
    let root_path = normalize_path(root_path);
    if !path_is_at_or_below(&path, &root_path) {
        return path;
    }
    if path.len() == root_path.len() {
        return root_path;
    }
    format!("{root_path}{}", &path[root_path.len()..])
}

fn stable_scoped_entry_id(path: &str) -> String {
    format!("path:{path}")
}

fn decrement_count(counts: &mut HashMap<String, u64>, category: &str) {
    if let Some(count) = counts.get_mut(category) {
        *count = count.saturating_sub(1);
        if *count == 0 {
            counts.remove(category);
        }
    }
}

fn is_windows_style_path(path: &str) -> bool {
    has_windows_drive_prefix(path) || path.starts_with("//")
}

fn paths_equal(left: &str, right: &str) -> bool {
    if is_windows_style_path(left) || is_windows_style_path(right) {
        left.eq_ignore_ascii_case(right)
    } else {
        left == right
    }
}

pub(crate) fn path_is_at_or_below(path: &str, root: &str) -> bool {
    let path = normalize_path(path);
    let root = normalize_path(root);
    if root.is_empty() {
        return false;
    }
    let windows_style = is_windows_style_path(&path) || is_windows_style_path(&root);
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

#[allow(clippy::too_many_arguments)]
fn walk_tree(
    node: &crate::model::ScanTreeNode,
    parent: Option<u32>,
    root_path: &str,
    table: &mut StringTable,
    directory_by_id: &mut HashMap<u32, DirectoryRecord>,
    children_by_id: &mut HashMap<u32, Vec<u32>>,
    entry_id_by_path: &HashMap<u32, u32>,
    entry_by_id: &HashMap<u32, EntryRecord>,
    file_size_by_path: &mut HashMap<u32, u64>,
) -> (u64, u64, u64) {
    let node_path = canonicalize_under_root(&node.path, root_path);
    let node_path_id = table.intern(&node_path);

    if !node.is_dir {
        // Files are indexed via entry_by_id; just register as child of parent.
        if let Some(p) = parent {
            children_by_id.entry(p).or_default().push(node_path_id);
        }
        if let Some(&entry_id) = entry_id_by_path.get(&node_path_id) {
            if let Some(entry) = entry_by_id.get(&entry_id) {
                let cat_str = table.resolve(entry.category);
                let mask = category_mask_for_name(cat_str);
                return (
                    mask,
                    if entry.deletable { mask } else { 0 },
                    if entry.deletable { 1 } else { 0 },
                );
            }
        } else {
            file_size_by_path.insert(node_path_id, node.size_bytes);
        }
        return (0, 0, 0);
    }

    let name_id = table.intern(&node.name);
    let mut category_mask = 0u64;
    let mut deletable_category_mask = 0u64;
    let mut deletable_file_count = 0u64;

    if let Some(p) = parent {
        children_by_id.entry(p).or_default().push(node_path_id);
    }
    // Initialise an empty children vec for this dir so query_directory always
    // finds an entry even for empty dirs.
    children_by_id.entry(node_path_id).or_default();

    for child in &node.children {
        let (child_mask, child_deletable_mask, child_deletable_count) = walk_tree(
            child,
            Some(node_path_id),
            root_path,
            table,
            directory_by_id,
            children_by_id,
            entry_id_by_path,
            entry_by_id,
            file_size_by_path,
        );
        category_mask |= child_mask;
        deletable_category_mask |= child_deletable_mask;
        deletable_file_count += child_deletable_count;
    }

    directory_by_id.insert(
        node_path_id,
        DirectoryRecord {
            parent,
            name: name_id,
            size_bytes: node.size_bytes,
            scanned: true,
            peek_scanned: false,
            category_mask,
            deletable_category_mask,
            deletable_file_count,
        },
    );
    (category_mask, deletable_category_mask, deletable_file_count)
}

/// Normalises an index path: strips a single trailing slash (except for the
/// filesystem root "/") so catalog keys agree on the canonical form.
fn normalize_index_path(path: &str) -> String {
    let normalized = normalize_path(path);
    if normalized.len() > 1 && normalized.ends_with('/') && !is_windows_drive_root(&normalized) {
        normalized[..normalized.len() - 1].to_string()
    } else {
        normalized
    }
}

fn has_windows_drive_prefix(path: &str) -> bool {
    let bytes = path.as_bytes();
    bytes.len() >= 3 && bytes[1] == b':' && bytes[2] == b'/' && bytes[0].is_ascii_alphabetic()
}

fn is_windows_drive_root(path: &str) -> bool {
    let bytes = path.as_bytes();
    bytes.len() == 3 && bytes[1] == b':' && bytes[2] == b'/' && bytes[0].is_ascii_alphabetic()
}

fn passes_entry_filter(
    entry: &EntryRecord,
    category_str: &str,
    category_filter: Option<&str>,
    deletable_only: bool,
) -> bool {
    if deletable_only && !entry.deletable {
        return false;
    }
    if let Some(cat) = category_filter {
        if category_str != cat {
            return false;
        }
    }
    true
}

fn apply_sort(nodes: &mut [SnapshotNodeRecord], sort_mode: &str) {
    // Dirs always before files.
    nodes.sort_by(|a, b| {
        let primary = match (a.is_directory, b.is_directory) {
            (true, false) => std::cmp::Ordering::Less,
            (false, true) => std::cmp::Ordering::Greater,
            _ => match sort_mode {
                "name" | "name_asc" => a.name.to_lowercase().cmp(&b.name.to_lowercase()),
                "size_asc" => a.size_bytes.cmp(&b.size_bytes),
                _ => b.size_bytes.cmp(&a.size_bytes), // size_desc default
            },
        };
        primary.then_with(|| {
            a.name
                .to_lowercase()
                .cmp(&b.name.to_lowercase())
                .then_with(|| a.path.cmp(&b.path))
        })
    });
}

fn apply_entry_sort(entries: &mut [SnapshotEntryRecord], sort_mode: &str) {
    entries.sort_by(|a, b| {
        let primary = match sort_mode {
            "name" | "name_asc" => a
                .display_name
                .to_lowercase()
                .cmp(&b.display_name.to_lowercase()),
            "size_asc" => a.size_bytes.cmp(&b.size_bytes),
            _ => b.size_bytes.cmp(&a.size_bytes),
        };
        primary.then_with(|| {
            a.display_name
                .to_lowercase()
                .cmp(&b.display_name.to_lowercase())
                .then_with(|| a.path.cmp(&b.path))
        })
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
        EntryCategory::BuildArtifact => "BuildArtifact",
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
            reclaimable_estimate_bytes: 40,
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
                modified_at_ms: None,
            }],
        }
    }

    fn replacement_tree(name: &str, size_bytes: u64) -> ScanTreeNode {
        ScanTreeNode {
            name: "Documents".to_string(),
            path: "/root/Documents".to_string(),
            is_dir: true,
            size_bytes,
            entry_id: None,
            children: vec![ScanTreeNode {
                name: name.to_string(),
                path: format!("/root/Documents/{name}"),
                is_dir: false,
                size_bytes,
                entry_id: Some(format!("peek:{name}")),
                children: vec![],
            }],
        }
    }

    fn replacement_entry(
        id: &str,
        name: &str,
        size_bytes: u64,
        category: EntryCategory,
        deletable: bool,
    ) -> StorageEntry {
        StorageEntry {
            id: id.to_string(),
            display_name: name.to_string(),
            path_or_uri: format!("/root/Documents/{name}"),
            size_bytes,
            category,
            risk_level: RiskLevel::Low,
            source_type: SourceType::File,
            deletable,
            reason: "replacement".to_string(),
            modified_at_ms: None,
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
        assert_eq!(catalog.reclaimable_estimate_bytes(), 40);
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
    fn replacing_subtree_removes_old_records_and_rebuilds_summaries() {
        let mut catalog = SnapshotIndex::from(&build_test_snapshot());
        let tree = replacement_tree("b.tmp", 25);
        let entry = replacement_entry("peek-1", "b.tmp", 25, EntryCategory::Temp, false);

        catalog
            .replace_directory_with_subtree("/root/Documents", &tree, &[entry])
            .unwrap();

        let documents = catalog.query_directory("/root/Documents", None, false, "name");
        assert_eq!(documents.direct_children.len(), 1);
        assert_eq!(documents.direct_children[0].name, "b.tmp");
        assert!(catalog.entries_for_ids(&["e1".to_string()]).is_empty());
        assert_eq!(catalog.entry_by_id.len(), 1);
        assert_eq!(catalog.category_counts.get("Cache"), None);
        assert_eq!(catalog.category_counts.get("Temp"), Some(&1));
        assert!(catalog.deletable_counts.is_empty());
        assert_eq!(catalog.reclaimable_estimate_bytes, 0);
        assert_eq!(catalog.stats.files_in_snapshot, 1);
        assert_eq!(
            catalog.directory_record("/root").unwrap().size_bytes,
            25,
            "ancestor size must reflect the fresh subtree"
        );
    }

    #[test]
    fn repeated_subtree_replacement_is_idempotent_and_uses_stable_entry_ids() {
        let mut catalog = SnapshotIndex::from(&build_test_snapshot());
        let tree = replacement_tree("b.tmp", 25);

        catalog
            .replace_directory_with_subtree(
                "/root/Documents",
                &tree,
                &[replacement_entry(
                    "peek-1",
                    "b.tmp",
                    25,
                    EntryCategory::Temp,
                    true,
                )],
            )
            .unwrap();
        let first = catalog.query_directory("/root/Documents", None, false, "name");
        let first_entry_id = first.direct_children[0].entry_id.clone();
        assert_eq!(
            first_entry_id.as_deref(),
            Some("path:/root/Documents/b.tmp")
        );
        let first_string_count = catalog.table.len();

        catalog
            .replace_directory_with_subtree(
                "/root/Documents",
                &tree,
                &[replacement_entry(
                    "peek-2",
                    "b.tmp",
                    25,
                    EntryCategory::Temp,
                    true,
                )],
            )
            .unwrap();
        let second = catalog.query_directory("/root/Documents", None, false, "name");

        assert_eq!(second.direct_children.len(), 1);
        assert_eq!(second.direct_entries.len(), 1);
        assert_eq!(second.direct_children[0].entry_id, first_entry_id);
        assert_eq!(catalog.entry_by_id.len(), 1);
        assert_eq!(catalog.category_counts.get("Temp"), Some(&1));
        assert_eq!(catalog.deletable_counts.get("Temp"), Some(&1));
        assert_eq!(catalog.reclaimable_estimate_bytes, 25);
        assert_eq!(catalog.table.len(), first_string_count);
    }

    #[test]
    fn subtree_replacement_does_not_duplicate_unknown_and_classified_files() {
        let mut catalog = SnapshotIndex::from(&build_test_snapshot());
        let tree = replacement_tree("index.js", 10);

        catalog
            .replace_directory_with_subtree("/root/Documents", &tree, &[])
            .unwrap();
        let unknown = catalog.query_directory("/root/Documents", None, false, "name");
        assert_eq!(unknown.direct_children.len(), 1);
        assert_eq!(
            unknown.direct_children[0].category.as_deref(),
            Some("Unknown")
        );

        catalog
            .replace_directory_with_subtree(
                "/root/Documents",
                &tree,
                &[replacement_entry(
                    "peek-classified",
                    "index.js",
                    10,
                    EntryCategory::AppData,
                    false,
                )],
            )
            .unwrap();
        let classified = catalog.query_directory("/root/Documents", None, false, "name");
        assert_eq!(classified.direct_children.len(), 1);
        assert_eq!(classified.direct_entries.len(), 1);
        assert_eq!(
            classified.direct_children[0].category.as_deref(),
            Some("AppData")
        );
        assert!(catalog.file_size_by_path.is_empty());
    }

    #[test]
    fn size_sort_uses_name_as_a_stable_tie_breaker() {
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.ensure_dir("/root/zeta");
        builder.ensure_dir("/root/alpha");
        let index = builder.finish(
            "snap-ties".to_string(),
            1,
            1,
            "Done".to_string(),
            ScanStats {
                paths_seen: 3,
                dirs_seen: 2,
                files_seen: 0,
                files_in_snapshot: 0,
                paths_skipped: 0,
                truncated: false,
                incomplete_reason: None,
            },
        );

        let result = index.query_directory("/root", None, false, "size_desc");
        let names: Vec<_> = result
            .direct_children
            .iter()
            .map(|node| node.name.as_str())
            .collect();
        assert_eq!(names, ["alpha", "zeta"]);
    }

    #[test]
    fn query_unknown_path_returns_empty() {
        let snapshot = build_test_snapshot();
        let catalog = SnapshotIndex::from(&snapshot);
        let result = catalog.query_directory("/root/nonexistent", None, false, "name");
        assert!(result.direct_children.is_empty());
    }

    #[test]
    fn query_directory_returns_unclassified_files_as_unknown_nodes() {
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.ensure_dir("/root/fastbuild");
        builder.record_file_size("/root/fastbuild/index.js", 6_717);
        builder.record_file_size("/root/fastbuild/content.js", 3_671);
        let index = builder.finish(
            "snap-js".to_string(),
            1,
            1,
            "Done".to_string(),
            ScanStats {
                paths_seen: 3,
                dirs_seen: 1,
                files_seen: 2,
                files_in_snapshot: 0,
                paths_skipped: 0,
                truncated: false,
                incomplete_reason: None,
            },
        );

        let result = index.query_directory("/root/fastbuild", None, false, "name");
        assert_eq!(result.direct_children.len(), 2);
        assert_eq!(result.direct_children[0].path, "/root/fastbuild/content.js");
        assert_eq!(
            result.direct_children[0].entry_id.as_deref(),
            Some("/root/fastbuild/content.js")
        );
        assert_eq!(
            result.direct_children[0].category.as_deref(),
            Some("Unknown")
        );
        assert!(!result.direct_children[0].deletable);
        assert!(result.direct_entries.is_empty());
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

    #[test]
    fn serde_roundtrip_preserves_data() {
        let snapshot = build_test_snapshot();
        let catalog = SnapshotIndex::from(&snapshot);

        let json = serde_json::to_string(&catalog).expect("serialize");
        let loaded: SnapshotIndex = serde_json::from_str(&json).expect("deserialize");

        assert_eq!(loaded.snapshot_id, catalog.snapshot_id);
        assert_eq!(loaded.root_path, catalog.root_path);
        assert_eq!(loaded.version, catalog.version);
        assert_eq!(loaded.scan_state, catalog.scan_state);
        assert_eq!(
            loaded.reclaimable_estimate_bytes,
            catalog.reclaimable_estimate_bytes
        );
        assert_eq!(loaded.entry_by_id.len(), catalog.entry_by_id.len());
        assert_eq!(loaded.directory_by_id.len(), catalog.directory_by_id.len());

        // Query should produce identical results.
        let result_orig = catalog.query_directory("/root", None, false, "name");
        let result_loaded = loaded.query_directory("/root", None, false, "name");
        assert_eq!(
            result_orig.direct_children.len(),
            result_loaded.direct_children.len()
        );
        assert_eq!(result_orig.total_bytes, result_loaded.total_bytes);

        // Entry detail should match.
        let entries_orig = catalog.deletable_entries_for_ids(&["e1".to_string()]);
        let entries_loaded = loaded.deletable_entries_for_ids(&["e1".to_string()]);
        assert_eq!(entries_orig.len(), entries_loaded.len());
        assert_eq!(entries_orig[0].path, entries_loaded[0].path);
    }

    #[test]
    fn builder_produces_same_results_as_from_snapshot() {
        // Build via builder.
        let mut builder = SnapshotIndexBuilder::new("/root");
        builder.ensure_dir("/root/Documents");
        builder.ensure_dir("/root/Downloads");
        builder.record_file_size("/root/Documents/a.txt", 40);
        builder.insert_entry(StorageEntry {
            id: "e1".to_string(),
            display_name: "a.txt".to_string(),
            path_or_uri: "/root/Documents/a.txt".to_string(),
            size_bytes: 40,
            category: EntryCategory::Cache,
            risk_level: RiskLevel::Low,
            source_type: SourceType::File,
            deletable: true,
            reason: "cache".to_string(),
            modified_at_ms: None,
        });
        let index = builder.finish(
            "snap-1".to_string(),
            1,
            1,
            "Done".to_string(),
            ScanStats {
                paths_seen: 3,
                dirs_seen: 2,
                files_seen: 1,
                files_in_snapshot: 1,
                paths_skipped: 0,
                truncated: false,
                incomplete_reason: None,
            },
        );

        // Build via from_snapshot.
        let snapshot = build_test_snapshot();
        let from_snap = SnapshotIndex::from(&snapshot);

        // Both should produce the same query results.
        let r1 = index.query_directory("/root", None, false, "name");
        let r2 = from_snap.query_directory("/root", None, false, "name");
        assert_eq!(r1.direct_children.len(), r2.direct_children.len());

        let r1 = index.query_directory("/root/Documents", None, false, "name");
        let r2 = from_snap.query_directory("/root/Documents", None, false, "name");
        assert_eq!(r1.direct_children.len(), r2.direct_children.len());
        assert_eq!(r1.reclaimable_bytes, r2.reclaimable_bytes);
    }

    #[test]
    fn parent_path_of_drive_root_child_returns_drive_root() {
        assert_eq!(parent_path_of("C:/file.txt"), "C:/");
        assert_eq!(parent_path_of("C:/Users"), "C:/");
        assert_eq!(parent_path_of(r"C:\Users\me\a.txt"), "C:/Users/me");
        assert_eq!(parent_path_of("C:/"), "C:/");
    }

    #[test]
    fn parent_path_of_handles_unc() {
        assert_eq!(normalize_path(r"\\server\share\a\b"), "//server/share/a/b");
        assert_eq!(normalize_path("//server/share/"), "//server/share");
        assert_eq!(normalize_path("//server/share///"), "//server/share");
        assert_eq!(
            parent_path_of(r"\\server\share\a\b.txt"),
            "//server/share/a"
        );
        assert_eq!(parent_path_of("//server/share/a"), "//server/share");
        assert_eq!(parent_path_of("//server/share"), "//server/share");
    }

    #[test]
    fn path_is_at_or_below_rejects_unc_false_prefix() {
        assert!(!path_is_at_or_below(
            "//server/shareextra",
            "//server/share"
        ));
        assert!(path_is_at_or_below("//server/share/a", "//server/share"));
        assert_eq!(
            parent_path_of_for_root("//server/shareextra/foo", "//server/share"),
            "//server/share"
        );
    }

    #[test]
    fn path_is_at_or_below_is_case_insensitive_for_windows_paths() {
        assert!(path_is_at_or_below("c:/Users/me/a.txt", "C:/Users/me"));
        assert!(path_is_at_or_below(
            "//SERVER/Share/folder/a.txt",
            "//server/share"
        ));
        assert!(!path_is_at_or_below("c:/Users/media", "C:/Users/me"));
    }

    #[test]
    fn insert_entry_normalizes_path_before_intern() {
        let mut builder = SnapshotIndexBuilder::new(r"C:\Users\me");
        builder.insert_entry(StorageEntry {
            id: "e1".to_string(),
            display_name: "a.txt".to_string(),
            path_or_uri: r"C:\Users\me\docs\a.txt".to_string(),
            size_bytes: 10,
            category: EntryCategory::Cache,
            risk_level: RiskLevel::Low,
            source_type: SourceType::File,
            deletable: true,
            reason: "cache".to_string(),
            modified_at_ms: None,
        });
        let index = builder.finish(
            "snap".to_string(),
            1,
            1,
            "Done".to_string(),
            ScanStats {
                paths_seen: 1,
                dirs_seen: 1,
                files_seen: 1,
                files_in_snapshot: 1,
                paths_skipped: 0,
                truncated: false,
                incomplete_reason: None,
            },
        );
        let result = index.query_directory("C:/Users/me/docs", None, false, "size_desc");
        assert_eq!(result.direct_entries.len(), 1);
        assert_eq!(result.direct_entries[0].path, "C:/Users/me/docs/a.txt");
    }

    #[test]
    fn insert_entry_canonicalizes_windows_casing_without_shadow_dirs() {
        let mut builder = SnapshotIndexBuilder::new("C:/Users/me");
        builder.insert_entry(StorageEntry {
            id: "e1".to_string(),
            display_name: "a.txt".to_string(),
            path_or_uri: "c:/Users/me/docs/a.txt".to_string(),
            size_bytes: 10,
            category: EntryCategory::Cache,
            risk_level: RiskLevel::Low,
            source_type: SourceType::File,
            deletable: true,
            reason: "cache".to_string(),
            modified_at_ms: None,
        });
        let index = builder.finish(
            "snap".to_string(),
            1,
            1,
            "Done".to_string(),
            ScanStats {
                paths_seen: 1,
                dirs_seen: 1,
                files_seen: 1,
                files_in_snapshot: 1,
                paths_skipped: 0,
                truncated: false,
                incomplete_reason: None,
            },
        );
        let root = index.query_directory("c:/Users/me", None, false, "name");
        assert_eq!(root.path, "C:/Users/me");
        assert!(root
            .direct_children
            .iter()
            .all(|child| !child.path.eq_ignore_ascii_case("c:/Users/me")));
        assert!(root
            .direct_children
            .iter()
            .any(|child| child.path == "C:/Users/me/docs"));
        let docs = index.query_directory("c:/Users/me/docs", None, false, "name");
        assert_eq!(docs.direct_entries.len(), 1);
        assert_eq!(docs.direct_entries[0].path, "C:/Users/me/docs/a.txt");
    }
}
