use super::*;

impl VolwardEngine {
    pub fn is_scan_running(&self) -> bool {
        self.is_scanning.load(Ordering::Relaxed)
    }

    pub fn start_scan(&self, job_id: String, roots: Vec<String>, incremental: bool) -> String {
        // Reject if a scan is already in progress (defense-in-depth —
        // Dart callers use start_scan_async, but blocking path is also
        // exposed through C FFI).
        if self
            .is_scanning
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::Relaxed)
            .is_err()
        {
            return "error:scan already in progress".to_string();
        }

        self.invalidate_index_load();
        self.cancel.store(false, Ordering::Release);
        self.persist_pause.store(false, Ordering::Release);
        let classifier = load_classifier(self.platform.as_ref());
        let orchestrator = ScanOrchestrator::new(self.platform.as_ref(), classifier);
        let cancel = self.cancel.clone();
        let last_snapshot = self.last_snapshot.clone();
        let last_progress = self.last_progress.clone();

        let result = orchestrator.run_scan(
            job_id,
            roots,
            incremental,
            &cancel,
            |progress| {
                if let Ok(mut g) = last_progress.lock() {
                    *g = Some(progress);
                }
            },
            |_checkpoint| {},
        );

        self.is_scanning.store(false, Ordering::Relaxed);

        match result {
            Ok(snapshot) => {
                let id = snapshot.snapshot_id.clone();
                if let Ok(mut g) = last_snapshot.lock() {
                    *g = Some(snapshot);
                }
                id
            }
            Err(e) => format!("error:{e}"),
        }
    }

    pub fn start_scan_async(
        &self,
        job_id: String,
        roots: Vec<String>,
        incremental: bool,
    ) -> String {
        // Reject if a scan is already in progress.
        if self
            .is_scanning
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::Relaxed)
            .is_err()
        {
            return "error:scan already in progress".to_string();
        }

        // Clear any prior cancel request so a new async scan is not aborted
        // immediately when the shared main engine is reused after cancel.
        self.invalidate_index_load();
        self.cancel.store(false, Ordering::Release);
        self.persist_pause.store(false, Ordering::Release);
        if let Ok(mut error) = self.last_pause_error.lock() {
            *error = None;
        }

        let platform = self.platform.clone();
        let cancel = self.cancel.clone();
        let persist_pause = self.persist_pause.clone();
        let last_pause_error = self.last_pause_error.clone();
        let last_snapshot = self.last_snapshot.clone();
        let last_index = self.last_index.clone();
        let last_progress = self.last_progress.clone();
        let last_checkpoint = self.last_checkpoint.clone();
        let is_scanning = self.is_scanning.clone();
        let index_version = self.index_version.clone();
        let scan_handle = self._scan_handle.clone();

        let job_id_clone = job_id.clone();

        let handle = std::thread::spawn(move || {
            let classifier = load_classifier_from_arc(&platform);
            let orchestrator = ScanOrchestrator::new(platform.as_ref(), classifier)
                .with_pause_signal(persist_pause.clone());
            match orchestrator.run_index_scan(
                job_id_clone,
                roots,
                incremental,
                &cancel,
                false,
                |progress| {
                    if let Ok(mut g) = last_progress.lock() {
                        *g = Some(progress);
                    }
                },
            ) {
                Ok(mut index) => {
                    // A cancelled walk returns a truncated catalog. Keep any prior
                    // good index so Dart (which still shows the previous snapshot)
                    // does not suddenly query/delete against partial results.
                    if index.scan_state == "Cancelled" {
                        // leave last_index / last_snapshot unchanged
                    } else {
                        let version = index_version.fetch_add(1, Ordering::Relaxed) + 1;
                        index.version = version;
                        if let Ok(mut g) = last_index.lock() {
                            *g = Some(Arc::new(index));
                        }
                        if let Ok(mut g) = last_snapshot.lock() {
                            *g = None;
                        }
                        if let Ok(mut g) = last_checkpoint.lock() {
                            *g = None;
                        }
                    }
                }
                Err(error) => {
                    if persist_pause.load(Ordering::Acquire) {
                        if let Ok(mut last_error) = last_pause_error.lock() {
                            *last_error = Some(error.to_string());
                        }
                    }
                    // snapshot stays None; caller should check via get_last_snapshot
                }
            }
            is_scanning.store(false, Ordering::Relaxed);
        });

        if let Ok(mut g) = scan_handle.lock() {
            *g = Some(handle);
        }

        job_id
    }

    pub fn cancel_scan(&self) {
        self.persist_pause.store(false, Ordering::Release);
        self.cancel.store(true, Ordering::Release);
    }

    pub fn pause_current_scan(&self) {
        self.persist_pause.store(true, Ordering::Release);
        self.cancel.store(true, Ordering::Release);
    }

    pub fn get_last_pause_error(&self) -> Option<String> {
        self.last_pause_error
            .lock()
            .ok()
            .and_then(|error| error.clone())
    }

    pub fn get_last_snapshot(&self) -> Option<StorageSnapshot> {
        self.last_snapshot.lock().ok().and_then(|g| g.clone())
    }

    pub fn get_last_progress(&self) -> Option<ScanProgress> {
        self.last_progress.lock().ok().and_then(|g| g.clone())
    }

}
