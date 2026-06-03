use std::sync::atomic::AtomicBool;
use std::time::{SystemTime, UNIX_EPOCH};

use uuid::Uuid;

use crate::classify::Classifier;
use crate::model::{PlatformCapabilities, ScanPhase, ScanProgress, StorageSnapshot};
use crate::platform::{PlatformError, PlatformStorage, WalkAction};

const MAX_ENTRIES: usize = 500;

pub struct ScanOrchestrator<'a> {
    platform: &'a dyn PlatformStorage,
    classifier: Classifier,
}

impl<'a> ScanOrchestrator<'a> {
    pub fn new(platform: &'a dyn PlatformStorage, classifier: Classifier) -> Self {
        Self {
            platform,
            classifier,
        }
    }

    pub fn probe(&self) -> PlatformCapabilities {
        self.platform.probe_capabilities()
    }

    pub fn run_scan(
        &self,
        job_id: String,
        user_selected: Vec<String>,
        cancel: &AtomicBool,
        mut on_progress: impl FnMut(ScanProgress),
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
        let mut entries = Vec::new();
        let mut paths_seen = 0u64;
        let mut bytes_seen = 0u64;
        let mut warnings = Vec::new();

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
            paths_seen += 1;
            bytes_seen = bytes_seen.saturating_add(e.size_bytes);
            last_path = Some(e.path.clone());
            progress_counter += 1;
            // Throttled progress — emit every 500 entries so the poll loop
            // can show live paths_seen / current_path without choking.
            if progress_counter % 500 == 0 {
                on_progress(ScanProgress {
                    job_id: job_id.clone(),
                    phase: ScanPhase::Walking,
                    paths_seen,
                    bytes_seen,
                    current_path: last_path.clone(),
                });
            }
            if entries.len() < MAX_ENTRIES && !e.is_dir {
                let classified =
                    self.classifier
                        .classify_path(&e.path, e.size_bytes, e.is_dir, &job_id);
                entries.push(classified);
            }
            WalkAction::Continue
        };

        if let Err(err) = self.platform.walk_entries(&roots, cancel, &mut walk) {
            match err {
                PlatformError::Cancelled => {
                    warnings.push("Scan cancelled.".to_string());
                }
                other => return Err(other),
            }
        }

        on_progress(ScanProgress {
            job_id: job_id.clone(),
            phase: ScanPhase::Aggregating,
            paths_seen,
            bytes_seen,
            current_path: last_path,
        });

        entries.sort_by(|a, b| b.size_bytes.cmp(&a.size_bytes));

        let vol = roots
            .first()
            .and_then(|r| self.platform.volume_stats(r).ok())
            .unwrap_or(crate::model::VolumeStats {
                total_bytes: 0,
                available_bytes: 0,
            });

        let reclaimable = entries
            .iter()
            .filter(|e| e.deletable)
            .map(|e| e.size_bytes)
            .sum();

        on_progress(ScanProgress {
            job_id: job_id.clone(),
            phase: ScanPhase::Done,
            paths_seen,
            bytes_seen,
            current_path: None,
        });

        Ok(StorageSnapshot {
            snapshot_id: Uuid::new_v4().to_string(),
            scanned_at_ms: unix_ms(),
            capability: caps.level,
            volume_total_bytes: vol.total_bytes,
            volume_used_bytes: vol.total_bytes.saturating_sub(vol.available_bytes),
            reclaimable_estimate_bytes: reclaimable,
            entries,
            warnings,
        })
    }
}

fn unix_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}
