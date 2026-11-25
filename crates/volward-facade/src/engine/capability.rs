use super::*;

impl VolwardEngine {
    // ------------------------------------------------------------------
    // Capability analysis (registry + async job state)

    /// Synchronous capability analysis against the current index. Returns
    /// `{"result": <CapabilityAnalysisResult>}` or `{"error": {...}}`.
    pub fn analyze_capability_json(
        &self,
        snapshot_id: &str,
        capability: &str,
        options_json: &str,
    ) -> String {
        let Some(capability) = parse_capability(capability) else {
            return capability_error_json(&CapabilityAnalysisError::new(
                "invalid_capability",
                format!("unknown capability {capability:?}"),
            ));
        };
        let options = match parse_capability_options(options_json, capability, snapshot_id) {
            Ok(options) => options,
            Err(error) => return capability_error_json(&error),
        };
        let registry = match self.capability_registry.lock() {
            Ok(registry) => registry.clone(),
            Err(_) => {
                return capability_error_json(&CapabilityAnalysisError::new(
                    "internal_error",
                    "capability registry lock poisoned",
                ));
            }
        };
        let Some(index) = self.current_index() else {
            return capability_error_json(&CapabilityAnalysisError::for_request(
                "no_snapshot",
                "no snapshot or index loaded",
                capability,
                snapshot_id,
            ));
        };
        match registry.analyze(&index, snapshot_id, capability, &options, &NoopProgressSink) {
            Ok(result) => serde_json::json!({ "result": result }).to_string(),
            Err(error) => capability_error_json(&error),
        }
    }

    /// Starts an async capability job on a worker thread and returns
    /// `{"job_id": "..."}` or `{"error": {...}}`.
    pub fn start_capability_analysis_json(
        &self,
        snapshot_id: &str,
        capability: &str,
        options_json: &str,
    ) -> String {
        let Some(capability) = parse_capability(capability) else {
            return capability_error_json(&CapabilityAnalysisError::new(
                "invalid_capability",
                format!("unknown capability {capability:?}"),
            ));
        };
        let options = match parse_capability_options(options_json, capability, snapshot_id) {
            Ok(options) => options,
            Err(error) => return capability_error_json(&error),
        };
        let snapshot_matches = self
            .current_index()
            .as_ref()
            .map(|index| index.snapshot_id == snapshot_id)
            .unwrap_or(false);
        if !snapshot_matches {
            return capability_error_json(&CapabilityAnalysisError::for_request(
                "snapshot_mismatch",
                format!("requested snapshot {snapshot_id} does not match the current index"),
                capability,
                snapshot_id,
            ));
        }
        let registry = match self.capability_registry.lock() {
            Ok(registry) => registry.clone(),
            Err(_) => {
                return capability_error_json(&CapabilityAnalysisError::new(
                    "internal_error",
                    "capability registry lock poisoned",
                ));
            }
        };
        if !registry.supports(capability) {
            return capability_error_json(&CapabilityAnalysisError::unsupported(
                capability,
                snapshot_id,
            ));
        }
        if self.capability_jobs.active_count() >= MAX_CONCURRENT_CAPABILITY_JOBS {
            return capability_error_json(&CapabilityAnalysisError::for_request(
                "busy",
                "too many capability jobs in flight; retry after one completes",
                capability,
                snapshot_id,
            ));
        }

        let job_handle = self.capability_jobs.create(snapshot_id, capability);
        let job_id = job_handle.job_id().to_string();
        let job_id_inner = job_id.clone();
        let index = self.last_index.clone();
        let job_snapshot = snapshot_id.to_string();
        let job_capability = capability;
        let job_options = options;

        std::thread::spawn(move || {
            job_handle.update_progress(CapabilityAnalysisPhase::Inspecting, 0, 0, None);
            let result = (|| {
                // Clone the index out of the lock so long-running analyzers
                // never stall concurrent FFI (snapshot refresh, status polls).
                let current = index
                    .lock()
                    .map_err(|_| {
                        CapabilityAnalysisError::new("internal_error", "index lock poisoned")
                    })?
                    .clone()
                    .ok_or_else(|| {
                        CapabilityAnalysisError::for_request(
                            "no_snapshot",
                            "no snapshot or index loaded",
                            job_capability,
                            &job_snapshot,
                        )
                    })?;
                if current.snapshot_id != job_snapshot {
                    return Err(CapabilityAnalysisError::for_request(
                        "snapshot_mismatch",
                        format!(
                            "requested snapshot {job_snapshot} does not match the current index {}",
                            current.snapshot_id
                        ),
                        job_capability,
                        &job_snapshot,
                    ));
                }
                registry.analyze(
                    &current,
                    &job_snapshot,
                    job_capability,
                    &job_options,
                    &job_handle,
                )
            })();

            if job_handle.is_cancelled() {
                return;
            }
            match result {
                Ok(analysis) => {
                    // Revalidate the snapshot after analysis: a refresh during
                    // the run must invalidate the job instead of producing a
                    // deletion plan against a stale snapshot.
                    let current_snapshot = index
                        .lock()
                        .ok()
                        .and_then(|guard| guard.as_ref().map(|i| i.snapshot_id.clone()));
                    if current_snapshot.as_deref() != Some(job_snapshot.as_str()) {
                        job_handle.fail(
                            serde_json::json!({
                                "code": "snapshot_mismatch",
                                "message": format!(
                                    "snapshot changed while capability job {job_id_inner} was running"
                                ),
                                "capability": job_capability,
                                "snapshot_id": job_snapshot,
                            })
                            .to_string(),
                        );
                        return;
                    }
                    job_handle.complete(Some(analysis));
                }
                Err(error) => {
                    let error_json = serde_json::to_string(&error).unwrap_or_else(|_| {
                        "{\"code\":\"internal_error\",\"message\":\"error serialization failed\"}"
                            .to_string()
                    });
                    job_handle.fail(error_json);
                }
            }
        });

        serde_json::json!({ "job_id": job_id }).to_string()
    }

    /// Current job status as `{"progress": ..., "result": ...}` or an error envelope.
    pub fn get_capability_job_status_json(&self, job_id: &str) -> String {
        match self.capability_jobs.status(job_id) {
            Some(status) => serde_json::to_string(&status).unwrap_or_else(|_| {
                capability_error_json(&CapabilityAnalysisError::new(
                    "internal_error",
                    "job status serialization failed",
                ))
            }),
            None => capability_error_json(&CapabilityAnalysisError::new(
                "job_not_found",
                format!("no capability job with id {job_id}"),
            )),
        }
    }

    pub fn cancel_capability_analysis(&self, job_id: &str) -> bool {
        self.capability_jobs.cancel(job_id)
    }

}
