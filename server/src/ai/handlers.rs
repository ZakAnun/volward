use axum::extract::State;
use axum::http::HeaderMap;
use axum::Json;
use serde::{Deserialize, Serialize};
use volward_ai::AnalyzeCandidate;

use crate::auth::middleware::require_user;
use crate::error::AppError;
use crate::AppState;

use super::proxy::{debit_one_credit, model_name, refund_one_credit, run_upstream};

#[derive(Deserialize)]
pub struct AnalyzeRequest {
    pub candidates: Vec<AnalyzeCandidate>,
}

#[derive(Serialize)]
pub struct AnalyzeResponse {
    pub entries: Vec<volward_ai::AiVerdict>,
    pub credits_used: i64,
    pub credits_remaining: i64,
    pub model: String,
}

#[derive(Serialize)]
pub struct QuotaResponse {
    pub credits_remaining: i64,
    pub credits_total: i64,
}

pub async fn quota(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<QuotaResponse>, AppError> {
    let auth = require_user(&state, &headers)?;
    let uid = auth.require_user()?;
    let credits: (i64,) = sqlx::query_as("SELECT credits FROM users WHERE id = ?")
        .bind(uid)
        .fetch_one(&state.pool)
        .await?;
    Ok(Json(QuotaResponse {
        credits_remaining: credits.0,
        credits_total: credits.0,
    }))
}

pub async fn analyze(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<AnalyzeRequest>,
) -> Result<Json<AnalyzeResponse>, AppError> {
    let auth = require_user(&state, &headers)?;
    let uid = auth.require_user()?.to_string();
    if body.candidates.len() > 150 {
        return Err(AppError::BadRequest("candidates_exceed_150".into()));
    }
    if body.candidates.is_empty() {
        return Err(AppError::BadRequest("candidates_empty".into()));
    }

    debit_one_credit(
        &state.pool,
        &uid,
        &auth.device_id,
        body.candidates.len() as i64,
    )
    .await?;

    let upstream_result = run_upstream(&state.upstream, &body.candidates).await;
    match upstream_result {
        Ok(entries) => {
            let credits: (i64,) = sqlx::query_as("SELECT credits FROM users WHERE id = ?")
                .bind(&uid)
                .fetch_one(&state.pool)
                .await?;
            Ok(Json(AnalyzeResponse {
                entries,
                credits_used: 1,
                credits_remaining: credits.0,
                model: model_name().to_string(),
            }))
        }
        Err(e) => {
            let _ = refund_one_credit(&state.pool, &uid, &auth.device_id).await;
            Err(match e {
                AppError::BadGateway => AppError::BadGateway,
                other => other,
            })
        }
    }
}
