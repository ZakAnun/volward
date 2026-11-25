use crate::error::AppError;
use serde::{Deserialize, Serialize};
use volward_ai::{AnalyzeCandidate, AnalyzeTreeNode};

#[derive(Debug, Clone, Copy, Deserialize, Default, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AnalysisKind {
    #[default]
    Candidates,
    Tree,
}

#[derive(Deserialize)]
pub struct AnalyzeRequest {
    #[serde(default)]
    pub analysis_kind: AnalysisKind,
    #[serde(default)]
    pub candidates: Vec<AnalyzeCandidate>,
    #[serde(default)]
    pub tree_nodes: Vec<AnalyzeTreeNode>,
}

#[derive(Serialize)]
pub struct AnalyzeResponse {
    pub entries: Vec<volward_ai::AiVerdict>,
    pub credits_used: i64,
    pub credits_remaining: i64,
    pub model: String,
}

#[derive(Serialize)]
pub struct SynthesizeConclusionResponse {
    pub text: String,
}

#[derive(Serialize)]
pub struct QuotaResponse {
    pub credits_remaining: i64,
    pub credits_total: i64,
}

impl AnalyzeRequest {
    pub(super) fn validate(&self) -> Result<(), AppError> {
        match self.analysis_kind {
            AnalysisKind::Candidates => {
                if self.candidates.len() > 150 {
                    return Err(AppError::BadRequest("candidates_exceed_150".into()));
                }
                if self.candidates.is_empty() {
                    return Err(AppError::BadRequest("candidates_empty".into()));
                }
                ()
            }
            AnalysisKind::Tree => {
                if self.tree_nodes.len() > 150 {
                    return Err(AppError::BadRequest("tree_nodes_exceed_150".into()));
                }
                if self.tree_nodes.is_empty() {
                    return Err(AppError::BadRequest("tree_nodes_empty".into()));
                }
                ()
            }
        };

        Ok(())
    }
}
