use super::*;

impl VolwardEngine {
    pub(super) fn peek_unclassified_coverage_cache(
        &self,
        snapshot_id: &str,
        index_version: u64,
    ) -> Option<Arc<UnclassifiedCoverageCache>> {
        let guard = self.unclassified_coverage_cache.lock().ok()?;
        let slot = guard.as_ref()?;
        if slot.snapshot_id == snapshot_id && slot.index_version == index_version {
            Some(slot.cache.clone())
        } else {
            None
        }
    }

    pub(super) fn coverage_cache_build_flight(
        &self,
        snapshot_id: &str,
        index_version: u64,
    ) -> Arc<Mutex<()>> {
        let key = (snapshot_id.to_string(), index_version);
        let mut map = self
            .coverage_cache_build_flights
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        map.entry(key)
            .or_insert_with(|| Arc::new(Mutex::new(())))
            .clone()
    }

    pub(super) fn log_coverage_cache_persist_error(context: &str, err: std::io::Error) {
        eprintln!("Volward AI: coverage cache {context} failed: {err}");
    }

    pub(super) fn ensure_unclassified_coverage_cache(
        &self,
        index: &SnapshotIndex,
        kb: &OsKnowledgeBase,
        protected_prefixes: &[String],
        depth: volward_core::UnclassifiedCoverageCacheDepth,
    ) -> Arc<UnclassifiedCoverageCache> {
        use volward_core::{
            build_unclassified_coverage_cache, build_unclassified_coverage_cache_funnel_sample,
            cache_meets_depth, UnclassifiedCoverageCacheDepth,
        };

        let snapshot_id = index.snapshot_id.clone();
        let index_version = self.index_version.load(Ordering::Relaxed);
        if let Some(cache) = self.peek_unclassified_coverage_cache(&snapshot_id, index_version) {
            if cache_meets_depth(cache.as_ref(), depth) {
                return cache;
            }
        }

        let flight = self.coverage_cache_build_flight(&snapshot_id, index_version);
        let _flight_guard = flight
            .lock()
            .unwrap_or_else(|e| e.into_inner());

        if let Some(cache) = self.peek_unclassified_coverage_cache(&snapshot_id, index_version) {
            if cache_meets_depth(cache.as_ref(), depth) {
                return cache;
            }
        }

        volward_core::unclassified_coverage_cache::invalidate_stale_coverage_cache_sidecar(
            &snapshot_id,
            index_version,
        );

        let fingerprint = index.content_fingerprint();
        // The sample is one cheap index pass; loading the (large) full sidecar for it is slower.
        let (built, built_fresh) = if depth == UnclassifiedCoverageCacheDepth::FunnelSample {
            (
                Arc::new(build_unclassified_coverage_cache_funnel_sample(index)),
                true,
            )
        } else if let Some(restored) =
            volward_core::unclassified_coverage_cache::try_load_coverage_cache_from_disk(
                &snapshot_id,
                index_version,
                &fingerprint,
            )
        {
            (Arc::new(restored), false)
        } else {
                (
                    Arc::new(build_unclassified_coverage_cache(
                        index,
                        kb,
                        protected_prefixes,
                        &[],
                    )),
                    true,
                )
            };

        self.store_unclassified_coverage_cache(
            &snapshot_id,
            index_version,
            built.clone(),
        );

        if built_fresh && built.subtree_index_ready {
            self.persist_unclassified_coverage_cache(
                &snapshot_id,
                index_version,
                &fingerprint,
                built.as_ref(),
            );
        }
        built
    }

    /// Writes bin first, then meta; meta is the commit marker that makes the bin loadable.
    pub(super) fn persist_unclassified_coverage_cache(
        &self,
        snapshot_id: &str,
        index_version: u64,
        fingerprint: &str,
        cache: &UnclassifiedCoverageCache,
    ) {
        use volward_core::unclassified_coverage_cache::{
            coverage_cache_sidecar_path, save_coverage_cache_sidecar, CoverageCacheSidecarMeta,
        };

        let sidecar_path = coverage_cache_sidecar_path(snapshot_id);
        let _ = std::fs::remove_file(&sidecar_path);
        let wire = volward_core::coverage_cache_to_persisted(cache, snapshot_id, index_version);
        let bin_path = volward_core::coverage_cache_bin_path(snapshot_id);
        if let Err(err) = volward_core::save_coverage_cache_bin(&bin_path, &wire) {
            Self::log_coverage_cache_persist_error("bin save", err);
            let _ = std::fs::remove_file(bin_path);
            return;
        }
        let sidecar =
            CoverageCacheSidecarMeta::from_cache(snapshot_id, index_version, fingerprint, cache);
        if let Err(err) = save_coverage_cache_sidecar(&sidecar_path, &sidecar) {
            Self::log_coverage_cache_persist_error("meta save", err);
        }
    }

    pub(super) fn store_unclassified_coverage_cache(
        &self,
        snapshot_id: &str,
        index_version: u64,
        built: Arc<UnclassifiedCoverageCache>,
    ) {
        let funnel_map = Arc::clone(&built.funnel_map);
        let classified = Arc::clone(&built.classified);
        let subtree_index = Arc::clone(&built.subtree_index);

        if let Ok(mut guard) = self.local_coverage_funnel_cache.lock() {
            *guard = Some(LocalCoverageFunnelCache {
                snapshot_id: snapshot_id.to_string(),
                index_version,
                funnel_map,
                classified,
                base_ctx: None,
            });
        }
        if let Ok(mut guard) = self.unclassified_subtree_index_cache.lock() {
            *guard = Some(UnclassifiedSubtreeIndexCache {
                snapshot_id: snapshot_id.to_string(),
                index_version,
                subtree_index,
            });
        }
        if let Ok(mut guard) = self.unclassified_coverage_cache.lock() {
            *guard = Some(UnclassifiedCoverageCacheSlot {
                snapshot_id: snapshot_id.to_string(),
                index_version,
                cache: built,
            });
        }
    }

    pub(super) fn unclassified_subtree_index_for(
        &self,
        index: &SnapshotIndex,
        kb: &OsKnowledgeBase,
        protected_prefixes: &[String],
    ) -> Arc<UnclassifiedSubtreeIndex> {
        let snapshot_id = index.snapshot_id.clone();
        let index_version = self.index_version.load(Ordering::Relaxed);
        self.ensure_unclassified_coverage_cache(
            index,
            kb,
            protected_prefixes,
            volward_core::UnclassifiedCoverageCacheDepth::Full,
        );
        if let Ok(guard) = self.unclassified_subtree_index_cache.lock() {
            if let Some(cache) = guard.as_ref() {
                if cache.snapshot_id == snapshot_id && cache.index_version == index_version {
                    return cache.subtree_index.clone();
                }
            }
        }
        Arc::new(UnclassifiedSubtreeIndex::default())
    }

    pub(super) fn tree_plan_preview_json(index: &SnapshotIndex, plan: &AiTreePlan) -> String {
        let summary = coverage_tree_summary(index, plan);
        serde_json::to_string(&summary)
            .unwrap_or_else(|error| format!("error:serialize tree summary: {error}"))
    }

    pub(super) fn local_coverage_funnel_cache_for(
        &self,
        index: &SnapshotIndex,
        kb: &OsKnowledgeBase,
        protected_prefixes: &[String],
    ) -> (
        Arc<CoverageFunnelContextMap>,
        Arc<HashSet<String>>,
        Arc<CoverageFunnelContext>,
    ) {
        let index_version = self.index_version.load(Ordering::Relaxed);
        self.ensure_unclassified_coverage_cache(
            index,
            kb,
            protected_prefixes,
            volward_core::UnclassifiedCoverageCacheDepth::Full,
        );
        let mut maps = None;
        if let Ok(guard) = self.local_coverage_funnel_cache.lock() {
            if let Some(cache) = guard.as_ref() {
                if cache.snapshot_id == index.snapshot_id && cache.index_version == index_version {
                    if let Some(ctx) = cache.base_ctx.as_ref() {
                        return (cache.funnel_map.clone(), cache.classified.clone(), ctx.clone());
                    }
                    maps = Some((cache.funnel_map.clone(), cache.classified.clone()));
                }
            }
        }
        let ctx = Arc::new(CoverageFunnelContext::for_index(index, protected_prefixes, &[]));
        let Some((funnel_map, classified)) = maps else {
            return (
                Arc::new(CoverageFunnelContextMap::new()),
                Arc::new(HashSet::new()),
                ctx,
            );
        };
        if let Ok(mut guard) = self.local_coverage_funnel_cache.lock() {
            if let Some(cache) = guard.as_mut() {
                if cache.snapshot_id == index.snapshot_id && cache.index_version == index_version {
                    cache.base_ctx = Some(ctx.clone());
                }
            }
        }
        (funnel_map, classified, ctx)
    }

}
