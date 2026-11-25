use super::*;

impl VolwardEngine {
    pub(super) fn current_index(&self) -> Option<Arc<SnapshotIndex>> {
        self.last_index.lock().ok().and_then(|guard| guard.clone())
    }

    // ------------------------------------------------------------------
    // Catalog index queries (Design §5.3 — Dart calls these over FFI)
    // ------------------------------------------------------------------

    /// Re-query the existing index for `path` — pure in-memory, no scan.
    /// This is the implementation of Design §7.2 "current directory refresh".
    pub fn refresh_directory(&self, path: &str) -> Result<String, String> {
        let guard = self.last_index.lock().map_err(|e| format!("lock: {e}"))?;
        let index = guard
            .as_ref()
            .ok_or_else(|| "error:no index loaded".to_string())?;
        index.refresh_directory_json(path)
    }

    /// Splices a freshly scanned subtree (from a peek/scoped scan) into the
    /// catalog index, replacing the directory at `target_path`, and bumps the
    /// index version so Dart-side caches invalidate.
    ///
    /// This is what makes a peek refresh visible to the UI when the index API
    /// is active: previously the peek result only updated the Dart overlay,
    /// while `query_directory` kept reading the stale catalog.
    pub fn replace_directory_with_subtree_json(
        &self,
        target_path: &str,
        subtree_json: &str,
    ) -> Result<u64, String> {
        #[derive(serde::Deserialize)]
        struct SubtreePayload {
            tree: volward_core::model::ScanTreeNode,
            #[serde(default)]
            entries: Vec<volward_core::model::StorageEntry>,
        }
        let payload: SubtreePayload =
            serde_json::from_str(subtree_json).map_err(|e| format!("error:parse subtree: {e}"))?;
        let mut guard = self.last_index.lock().map_err(|e| format!("lock: {e}"))?;
        let index = guard
            .as_mut()
            .map(Arc::make_mut)
            .ok_or_else(|| "error:no index loaded".to_string())?;
        let new_version =
            index.replace_directory_with_subtree(target_path, &payload.tree, &payload.entries)?;
        // Keep the engine-level version counter aligned with the index's own
        // version so Dart's catalogVersion sees the bump.
        self.index_version.store(new_version, Ordering::Relaxed);
        Ok(new_version)
    }

    /// Load a persisted index file into the engine.
    /// On success the in-memory index is replaced and the version counter bumped.
    pub fn load_index_from_path(&self, path: &str) -> Result<(), String> {
        self.invalidate_index_load();
        let index = Self::read_index_or_legacy_snapshot(path)?;
        schedule_json_index_migration(path.to_string(), index.clone());
        self.set_loaded_index(index);
        Ok(())
    }

    fn read_index_or_legacy_snapshot(path: &str) -> Result<SnapshotIndex, String> {
        if path.ends_with(".pb") {
            let bytes = std::fs::read(path).map_err(|e| format!("error:read pb: {e}"))?;
            return decode_snapshot_index(&bytes);
        }

        let file = File::open(path).map_err(|e| format!("error:open index: {e}"))?;
        Ok(match serde_json::from_reader::<_, SnapshotIndex>(file) {
            Ok(index) => index,
            Err(index_error) => {
                let file = File::open(path).map_err(|e| format!("error:open snapshot: {e}"))?;
                serde_json::from_reader::<_, StorageSnapshot>(file)
                    .map(|snapshot| SnapshotIndex::from(&snapshot))
                    .map_err(|snapshot_error| {
                        format!("error:parse index: {index_error}; snapshot: {snapshot_error}")
                    })?
            }
        })
    }

    fn set_loaded_index(&self, index: SnapshotIndex) {
        self.index_version.store(index.version, Ordering::Relaxed);
        if let Ok(mut g) = self.last_index.lock() {
            *g = Some(Arc::new(index));
        }
        if let Ok(mut g) = self.last_snapshot.lock() {
            *g = None;
        }
    }

    /// Load a persisted index/snapshot on a Rust worker thread so Flutter's
    /// main isolate remains responsive while large legacy caches are migrated.
    pub fn start_load_index_from_path_async(&self, path: String) -> String {
        if self
            .is_index_loading
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::Relaxed)
            .is_err()
        {
            return "busy:index load already in progress".to_string();
        }

        // Supersede any older async restore. The generation check below
        // prevents older workers from publishing their result after this call
        // starts; is_index_loading tracks the physical worker so Dart can avoid
        // running a scan concurrently with a still-parsing large cache file.
        let load_generation = self.index_load_generation.fetch_add(1, Ordering::SeqCst) + 1;
        if let Ok(mut g) = self.last_index_load_error.lock() {
            *g = None;
        }

        let last_index = self.last_index.clone();
        let last_snapshot = self.last_snapshot.clone();
        let index_version = self.index_version.clone();
        let is_index_loading = self.is_index_loading.clone();
        let last_index_load_error = self.last_index_load_error.clone();
        let index_load_generation = self.index_load_generation.clone();

        std::thread::spawn(move || {
            match Self::read_index_or_legacy_snapshot(&path) {
                Ok(index) => {
                    schedule_json_index_migration(path.clone(), index.clone());
                    if index_load_generation.load(Ordering::SeqCst) == load_generation {
                        index_version.store(index.version, Ordering::Relaxed);
                        if let Ok(mut g) = last_index.lock() {
                            *g = Some(Arc::new(index));
                        }
                        if let Ok(mut g) = last_snapshot.lock() {
                            *g = None;
                        }
                    }
                }
                Err(error) => {
                    if index_load_generation.load(Ordering::SeqCst) == load_generation {
                        if let Ok(mut g) = last_index_load_error.lock() {
                            *g = Some(error);
                        }
                    }
                }
            }
            if index_load_generation.load(Ordering::SeqCst) == load_generation {
                is_index_loading.store(false, Ordering::Release);
            }
        });

        "ok".to_string()
    }

    pub fn invalidate_index_load(&self) {
        self.index_load_generation.fetch_add(1, Ordering::SeqCst);
        // Release the loading slot immediately so a superseding restore/scan can
        // start without waiting for a stale worker to finish parsing.
        self.is_index_loading.store(false, Ordering::Release);
        if let Ok(mut g) = self.last_index_load_error.lock() {
            *g = None;
        }
    }

    pub fn is_index_loading(&self) -> bool {
        self.is_index_loading.load(Ordering::Relaxed)
    }

    pub fn get_last_index_load_error(&self) -> Option<String> {
        self.last_index_load_error
            .lock()
            .ok()
            .and_then(|g| g.clone())
    }

    pub fn get_index_summary_json(&self) -> Result<String, String> {
        let guard = self.last_index.lock().map_err(|e| format!("lock: {e}"))?;
        let index = guard
            .as_ref()
            .ok_or_else(|| "error:no index loaded".to_string())?;
        index.summary_json()
    }

    /// Persist the current index (as a snapshot JSON) to `path`.
    /// Returns the snapshot_id on success.
    pub fn write_last_index_to_path(&self, path: &str) -> Result<String, String> {
        {
            let guard = self.last_index.lock().map_err(|e| format!("lock: {e}"))?;
            if let Some(index) = guard.as_ref() {
                let file = File::create(path).map_err(|e| format!("error:create index: {e}"))?;
                let mut writer = BufWriter::new(file);
                serde_json::to_writer(&mut writer, index.as_ref())
                    .map_err(|e| format!("error:serialize index: {e}"))?;
                writer
                    .flush()
                    .map_err(|e| format!("error:flush index: {e}"))?;
                return Ok(index.snapshot_id.clone());
            }
        }

        let snapshot_guard = self
            .last_snapshot
            .lock()
            .map_err(|e| format!("lock snapshot: {e}"))?;
        let snapshot = snapshot_guard
            .as_ref()
            .ok_or_else(|| "error:no index".to_string())?;
        let index = SnapshotIndex::from(snapshot);
        let file = File::create(path).map_err(|e| format!("error:create index: {e}"))?;
        let mut writer = BufWriter::new(file);
        serde_json::to_writer(&mut writer, &index)
            .map_err(|e| format!("error:serialize index: {e}"))?;
        writer
            .flush()
            .map_err(|e| format!("error:flush index: {e}"))?;
        Ok(index.snapshot_id)
    }

}
