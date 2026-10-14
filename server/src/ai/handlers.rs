use axum::extract::State;
use axum::http::HeaderMap;
use axum::Json;
use serde::{Deserialize, Serialize};
use volward_ai::{AnalyzeCandidate, AnalyzeTreeNode};

use crate::auth::middleware::require_user;
use crate::error::AppError;
use crate::AppState;

use super::proxy::{
    debit_one_credit, model_name, refund_one_credit, run_conclusion_upstream, run_tree_upstream,
    run_upstream,
};
use super::synthesize_request::SynthesizeConclusionRequest;
use crate::billing::env_credits::balance_for_env;

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

pub async fn quota(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<QuotaResponse>, AppError> {
    let auth = require_user(&state, &headers)?;
    let uid = auth.require_user()?;
    let env = state.config.paddle_env.as_str();
    let balances: (i64, i64) = sqlx::query_as(
        "SELECT credits_sandbox, credits_live FROM users WHERE id = ?",
    )
    .bind(uid)
    .fetch_one(&state.pool)
    .await?;
    let remaining = balance_for_env(balances.0, balances.1, env)?;
    let total: (i64,) = sqlx::query_as(
        "SELECT COALESCE(SUM(credits_delta), 0) FROM transactions \
         WHERE user_id = ? AND kind IN ('purchase', 'topup') AND paddle_env = ?",
    )
    .bind(uid)
    .bind(env)
    .fetch_one(&state.pool)
    .await?;
    Ok(Json(QuotaResponse {
        credits_remaining: remaining,
        credits_total: total.0,
    }))
}

pub async fn synthesize_conclusion(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<SynthesizeConclusionRequest>,
) -> Result<Json<SynthesizeConclusionResponse>, AppError> {
    let auth = require_user(&state, &headers)?;
    let uid = auth.require_user()?.to_string();

    body.validate()?;
    let dir_len = body.directories.len();

    let user_json =
        serde_json::to_string(&body).map_err(|_| AppError::BadRequest("invalid_json".into()))?;
    let paddle_env = state.config.paddle_env.as_str();
    debit_one_credit(
        &state.pool,
        &uid,
        &auth.device_id,
        dir_len as i64,
        paddle_env,
    )
    .await?;

    let upstream_result = run_conclusion_upstream(&state.upstream, &user_json).await;
    match upstream_result {
        Ok(text) => Ok(Json(SynthesizeConclusionResponse { text })),
        Err(e) => {
            if let Err(refund_err) =
                refund_one_credit(&state.pool, &uid, &auth.device_id, paddle_env).await
            {
                tracing::error!(
                    error = %refund_err,
                    user_id = %uid,
                    device_id = %auth.device_id,
                    "failed to refund credit after upstream synthesize error; manual topup required"
                );
            }
            Err(match e {
                AppError::BadGateway => AppError::BadGateway,
                other => other,
            })
        }
    }
}

pub async fn analyze(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<AnalyzeRequest>,
) -> Result<Json<AnalyzeResponse>, AppError> {
    let auth = require_user(&state, &headers)?;
    let uid = auth.require_user()?.to_string();

    let item_count = match body.analysis_kind {
        AnalysisKind::Candidates => {
            if body.candidates.len() > 150 {
                return Err(AppError::BadRequest("candidates_exceed_150".into()));
            }
            if body.candidates.is_empty() {
                return Err(AppError::BadRequest("candidates_empty".into()));
            }
            body.candidates.len()
        }
        AnalysisKind::Tree => {
            if body.tree_nodes.len() > 150 {
                return Err(AppError::BadRequest("tree_nodes_exceed_150".into()));
            }
            if body.tree_nodes.is_empty() {
                return Err(AppError::BadRequest("tree_nodes_empty".into()));
            }
            body.tree_nodes.len()
        }
    };

    let paddle_env = state.config.paddle_env.as_str();
    debit_one_credit(
        &state.pool,
        &uid,
        &auth.device_id,
        item_count as i64,
        paddle_env,
    )
    .await?;

    let upstream_result = match body.analysis_kind {
        AnalysisKind::Candidates => run_upstream(&state.upstream, &body.candidates).await,
        AnalysisKind::Tree => run_tree_upstream(&state.upstream, &body.tree_nodes).await,
    };
    match upstream_result {
        Ok(entries) => {
            let balances: (i64, i64) = sqlx::query_as(
                "SELECT credits_sandbox, credits_live FROM users WHERE id = ?",
            )
            .bind(&uid)
            .fetch_one(&state.pool)
            .await?;
            let remaining = balance_for_env(balances.0, balances.1, paddle_env)?;
            Ok(Json(AnalyzeResponse {
                entries,
                credits_used: 1,
                credits_remaining: remaining,
                model: model_name().to_string(),
            }))
        }
        Err(e) => {
            if let Err(refund_err) =
                refund_one_credit(&state.pool, &uid, &auth.device_id, paddle_env).await
            {
                tracing::error!(
                    error = %refund_err,
                    user_id = %uid,
                    device_id = %auth.device_id,
                    "failed to refund credit after upstream analyze error; manual topup required"
                );
            }
            Err(match e {
                AppError::BadGateway => AppError::BadGateway,
                other => other,
            })
        }
    }
}
