use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use serde::Serialize;

use crate::{
    Capability, CapabilityAnalysisPhase, CapabilityAnalysisProgress,
    CapabilityAnalysisResult,
};
use crate::capability_registry::CapabilityProgressSink;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct CapabilityJobStatus {
    pub progress: CapabilityAnalysisProgress,
    pub result: Option<CapabilityAnalysisResult>,
}

struct CapabilityJobRecord {
    status: CapabilityJobStatus,
}

#[derive(Clone)]
pub struct CapabilityJobHandle {
    job_id: String,
    record: Arc<Mutex<CapabilityJobRecord>>,
}

impl CapabilityJobHandle {
    pub fn job_id(&self) -> &str {
        &self.job_id
    }

    pub fn update_progress(
        &self,
        phase: CapabilityAnalysisPhase,
        processed: u64,
        total: u64,
        current_path: Option<String>,
    ) {
        if let Ok(mut record) = self.record.lock() {
            if record.status.progress.cancelled
                || record.status.progress.phase == CapabilityAnalysisPhase::Completed
            {
                return;
            }
            record.status.progress.phase = phase;
            record.status.progress.processed = processed;
            record.status.progress.total = total;
            record.status.progress.current_path = current_path;
        }
    }

    pub fn is_cancelled(&self) -> bool {
        self.record
            .lock()
            .map(|record| record.status.progress.cancelled)
            .unwrap_or(true)
    }

    pub fn complete(&self, result: Option<CapabilityAnalysisResult>) {
        if let Ok(mut record) = self.record.lock() {
            if record.status.progress.cancelled {
                return;
            }
            record.status.progress.phase = CapabilityAnalysisPhase::Completed;
            record.status.progress.current_path = None;
            record.status.progress.error = None;
            record.status.result = result;
        }
    }

    pub fn fail(&self, error: String) {
        if let Ok(mut record) = self.record.lock() {
            if record.status.progress.cancelled {
                return;
            }
            record.status.progress.phase = CapabilityAnalysisPhase::Completed;
            record.status.progress.current_path = None;
            record.status.progress.error = Some(error);
            record.status.result = None;
        }
    }

    fn cancel(&self) -> bool {
        let Ok(mut record) = self.record.lock() else {
            return false;
        };
        if record.status.progress.phase == CapabilityAnalysisPhase::Completed {
            return false;
        }
        record.status.progress.cancelled = true;
        record.status.progress.current_path = None;
        record.status.result = None;
        true
    }
}

impl CapabilityProgressSink for CapabilityJobHandle {
    fn report(
        &self,
        phase: CapabilityAnalysisPhase,
        processed: u64,
        total: u64,
        current_path: Option<String>,
    ) {
        self.update_progress(phase, processed, total, current_path);
    }

    fn is_cancelled(&self) -> bool {
        CapabilityJobHandle::is_cancelled(self)
    }
}

#[derive(Clone, Default)]
pub struct CapabilityJobStore {
    jobs: Arc<Mutex<HashMap<String, CapabilityJobHandle>>>,
}

impl CapabilityJobStore {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn create(&self, snapshot_id: &str, capability: Capability) -> CapabilityJobHandle {
        let job_id = uuid::Uuid::new_v4().to_string();
        let handle = CapabilityJobHandle {
            job_id: job_id.clone(),
            record: Arc::new(Mutex::new(CapabilityJobRecord {
                status: CapabilityJobStatus {
                    progress: CapabilityAnalysisProgress {
                        job_id: job_id.clone(),
                        snapshot_id: snapshot_id.to_string(),
                        capability,
                        phase: CapabilityAnalysisPhase::Preparing,
                        processed: 0,
                        total: 0,
                        current_path: None,
                        cancelled: false,
                        error: None,
                    },
                    result: None,
                },
            })),
        };
        if let Ok(mut jobs) = self.jobs.lock() {
            jobs.insert(job_id, handle.clone());
        }
        handle
    }

    pub fn status(&self, job_id: &str) -> Option<CapabilityJobStatus> {
        let handle = self.jobs.lock().ok()?.get(job_id).cloned()?;
        handle.record.lock().ok().map(|record| record.status.clone())
    }

    pub fn cancel(&self, job_id: &str) -> bool {
        self.jobs
            .lock()
            .ok()
            .and_then(|jobs| jobs.get(job_id).cloned())
            .map(|job| job.cancel())
            .unwrap_or(false)
    }
}

#[cfg(test)]
mod tests {
    use crate::{Capability, CapabilityAnalysisPhase, CapabilityJobStore};

    #[test]
    fn job_tracks_progress_through_completion() {
        let jobs = CapabilityJobStore::new();
        let job = jobs.create("snapshot-1", Capability::DuplicateFiles);

        let initial = jobs.status(job.job_id()).expect("job status");
        assert_eq!(initial.progress.phase, CapabilityAnalysisPhase::Preparing);
        assert_eq!(initial.progress.processed, 0);

        job.update_progress(
            CapabilityAnalysisPhase::Hashing,
            3,
            10,
            Some("/root/a.bin".to_string()),
        );
        let hashing = jobs.status(job.job_id()).expect("hashing status");
        assert_eq!(hashing.progress.phase, CapabilityAnalysisPhase::Hashing);
        assert_eq!(hashing.progress.processed, 3);
        assert_eq!(hashing.progress.total, 10);
        assert_eq!(hashing.progress.current_path.as_deref(), Some("/root/a.bin"));

        job.complete(None);
        let completed = jobs.status(job.job_id()).expect("completed status");
        assert_eq!(completed.progress.phase, CapabilityAnalysisPhase::Completed);
        assert!(!completed.progress.cancelled);
        assert!(completed.progress.error.is_none());
    }

    #[test]
    fn cancellation_is_terminal_and_rejects_late_completion() {
        let jobs = CapabilityJobStore::new();
        let job = jobs.create("snapshot-1", Capability::SimilarPhotos);
        job.update_progress(
            CapabilityAnalysisPhase::Inspecting,
            1,
            2,
            Some("/root/photo.jpg".to_string()),
        );

        assert!(jobs.cancel(job.job_id()));
        assert!(job.is_cancelled());
        job.complete(None);

        let status = jobs.status(job.job_id()).expect("cancelled status");
        assert!(status.progress.cancelled);
        assert_eq!(status.progress.phase, CapabilityAnalysisPhase::Inspecting);
        assert!(status.result.is_none());
    }

    #[test]
    fn failed_job_keeps_structured_error_json() {
        let jobs = CapabilityJobStore::new();
        let job = jobs.create("snapshot-1", Capability::Applications);
        job.fail(r#"{"code":"snapshot_mismatch","message":"stale"}"#.to_string());

        let status = jobs.status(job.job_id()).expect("failed status");
        assert_eq!(status.progress.phase, CapabilityAnalysisPhase::Completed);
        assert_eq!(
            status.progress.error.as_deref(),
            Some(r#"{"code":"snapshot_mismatch","message":"stale"}"#)
        );
    }
}
