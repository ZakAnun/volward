use super::{application, synthesize_request::SynthesizeConclusionRequest};
use crate::{auth::require_user, error::AppError, AppState};
use axum::{extract::State, http::HeaderMap, Json};
// Preserve the existing public HTTP DTO paths for callers.
pub use super::types::{
    AnalysisKind, AnalyzeRequest, AnalyzeResponse, QuotaResponse, SynthesizeConclusionResponse,
};

pub async fn quota(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<QuotaResponse>, AppError> {
    let auth = require_user(&state, &headers)?;
    let uid = auth.require_user()?;
    application::quota(&state, uid).await.map(Json)
}

pub async fn synthesize_conclusion(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<SynthesizeConclusionRequest>,
) -> Result<Json<SynthesizeConclusionResponse>, AppError> {
    let auth = require_user(&state, &headers)?;
    let uid = auth.require_user()?;
    body.validate()?;
    application::synthesize_conclusion(&state, uid, &auth.device_id, body)
        .await
        .map(Json)
}

pub async fn analyze(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<AnalyzeRequest>,
) -> Result<Json<AnalyzeResponse>, AppError> {
    let auth = require_user(&state, &headers)?;
    let uid = auth.require_user()?;
    body.validate()?;
    application::analyze(&state, uid, &auth.device_id, body)
        .await
        .map(Json)
}
