use std::collections::HashMap;
use std::fmt;
use std::sync::Arc;

use serde::Serialize;

use crate::{
    AnalysisOptions, Capability, CapabilityAnalysisPhase, CapabilityAnalysisResult,
    SnapshotIndex, CAPABILITY_SCHEMA_VERSION,
};

/// Progress/cancellation view handed to analyzers for long-running work
/// (content hashing, image decoding). Cheap analyzers may ignore it.
pub trait CapabilityProgressSink: Send + Sync {
    fn report(
        &self,
        phase: CapabilityAnalysisPhase,
        processed: u64,
        total: u64,
        current_path: Option<String>,
    );

    fn is_cancelled(&self) -> bool;
}

/// No-op sink for synchronous analysis paths without a job handle.
pub struct NoopProgressSink;

impl CapabilityProgressSink for NoopProgressSink {
    fn report(
        &self,
        _phase: CapabilityAnalysisPhase,
        _processed: u64,
        _total: u64,
        _current_path: Option<String>,
    ) {
    }

    fn is_cancelled(&self) -> bool {
        false
    }
}

pub trait CapabilityAnalyzer: Send + Sync {
    fn capability(&self) -> Capability;

    fn analyze(
        &self,
        index: &SnapshotIndex,
        normalized_root: &str,
        options: &AnalysisOptions,
        progress: &dyn CapabilityProgressSink,
    ) -> Result<CapabilityAnalysisResult, CapabilityAnalysisError>;
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct CapabilityAnalysisError {
    pub code: String,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub capability: Option<Capability>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub snapshot_id: Option<String>,
}

impl CapabilityAnalysisError {
    pub fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
            capability: None,
            snapshot_id: None,
        }
    }

    pub fn for_request(
        code: impl Into<String>,
        message: impl Into<String>,
        capability: Capability,
        snapshot_id: impl Into<String>,
    ) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
            capability: Some(capability),
            snapshot_id: Some(snapshot_id.into()),
        }
    }

    pub fn unsupported(capability: Capability, snapshot_id: &str) -> Self {
        Self::for_request(
            "unsupported_capability",
            format!("capability {capability:?} is not implemented"),
            capability,
            snapshot_id,
        )
    }

    pub fn invalid_result(
        capability: Capability,
        snapshot_id: &str,
        message: impl Into<String>,
    ) -> Self {
        Self::for_request(
            "invalid_result",
            message,
            capability,
            snapshot_id,
        )
    }
}

impl fmt::Display for CapabilityAnalysisError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}: {}", self.code, self.message)
    }
}

impl std::error::Error for CapabilityAnalysisError {}

#[derive(Clone, Default)]
pub struct CapabilityRegistry {
    analyzers: HashMap<Capability, Arc<dyn CapabilityAnalyzer>>,
}

impl CapabilityRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn register(&mut self, analyzer: Arc<dyn CapabilityAnalyzer>) {
        self.analyzers.insert(analyzer.capability(), analyzer);
    }

    pub fn supports(&self, capability: Capability) -> bool {
        self.analyzers.contains_key(&capability)
    }

    pub fn analyze(
        &self,
        index: &SnapshotIndex,
        snapshot_id: &str,
        capability: Capability,
        options: &AnalysisOptions,
        progress: &dyn CapabilityProgressSink,
    ) -> Result<CapabilityAnalysisResult, CapabilityAnalysisError> {
        if index.snapshot_id != snapshot_id {
            return Err(CapabilityAnalysisError::for_request(
                "snapshot_mismatch",
                format!(
                    "requested snapshot {snapshot_id} does not match current snapshot {}",
                    index.snapshot_id
                ),
                capability,
                snapshot_id,
            ));
        }
        options.validate(capability).map_err(|error| {
            CapabilityAnalysisError::for_request(
                "invalid_options",
                error.to_string(),
                capability,
                snapshot_id,
            )
        })?;
        let analyzer = self
            .analyzers
            .get(&capability)
            .ok_or_else(|| CapabilityAnalysisError::unsupported(capability, snapshot_id))?;
        let normalized_root = normalize_root(&options.root_path, &index.root_path);
        let result = analyzer.analyze(index, &normalized_root, options, progress)?;
        validate_result(&result, snapshot_id, capability, &normalized_root)?;
        Ok(result)
    }
}

fn validate_result(
    result: &CapabilityAnalysisResult,
    snapshot_id: &str,
    capability: Capability,
    normalized_root: &str,
) -> Result<(), CapabilityAnalysisError> {
    let invalid = |message| {
        CapabilityAnalysisError::invalid_result(capability, snapshot_id, message)
    };
    if result.schema_version != CAPABILITY_SCHEMA_VERSION {
        return Err(invalid(format!(
            "schema_version must be {CAPABILITY_SCHEMA_VERSION}, got {}",
            result.schema_version
        )));
    }
    if result.capability != capability {
        return Err(invalid(
            "result capability does not match the request".to_string(),
        ));
    }
    if result.snapshot_id != snapshot_id {
        return Err(invalid(
            "result snapshot_id does not match the request".to_string(),
        ));
    }
    if result.root_path != normalized_root {
        return Err(invalid(
            "result root_path is not the normalized request root".to_string(),
        ));
    }
    if result.deletion_plan.snapshot_id != snapshot_id {
        return Err(invalid(
            "deletion_plan snapshot_id does not match the request".to_string(),
        ));
    }
    let wire = serde_json::to_value(result)
        .map_err(|error| invalid(format!("result serialization failed: {error}")))?;
    serde_json::from_value::<CapabilityAnalysisResult>(wire)
        .map_err(|error| invalid(format!("result schema validation failed: {error}")))?;
    Ok(())
}

fn normalize_root(root_path: &str, index_root: &str) -> String {
    let source = if root_path.is_empty() {
        index_root
    } else {
        root_path
    };
    let replaced = source.replace('\\', "/");
    let unc = replaced.starts_with("//");
    let mut parts = replaced.split('/').filter(|part| !part.is_empty());
    let mut normalized = if unc {
        "//".to_string()
    } else if replaced.starts_with('/') {
        "/".to_string()
    } else {
        String::new()
    };
    if let Some(first) = parts.next() {
        normalized.push_str(first);
        for part in parts {
            if !normalized.ends_with('/') {
                normalized.push('/');
            }
            normalized.push_str(part);
        }
    }
    if normalized.len() == 2 && normalized.ends_with(':') {
        normalized.push('/');
    }
    normalized
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Mutex};

    use crate::{
        AnalysisOptions, AnalysisSummary, Capability, CapabilityAnalysisError,
        CapabilityAnalysisResult, CapabilityAnalyzer, CapabilityLevel, CapabilityProgressSink,
        CapabilityRegistry, DeletionPlan, NoopProgressSink, ScanStats, ScanTreeNode,
        SnapshotIndex, StorageSnapshot, CAPABILITY_SCHEMA_VERSION,
    };

    struct FakeAnalyzer {
        observed_root: Arc<Mutex<Option<String>>>,
    }

    impl CapabilityAnalyzer for FakeAnalyzer {
        fn capability(&self) -> Capability {
            Capability::LargeFiles
        }

        fn analyze(
            &self,
            index: &SnapshotIndex,
            normalized_root: &str,
            _options: &AnalysisOptions,
            _progress: &dyn CapabilityProgressSink,
        ) -> Result<CapabilityAnalysisResult, CapabilityAnalysisError> {
            *self.observed_root.lock().unwrap() = Some(normalized_root.to_string());
            Ok(result(index, normalized_root))
        }
    }

    #[test]
    fn registered_analyzer_receives_normalized_root() {
        let observed_root = Arc::new(Mutex::new(None));
        let mut registry = CapabilityRegistry::new();
        registry.register(Arc::new(FakeAnalyzer {
            observed_root: observed_root.clone(),
        }));
        let index = fixture_index();
        let options = AnalysisOptions {
            root_path: r"\root\folder\".to_string(),
            ..AnalysisOptions::default()
        };

        let analysis = registry
            .analyze(
                &index,
                "snapshot-1",
                Capability::LargeFiles,
                &options,
                &NoopProgressSink,
            )
            .expect("registered analyzer should run");

        assert_eq!(observed_root.lock().unwrap().as_deref(), Some("/root/folder"));
        assert_eq!(analysis.root_path, "/root/folder");
    }

    #[test]
    fn unknown_capability_returns_structured_unsupported_error() {
        let error = CapabilityRegistry::new()
            .analyze(
                &fixture_index(),
                "snapshot-1",
                Capability::DuplicateFiles,
                &AnalysisOptions::default(),
                &NoopProgressSink,
            )
            .expect_err("unregistered capability should be unsupported");

        assert_eq!(error.code, "unsupported_capability");
        assert_eq!(error.capability, Some(Capability::DuplicateFiles));
        let json = serde_json::to_value(error).unwrap();
        assert_eq!(json["code"], "unsupported_capability");
        assert_eq!(json["capability"], "duplicate_files");
    }

    #[test]
    fn analyzer_result_must_match_requested_contract() {
        struct WrongSnapshotAnalyzer;

        impl CapabilityAnalyzer for WrongSnapshotAnalyzer {
            fn capability(&self) -> Capability {
                Capability::LargeFiles
            }

            fn analyze(
                &self,
                index: &SnapshotIndex,
                normalized_root: &str,
                _options: &AnalysisOptions,
                _progress: &dyn CapabilityProgressSink,
            ) -> Result<CapabilityAnalysisResult, CapabilityAnalysisError> {
                let mut result = result(index, normalized_root);
                result.snapshot_id = "stale-snapshot".to_string();
                Ok(result)
            }
        }

        let mut registry = CapabilityRegistry::new();
        registry.register(Arc::new(WrongSnapshotAnalyzer));
        let error = registry
            .analyze(
                &fixture_index(),
                "snapshot-1",
                Capability::LargeFiles,
                &AnalysisOptions::default(),
                &NoopProgressSink,
            )
            .expect_err("mismatched result should be rejected");

        assert_eq!(error.code, "invalid_result");
    }

    fn fixture_index() -> SnapshotIndex {
        SnapshotIndex::from(&StorageSnapshot {
            snapshot_id: "snapshot-1".to_string(),
            scanned_at_ms: 1,
            capability: CapabilityLevel::FullPath,
            volume_total_bytes: 100,
            volume_used_bytes: 50,
            reclaimable_estimate_bytes: 0,
            entries: vec![],
            tree: ScanTreeNode {
                name: "root".to_string(),
                path: "/root".to_string(),
                is_dir: true,
                size_bytes: 0,
                entry_id: None,
                children: vec![],
            },
            stats: ScanStats::default(),
            warnings: vec![],
        })
    }

    fn result(index: &SnapshotIndex, root_path: &str) -> CapabilityAnalysisResult {
        CapabilityAnalysisResult {
            schema_version: CAPABILITY_SCHEMA_VERSION,
            capability: Capability::LargeFiles,
            snapshot_id: index.snapshot_id.clone(),
            root_path: root_path.to_string(),
            analyzer_version: "fake-v1".to_string(),
            generated_at_ms: 1,
            capability_level: CapabilityLevel::FullPath,
            summary: AnalysisSummary::default(),
            groups: vec![],
            next_cursor: None,
            deletion_plan: DeletionPlan {
                snapshot_id: index.snapshot_id.clone(),
                target_count: 0,
                target_bytes: 0,
                targets: vec![],
                blocked_targets: vec![],
                requires_confirmation: true,
            },
            warnings: vec![],
        }
    }
}
