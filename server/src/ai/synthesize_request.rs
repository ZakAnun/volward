use crate::error::AppError;

const MAX_SESSION_ID: usize = 128;
const MAX_LOCALE: usize = 16;
const MAX_LABEL: usize = 256;
const MAX_PATH: usize = 4096;
const MAX_HIGHLIGHT: usize = 500;
const MAX_HIGHLIGHTS_PER_DIR: usize = 5;
pub const MAX_DIRECTORIES: usize = 12;

#[derive(Debug, serde::Deserialize, serde::Serialize)]
pub struct SynthesizeConclusionRequest {
    pub schema_version: i64,
    pub analysis_session_id: String,
    pub locale: String,
    pub root_label: String,
    pub scan: serde_json::Value,
    pub totals: serde_json::Value,
    pub directories: Vec<SynthesizeDirectory>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize)]
pub struct SynthesizeDirectory {
    pub path: String,
    pub display_label: String,
    pub safe_bytes: i64,
    pub review_count: i64,
    pub keep_count: i64,
    pub share_of_safe_pct: f64,
    pub reason_highlights: Vec<String>,
}

impl SynthesizeConclusionRequest {
    pub fn validate(&self) -> Result<(), AppError> {
        if self.schema_version != 2 {
            return Err(AppError::BadRequest("schema_version_must_be_2".into()));
        }
        if self.analysis_session_id.is_empty()
            || self.analysis_session_id.len() > MAX_SESSION_ID
        {
            return Err(AppError::BadRequest("invalid_analysis_session_id".into()));
        }
        if self.locale.is_empty() || self.locale.len() > MAX_LOCALE {
            return Err(AppError::BadRequest("invalid_locale".into()));
        }
        if self.root_label.is_empty() || self.root_label.len() > MAX_LABEL {
            return Err(AppError::BadRequest("invalid_root_label".into()));
        }
        if self.directories.is_empty() {
            return Err(AppError::BadRequest("directories_empty".into()));
        }
        if self.directories.len() > MAX_DIRECTORIES {
            return Err(AppError::BadRequest("directories_exceed_12".into()));
        }
        for dir in &self.directories {
            if dir.path.is_empty() || dir.path.len() > MAX_PATH {
                return Err(AppError::BadRequest("invalid_directory_path".into()));
            }
            if dir.display_label.len() > MAX_LABEL {
                return Err(AppError::BadRequest("invalid_directory_label".into()));
            }
            if dir.reason_highlights.len() > MAX_HIGHLIGHTS_PER_DIR {
                return Err(AppError::BadRequest(
                    "reason_highlights_exceed_limit".into(),
                ));
            }
            for highlight in &dir.reason_highlights {
                if highlight.len() > MAX_HIGHLIGHT {
                    return Err(AppError::BadRequest("reason_highlight_too_long".into()));
                }
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_request(directories: Vec<SynthesizeDirectory>) -> SynthesizeConclusionRequest {
        SynthesizeConclusionRequest {
            schema_version: 2,
            analysis_session_id: "sess".into(),
            locale: "en".into(),
            root_label: "Home".into(),
            scan: serde_json::json!({}),
            totals: serde_json::json!({}),
            directories,
        }
    }

    #[test]
    fn rejects_empty_directories() {
        let req = sample_request(vec![]);
        assert!(req.validate().is_err());
    }

    #[test]
    fn rejects_long_highlight() {
        let req = sample_request(vec![SynthesizeDirectory {
            path: "/a".into(),
            display_label: "A".into(),
            safe_bytes: 1,
            review_count: 0,
            keep_count: 0,
            share_of_safe_pct: 100.0,
            reason_highlights: vec!["x".repeat(501)],
        }]);
        assert!(req.validate().is_err());
    }
}
