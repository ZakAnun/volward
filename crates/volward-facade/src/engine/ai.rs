use super::*;

impl VolwardEngine {
    fn index_for_ai(&self, snapshot_id: &str) -> Result<Arc<SnapshotIndex>, String> {
        if let Ok(guard) = self.last_index.lock() {
            if let Some(index) = guard.as_ref() {
                if index.snapshot_id != snapshot_id {
                    return Err(format!(
                        "error:snapshot_id mismatch: got {}, expected {snapshot_id}",
                        index.snapshot_id
                    ));
                }
                return Ok(index.clone());
            }
        }
        let snapshot = self
            .last_snapshot
            .lock()
            .map_err(|_| "error:lock".to_string())?
            .clone();
        let Some(snapshot) = snapshot else {
            return Err("error:no index or snapshot loaded".to_string());
        };
        if snapshot.snapshot_id != snapshot_id {
            return Err(format!(
                "error:snapshot_id mismatch: got {}, expected {snapshot_id}",
                snapshot.snapshot_id
            ));
        }
        Ok(Arc::new(SnapshotIndex::from_snapshot_with_version(
            &snapshot, 1,
        )))
    }

    /// Build AI candidate JSON for the given snapshot.
    ///
    /// Prefers `last_index` (production path — `run_index_scan` clears
    /// `last_snapshot`), then falls back to in-memory `last_snapshot`
    /// (tests / legacy). Heavy work: call via
    /// [`Self::start_build_ai_candidates_async`] from the UI path.

    pub fn build_ai_candidates_json(&self, snapshot_id: &str) -> String {
        let kb = OsKnowledgeBase::for_current_platform();

        // 1) Prefer index (production path). Clone under the lock, then
        // release before cache build / aggregation so other FFI isn't stalled.
        let index_owned = match self.last_index.lock() {
            Ok(guard) => guard.clone(),
            Err(e) => return format!("error:lock:{e}"),
        };

        if let Some(index) = index_owned {
            if index.snapshot_id != snapshot_id {
                return format!("error:snapshot_id mismatch: got {}", index.snapshot_id);
            }
            let indexed_prefixes = volward_core::indexed_local_exclusion_prefixes(&index);
            let cache = self.ensure_unclassified_coverage_cache(
                &index,
                &kb,
                &indexed_prefixes,
                volward_core::UnclassifiedCoverageCacheDepth::FunnelSample,
            );
            let assembly = volward_core::build_index_candidate_assembly(
                index.as_ref(),
                cache.as_ref(),
                &kb,
                &indexed_prefixes,
            );
            return Self::serialize_ai_candidate_assembly(snapshot_id, &assembly);
        }

        // 2) Fallback: in-memory StorageSnapshot (tests / legacy)
        let snapshot_owned = match self.last_snapshot.lock() {
            Ok(g) => g.clone(),
            Err(e) => return format!("error:lock:{e}"),
        };
        let snapshot = match snapshot_owned.as_ref() {
            Some(s) => s,
            None => return "error:no snapshot or index loaded".to_string(),
        };
        if snapshot.snapshot_id != snapshot_id {
            return format!("error:snapshot_id mismatch: got {}", snapshot.snapshot_id);
        }

        let assembly = volward_core::build_snapshot_candidate_assembly(snapshot, &kb);
        Self::serialize_ai_candidate_assembly(snapshot_id, &assembly)
    }

    fn serialize_ai_candidate_assembly(
        snapshot_id: &str,
        assembly: &volward_core::AiCandidateAssembly,
    ) -> String {
        let set = &assembly.set;
        match serde_json::to_string(&serde_json::json!({
            "snapshot_id": snapshot_id,
            "root_path": assembly.root_path,
            "result_cache_key": assembly.cache_key,
            "pre_classified": set.pre_classified,
            "unknown_candidates": set.candidates,
            "estimated_input_tokens": set.estimated_input_tokens,
            "estimated_byok_batch_input_tokens": set.estimated_byok_batch_input_tokens,
            "total_raw_count": set.total_raw_count,
            "candidates_total_before_cap": set.candidates_total_before_cap,
            "truncated": set.truncated,
            "pre_classified_truncated": set.pre_classified_truncated,
            "has_existing_result": assembly.has_existing_result,
        })) {
            Ok(s) => s,
            Err(e) => format!("error:serialize:{e}"),
        }
    }

    /// Build candidates on a worker thread so Flutter's main isolate stays
    /// responsive on multi-hundred-GB scans.
    pub fn start_build_ai_candidates_async(&self, snapshot_id: String) -> String {
        if self
            .is_ai_candidates_building
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::Relaxed)
            .is_err()
        {
            return "busy:ai candidates build already in progress".to_string();
        }

        let generation = self.ai_candidates_generation.fetch_add(1, Ordering::SeqCst) + 1;
        if let Ok(mut g) = self.ai_candidates_json.lock() {
            *g = None;
        }
        if let Ok(mut g) = self.ai_candidates_spill_path.lock() {
            *g = None;
        }

        // Snapshot Arc handles for the worker; the build method locks briefly.
        let engine_index = self.last_index.clone();
        let engine_snapshot = self.last_snapshot.clone();
        let local_coverage_funnel_cache = self.local_coverage_funnel_cache.clone();
        let unclassified_subtree_index_cache = self.unclassified_subtree_index_cache.clone();
        let unclassified_coverage_cache = self.unclassified_coverage_cache.clone();
        let coverage_cache_build_flights = self.coverage_cache_build_flights.clone();
        let index_version = self.index_version.clone();
        let result_slot = self.ai_candidates_json.clone();
        let spill_slot = self.ai_candidates_spill_path.clone();
        let building = self.is_ai_candidates_building.clone();
        let generation_slot = self.ai_candidates_generation.clone();
        let snapshot_id_for_path = snapshot_id.clone();

        // We need a thin stand-in that can call the same build logic. Reconstruct
        // a minimal engine view via a free helper using the cloned Arcs.
        std::thread::spawn(move || {
            struct AiCandidatesBuildingGuard(Arc<AtomicBool>);
            impl Drop for AiCandidatesBuildingGuard {
                fn drop(&mut self) {
                    self.0.store(false, Ordering::Release);
                }
            }
            let _building_guard = AiCandidatesBuildingGuard(building.clone());

            #[cfg(debug_assertions)]
            let build_started = std::time::Instant::now();
            #[cfg(debug_assertions)]
            eprintln!("Volward AI: native candidates build thread started snapshot={snapshot_id}");

            let json = Self::build_ai_candidates_json_with(
                &engine_index,
                &engine_snapshot,
                &snapshot_id,
                local_coverage_funnel_cache,
                unclassified_subtree_index_cache,
                unclassified_coverage_cache,
                coverage_cache_build_flights,
                index_version,
            );

            #[cfg(debug_assertions)]
            eprintln!(
                "Volward AI: native candidates JSON built in {:?} ({} bytes, err={})",
                build_started.elapsed(),
                json.len(),
                json.starts_with("error:")
            );
            if generation_slot.load(Ordering::SeqCst) == generation {
                if json.starts_with("error:") {
                    if let Ok(mut g) = result_slot.lock() {
                        *g = Some(json);
                    }
                } else {
                    let path = std::env::temp_dir().join(format!(
                        "volward-ai-candidates-{}-{}.pb",
                        snapshot_id_for_path, generation
                    ));
                    let bytes =
                        match crate::pb_convert::encode_ai_candidates_payload_from_json(&json) {
                            Ok(encoded) => encoded,
                            Err(err) => {
                                if let Ok(mut g) = result_slot.lock() {
                                    *g = Some(err);
                                }
                                return;
                            }
                        };
                    match std::fs::write(&path, bytes) {
                        Ok(()) => {
                            if let Ok(mut spill) = spill_slot.lock() {
                                *spill = Some(path.to_string_lossy().into_owned());
                            }
                        }
                        Err(e) => {
                            if let Ok(mut g) = result_slot.lock() {
                                *g = Some(format!("error:spill:{e}"));
                            }
                        }
                    }
                }
            }
        });

        "ok".to_string()
    }

    fn build_ai_candidates_json_with(
        last_index: &Arc<Mutex<Option<Arc<SnapshotIndex>>>>,
        last_snapshot: &Arc<Mutex<Option<StorageSnapshot>>>,
        snapshot_id: &str,
        local_coverage_funnel_cache: Arc<Mutex<Option<LocalCoverageFunnelCache>>>,
        unclassified_subtree_index_cache: Arc<Mutex<Option<UnclassifiedSubtreeIndexCache>>>,
        unclassified_coverage_cache: Arc<Mutex<Option<UnclassifiedCoverageCacheSlot>>>,
        coverage_cache_build_flights: Arc<Mutex<HashMap<(String, u64), Arc<Mutex<()>>>>>,
        index_version: Arc<std::sync::atomic::AtomicU64>,
    ) -> String {
        // Temporary engine shell so we reuse the same method body without
        // duplicating aggregation logic. Only index/snapshot fields are read.
        let shell = VolwardEngine {
            platform: Arc::new(DesktopPlatform::new()),
            cancel: Arc::new(AtomicBool::new(false)),
            persist_pause: Arc::new(AtomicBool::new(false)),
            is_scanning: Arc::new(AtomicBool::new(false)),
            last_snapshot: last_snapshot.clone(),
            last_index: last_index.clone(),
            is_index_loading: Arc::new(AtomicBool::new(false)),
            last_index_load_error: Arc::new(Mutex::new(None)),
            last_pause_error: Arc::new(Mutex::new(None)),
            index_load_generation: Arc::new(std::sync::atomic::AtomicU64::new(0)),
            index_version,
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
            local_coverage_funnel_cache,
            unclassified_subtree_index_cache,
            unclassified_coverage_cache,
            coverage_cache_build_flights,
            ai_coverage_plan: Arc::new(Mutex::new(None)),
            ai_tree_coverage_plan: Arc::new(Mutex::new(None)),
            capability_registry: Arc::new(Mutex::new(CapabilityRegistry::new())),
            capability_jobs: CapabilityJobStore::new(),
        };
        shell.build_ai_candidates_json(snapshot_id)
    }

    /// Build coverage plan JSON on a worker thread (tree or flat plan).
    pub fn start_build_ai_coverage_plan_async(&self, snapshot_id: String, tree: bool) -> String {
        if tree && !self.is_ai_coverage_plan_building.load(Ordering::Relaxed) {
            if let Ok(guard) = self.ai_tree_coverage_plan.lock() {
                if let Some(plan) = guard.as_ref() {
                    if plan.snapshot_id == snapshot_id {
                        if let Ok(index) = self.index_for_ai(&snapshot_id) {
                            let json = Self::tree_plan_preview_json(&index, plan);
                            if let Ok(mut preview) = self.ai_coverage_plan_preview_json.lock() {
                                *preview = Some(json);
                            }
                            return "ok".to_string();
                        }
                    }
                }
            }
        }

        if self
            .is_ai_coverage_plan_building
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::Relaxed)
            .is_err()
        {
            return "busy:coverage plan build already in progress".to_string();
        }

        let generation = self
            .ai_coverage_plan_build_generation
            .fetch_add(1, Ordering::SeqCst)
            + 1;
        if let Ok(mut g) = self.ai_coverage_plan_preview_json.lock() {
            *g = None;
        }

        let last_index = self.last_index.clone();
        let platform = self.platform.clone();
        let ai_coverage_plan = self.ai_coverage_plan.clone();
        let ai_tree_coverage_plan = self.ai_tree_coverage_plan.clone();
        let local_coverage_funnel_cache = self.local_coverage_funnel_cache.clone();
        let unclassified_subtree_index_cache = self.unclassified_subtree_index_cache.clone();
        let unclassified_coverage_cache = self.unclassified_coverage_cache.clone();
        let coverage_cache_build_flights = self.coverage_cache_build_flights.clone();
        let index_version = self.index_version.clone();
        let result_slot = self.ai_coverage_plan_preview_json.clone();
        let building = self.is_ai_coverage_plan_building.clone();
        let generation_slot = self.ai_coverage_plan_build_generation.clone();

        std::thread::spawn(move || {
            let json = if tree {
                Self::build_ai_tree_plan_json_with(
                    &last_index,
                    &platform,
                    &ai_tree_coverage_plan,
                    &local_coverage_funnel_cache,
                    &unclassified_subtree_index_cache,
                    &unclassified_coverage_cache,
                    coverage_cache_build_flights.clone(),
                    index_version,
                    &snapshot_id,
                )
            } else {
                Self::build_ai_coverage_plan_json_with(
                    &last_index,
                    &platform,
                    &ai_coverage_plan,
                    &local_coverage_funnel_cache,
                    &unclassified_coverage_cache,
                    coverage_cache_build_flights,
                    index_version,
                    &snapshot_id,
                )
            };
            if generation_slot.load(Ordering::SeqCst) == generation {
                if let Ok(mut g) = result_slot.lock() {
                    *g = Some(json);
                }
            }
            building.store(false, Ordering::Release);
        });

        "ok".to_string()
    }

    fn build_ai_coverage_plan_json_with(
        last_index: &Arc<Mutex<Option<Arc<SnapshotIndex>>>>,
        platform: &Arc<DesktopPlatform>,
        ai_coverage_plan: &Arc<Mutex<Option<AiCoveragePlan>>>,
        local_coverage_funnel_cache: &Arc<Mutex<Option<LocalCoverageFunnelCache>>>,
        unclassified_coverage_cache: &Arc<Mutex<Option<UnclassifiedCoverageCacheSlot>>>,
        coverage_cache_build_flights: Arc<Mutex<HashMap<(String, u64), Arc<Mutex<()>>>>>,
        index_version: Arc<std::sync::atomic::AtomicU64>,
        snapshot_id: &str,
    ) -> String {
        let shell = VolwardEngine {
            platform: platform.clone(),
            cancel: Arc::new(AtomicBool::new(false)),
            persist_pause: Arc::new(AtomicBool::new(false)),
            is_scanning: Arc::new(AtomicBool::new(false)),
            last_snapshot: Arc::new(Mutex::new(None)),
            last_index: last_index.clone(),
            is_index_loading: Arc::new(AtomicBool::new(false)),
            last_index_load_error: Arc::new(Mutex::new(None)),
            last_pause_error: Arc::new(Mutex::new(None)),
            index_load_generation: Arc::new(std::sync::atomic::AtomicU64::new(0)),
            index_version,
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
            local_coverage_funnel_cache: local_coverage_funnel_cache.clone(),
            unclassified_subtree_index_cache: Arc::new(Mutex::new(None)),
            unclassified_coverage_cache: unclassified_coverage_cache.clone(),
            coverage_cache_build_flights,
            ai_coverage_plan: ai_coverage_plan.clone(),
            ai_tree_coverage_plan: Arc::new(Mutex::new(None)),
            capability_registry: Arc::new(Mutex::new(CapabilityRegistry::new())),
            capability_jobs: CapabilityJobStore::new(),
        };
        shell.build_ai_coverage_plan_json(snapshot_id)
    }

    fn build_ai_tree_plan_json_with(
        last_index: &Arc<Mutex<Option<Arc<SnapshotIndex>>>>,
        platform: &Arc<DesktopPlatform>,
        ai_tree_coverage_plan: &Arc<Mutex<Option<AiTreePlan>>>,
        local_coverage_funnel_cache: &Arc<Mutex<Option<LocalCoverageFunnelCache>>>,
        unclassified_subtree_index_cache: &Arc<Mutex<Option<UnclassifiedSubtreeIndexCache>>>,
        unclassified_coverage_cache: &Arc<Mutex<Option<UnclassifiedCoverageCacheSlot>>>,
        coverage_cache_build_flights: Arc<Mutex<HashMap<(String, u64), Arc<Mutex<()>>>>>,
        index_version: Arc<std::sync::atomic::AtomicU64>,
        snapshot_id: &str,
    ) -> String {
        let shell = VolwardEngine {
            platform: platform.clone(),
            cancel: Arc::new(AtomicBool::new(false)),
            persist_pause: Arc::new(AtomicBool::new(false)),
            is_scanning: Arc::new(AtomicBool::new(false)),
            last_snapshot: Arc::new(Mutex::new(None)),
            last_index: last_index.clone(),
            is_index_loading: Arc::new(AtomicBool::new(false)),
            last_index_load_error: Arc::new(Mutex::new(None)),
            last_pause_error: Arc::new(Mutex::new(None)),
            index_load_generation: Arc::new(std::sync::atomic::AtomicU64::new(0)),
            index_version,
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
            local_coverage_funnel_cache: local_coverage_funnel_cache.clone(),
            unclassified_subtree_index_cache: unclassified_subtree_index_cache.clone(),
            unclassified_coverage_cache: unclassified_coverage_cache.clone(),
            coverage_cache_build_flights,
            ai_coverage_plan: Arc::new(Mutex::new(None)),
            ai_tree_coverage_plan: ai_tree_coverage_plan.clone(),
            capability_registry: Arc::new(Mutex::new(CapabilityRegistry::new())),
            capability_jobs: CapabilityJobStore::new(),
        };
        shell.build_ai_tree_plan_json(snapshot_id)
    }

    pub fn is_ai_coverage_plan_building(&self) -> bool {
        self.is_ai_coverage_plan_building.load(Ordering::Relaxed)
    }

    pub fn get_ai_coverage_plan_json(&self) -> String {
        self.ai_coverage_plan_preview_json
            .lock()
            .ok()
            .and_then(|g| g.clone())
            .unwrap_or_else(|| "error:not_ready".to_string())
    }

    pub fn is_ai_candidates_building(&self) -> bool {
        self.is_ai_candidates_building.load(Ordering::Relaxed)
    }

    /// Latest async build payload (or error string). Empty when none yet.
    ///
    /// After an async build, reads the spill file when present (then deletes it).
    pub fn get_ai_candidates_json(&self) -> String {
        if let Ok(mut spill) = self.ai_candidates_spill_path.lock() {
            if let Some(path) = spill.take() {
                match std::fs::read_to_string(&path) {
                    Ok(json) => {
                        let _ = std::fs::remove_file(&path);
                        return json;
                    }
                    Err(e) => return format!("error:spill:{e}"),
                }
            }
        }
        self.ai_candidates_json
            .lock()
            .ok()
            .and_then(|g| g.clone())
            .unwrap_or_else(|| "error:not_ready".to_string())
    }

    /// Takes the temp-file path for the latest async candidates build (if any).
    /// The file is removed from engine state; the caller owns deletion after read.
    pub fn take_ai_candidates_spill_path(&self) -> String {
        self.ai_candidates_spill_path
            .lock()
            .ok()
            .and_then(|mut g| g.take())
            .unwrap_or_else(|| "error:not_ready".to_string())
    }

    pub fn build_ai_coverage_plan_json(&self, snapshot_id: &str) -> String {
        let kb = volward_core::os_knowledge::OsKnowledgeBase::for_current_platform();
        let index = match self.index_for_ai(snapshot_id) {
            Ok(index) => index,
            Err(error) => return error,
        };
        let plan = build_ai_coverage_plan(&index, &kb);
        let funnel = self
            .ensure_unclassified_coverage_cache(
                &index,
                &kb,
                self.platform.protected_prefixes(),
                volward_core::UnclassifiedCoverageCacheDepth::Full,
            )
            .funnel_stats;
        let summary = coverage_plan_summary(&plan, funnel);
        if let Ok(mut slot) = self.ai_coverage_plan.lock() {
            *slot = Some(plan);
        }
        serde_json::to_string(&summary)
            .unwrap_or_else(|error| format!("error:serialize coverage summary: {error}"))
    }

    pub fn list_local_coverage_verdicts_json(
        &self,
        snapshot_id: &str,
        cursor: u64,
        limit: u32,
    ) -> String {
        let kb = OsKnowledgeBase::for_current_platform();
        let index = match self.index_for_ai(snapshot_id) {
            Ok(index) => index,
            Err(error) => return error,
        };
        let limit = limit.max(1) as usize;
        let protected = self.platform.protected_prefixes();
        let (funnel_map, classified, base_ctx) =
            self.local_coverage_funnel_cache_for(&index, &kb, protected);
        let (verdicts, next_cursor) = page_local_coverage_verdicts(
            &index,
            &kb,
            &base_ctx,
            &funnel_map,
            &classified,
            cursor,
            limit,
        );
        let page = coverage_local_verdict_page(verdicts, next_cursor);
        serde_json::to_string(&page)
            .unwrap_or_else(|error| format!("error:serialize local verdict page: {error}"))
    }

    pub fn next_ai_coverage_page_json(
        &self,
        snapshot_id: &str,
        plan_version: u64,
        cursor: u64,
        page_size: u32,
    ) -> String {
        let page_size = page_size.max(1) as usize;
        let guard = match self.ai_coverage_plan.lock() {
            Ok(guard) => guard,
            Err(_) => return "error:lock".to_string(),
        };
        let Some(plan) = guard.as_ref() else {
            return "error:coverage plan not built".to_string();
        };
        if plan.snapshot_id != snapshot_id || plan.plan_version != plan_version {
            return "error:coverage plan mismatch".to_string();
        }
        let page = coverage_plan_page(plan, cursor, page_size);
        serde_json::to_string(&page)
            .unwrap_or_else(|error| format!("error:serialize coverage page: {error}"))
    }

    pub fn build_ai_tree_plan_json(&self, snapshot_id: &str) -> String {
        let kb = volward_core::os_knowledge::OsKnowledgeBase::for_current_platform();
        let index = match self.index_for_ai(snapshot_id) {
            Ok(index) => index,
            Err(error) => return error,
        };
        let protected = self.platform.protected_prefixes();
        let cache = self.ensure_unclassified_coverage_cache(
            &index,
            &kb,
            protected,
            volward_core::UnclassifiedCoverageCacheDepth::Full,
        );
        let plan =
            build_ai_tree_plan_from_coverage_cache(&index, &kb, protected, &[], cache.as_ref());
        if let Ok(mut slot) = self.ai_tree_coverage_plan.lock() {
            *slot = Some(plan.clone());
        }
        Self::tree_plan_preview_json(&index, &plan)
    }

    pub fn next_ai_tree_coverage_page_json(
        &self,
        snapshot_id: &str,
        plan_version: u64,
        cursor: u64,
        page_size: u32,
    ) -> String {
        let page_size = page_size.max(1) as usize;
        let guard = match self.ai_tree_coverage_plan.lock() {
            Ok(guard) => guard,
            Err(_) => return "error:lock".to_string(),
        };
        let Some(plan) = guard.as_ref() else {
            return "error:tree coverage plan not built".to_string();
        };
        if plan.snapshot_id != snapshot_id || plan.plan_version != plan_version {
            return "error:tree coverage plan mismatch".to_string();
        }
        if cursor > plan.scope_file_ids.len() as u64 {
            return "error:scope coverage cursor out of range".to_string();
        }
        let page = coverage_tree_page(plan, cursor, page_size);
        serde_json::to_string(&page)
            .unwrap_or_else(|error| format!("error:serialize tree page: {error}"))
    }

    pub fn next_ai_tail_coverage_page_json(
        &self,
        snapshot_id: &str,
        plan_version: u64,
        cursor: u64,
        page_size: u32,
    ) -> String {
        let page_size = page_size.max(1) as usize;
        let guard = match self.ai_tree_coverage_plan.lock() {
            Ok(guard) => guard,
            Err(_) => return "error:lock".to_string(),
        };
        let Some(plan) = guard.as_ref() else {
            return "error:tree coverage plan not built".to_string();
        };
        if plan.snapshot_id != snapshot_id || plan.plan_version != plan_version {
            return "error:tree coverage plan mismatch".to_string();
        }
        let page = coverage_tail_page(plan, cursor, page_size);
        serde_json::to_string(&page)
            .unwrap_or_else(|error| format!("error:serialize tail page: {error}"))
    }

    pub fn next_ai_scope_coverage_page_json(
        &self,
        snapshot_id: &str,
        plan_version: u64,
        cursor: u64,
        page_size: u32,
    ) -> String {
        let page_size = page_size.max(1) as usize;
        let guard = match self.ai_tree_coverage_plan.lock() {
            Ok(guard) => guard,
            Err(_) => return "error:lock".to_string(),
        };
        let Some(plan) = guard.as_ref() else {
            return "error:tree coverage plan not built".to_string();
        };
        if plan.snapshot_id != snapshot_id || plan.plan_version != plan_version {
            return "error:tree coverage plan mismatch".to_string();
        }
        if cursor > plan.scope_file_ids.len() as u64 {
            return "error:scope coverage cursor out of range".to_string();
        }
        let kb = OsKnowledgeBase::for_current_platform();
        let index = match self.index_for_ai(snapshot_id) {
            Ok(index) => index,
            Err(error) => return error,
        };
        if index.content_fingerprint() != plan.scope_fingerprint {
            return "error:scope coverage index changed".to_string();
        }
        let protected = self.platform.protected_prefixes();
        let (funnel_map, _, base_ctx) =
            self.local_coverage_funnel_cache_for(&index, &kb, protected);
        let page = coverage_scope_page(
            &index,
            &kb,
            base_ctx.as_ref(),
            funnel_map.as_ref(),
            plan,
            cursor,
            page_size,
        );
        serde_json::to_string(&page)
            .unwrap_or_else(|error| format!("error:serialize scope page: {error}"))
    }

    pub fn expand_ai_tree_node_json(&self, snapshot_id: &str, dir_path: &str) -> String {
        let kb = OsKnowledgeBase::for_current_platform();
        let index = match self.index_for_ai(snapshot_id) {
            Ok(index) => index,
            Err(error) => return error,
        };
        if index.snapshot_id != snapshot_id {
            return "error:snapshot mismatch".to_string();
        }
        let protected = self.platform.protected_prefixes();
        let subtree_index = self.unclassified_subtree_index_for(&index, &kb, protected);
        let nodes = expand_tree_drill_children_with_index(
            &index,
            &kb,
            protected,
            &[],
            dir_path,
            subtree_index.as_ref(),
        );
        serde_json::json!({ "nodes": nodes }).to_string()
    }

    pub fn apply_ai_dir_verdict_json(
        &self,
        snapshot_id: &str,
        dir_path: &str,
        verdict: &str,
        confidence: &str,
        role_snake_case: &str,
    ) -> String {
        let index = match self.index_for_ai(snapshot_id) {
            Ok(index) => index,
            Err(error) => return error,
        };
        if index.snapshot_id != snapshot_id {
            return "error:snapshot mismatch".to_string();
        }
        let role: DirectoryRole = serde_json::from_str(&format!("\"{role_snake_case}\""))
            .unwrap_or(DirectoryRole::Unknown);
        let verdicts = apply_dir_verdict(&index, dir_path, verdict, confidence, role);
        serde_json::json!({ "verdicts": verdicts }).to_string()
    }

    /// Appends the propagated verdicts for `dir_path` to the JSONL file at
    /// `out_path` and returns `{"count":N}`; avoids shipping huge subtrees over FFI.
    pub fn apply_ai_dir_verdict_to_file(
        &self,
        snapshot_id: &str,
        dir_path: &str,
        verdict: &str,
        confidence: &str,
        role_snake_case: &str,
        out_path: &str,
    ) -> String {
        use std::io::Write;

        let index = match self.index_for_ai(snapshot_id) {
            Ok(index) => index,
            Err(error) => return error,
        };
        if index.snapshot_id != snapshot_id {
            return "error:snapshot mismatch".to_string();
        }
        let role: DirectoryRole = serde_json::from_str(&format!("\"{role_snake_case}\""))
            .unwrap_or(DirectoryRole::Unknown);
        let file = match std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(out_path)
        {
            Ok(file) => file,
            Err(e) => return format!("error:open verdict file: {e}"),
        };
        let mut writer = std::io::BufWriter::with_capacity(1 << 20, file);
        let count =
            match write_dir_verdict_jsonl(&index, dir_path, verdict, confidence, role, &mut writer)
                .and_then(|count| writer.flush().map(|()| count))
            {
                Ok(count) => count,
                Err(e) => return format!("error:write verdict file: {e}"),
            };
        serde_json::json!({ "count": count }).to_string()
    }

    pub fn resolve_ai_coverage_group_json(&self, snapshot_id: &str, group_path: &str) -> String {
        let kb = volward_core::os_knowledge::OsKnowledgeBase::for_current_platform();
        let index = match self.index_for_ai(snapshot_id) {
            Ok(index) => index,
            Err(error) => return error,
        };
        let members = coverage_group_member_paths(&index, &kb, group_path);
        let resolution = coverage_group_resolution(snapshot_id, group_path, members);
        serde_json::to_string(&resolution)
            .unwrap_or_else(|error| format!("error:serialize coverage group: {error}"))
    }

    pub fn save_ai_result_json(&self, snapshot_id: &str, result_json: &str) -> bool {
        use volward_core::AiAnalysisResult;
        let mut result: AiAnalysisResult = match serde_json::from_str(result_json) {
            Ok(r) => r,
            Err(_) => return false,
        };
        if result.snapshot_id.is_empty() {
            result.snapshot_id = snapshot_id.to_string();
        }
        if !result.save_for_reuse().is_ok() {
            return false;
        }
        let pb = crate::pb_convert::encode_ai_analysis_result_pb(&result);
        let mut ok = true;
        if let Some(cache_key) = result.cache_key.as_deref() {
            if !cache_key.is_empty() && AiAnalysisResult::save_pb_for_key(cache_key, &pb).is_err() {
                ok = false;
            }
        }
        if !result.snapshot_id.is_empty()
            && result.cache_key.as_deref() != Some(result.snapshot_id.as_str())
            && AiAnalysisResult::save_pb_for_key(&result.snapshot_id, &pb).is_err()
        {
            ok = false;
        }
        ok
    }

    /// Load a previously saved AI analysis JSON.
    ///
    /// Prefer the content-addressed `cache_key` (stable across re-scans of the
    /// same directory). Falls back to `snapshot_id` for legacy files.
    pub fn load_ai_result_json(&self, key: &str) -> String {
        use volward_core::AiAnalysisResult;
        match AiAnalysisResult::load(key) {
            Some(result) => {
                serde_json::to_string(&result).unwrap_or_else(|e| format!("error:serialize:{e}"))
            }
            None => "error:not_found".to_string(),
        }
    }
}
