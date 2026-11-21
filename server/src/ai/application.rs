use super::proxy::{model_name, run_conclusion_upstream, run_tree_upstream, run_upstream};
use super::synthesize_request::SynthesizeConclusionRequest;
use super::types::{
    AnalysisKind, AnalyzeRequest, AnalyzeResponse, QuotaResponse, SynthesizeConclusionResponse,
};
use crate::{
    billing::{balance, debit_one_credit, refund_one_credit},
    error::AppError,
    AppState,
};

pub async fn quota(state: &AppState, uid: &str) -> Result<QuotaResponse, AppError> {
    let env = state.config.paddle_env.as_str();
    let remaining = balance(&state.pool, uid, env).await?;
    let total: (i64,) = sqlx::query_as(
        "SELECT COALESCE(SUM(credits_delta), 0) FROM transactions \
         WHERE user_id = ? AND kind IN ('purchase', 'topup') AND paddle_env = ?",
    )
    .bind(uid)
    .bind(env)
    .fetch_one(&state.pool)
    .await?;
    Ok(QuotaResponse {
        credits_remaining: remaining,
        credits_total: total.0,
    })
}

pub async fn synthesize_conclusion(
    state: &AppState,
    uid: &str,
    device_id: &str,
    body: SynthesizeConclusionRequest,
) -> Result<SynthesizeConclusionResponse, AppError> {
    let dir_len = body.directories.len();

    let user_json =
        serde_json::to_string(&body).map_err(|_| AppError::BadRequest("invalid_json".into()))?;
    let paddle_env = state.config.paddle_env.as_str();
    debit_one_credit(&state.pool, uid, device_id, dir_len as i64, paddle_env).await?;

    let upstream_result = run_conclusion_upstream(&state.upstream, &user_json).await;
    match upstream_result {
        Ok(text) => Ok(SynthesizeConclusionResponse { text }),
        Err(e) => {
            if let Err(refund_err) =
                refund_one_credit(&state.pool, uid, device_id, paddle_env).await
            {
                tracing::error!(
                    error = %refund_err,
                    user_id = %uid,
                    device_id = %device_id,
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
    state: &AppState,
    uid: &str,
    device_id: &str,
    body: AnalyzeRequest,
) -> Result<AnalyzeResponse, AppError> {
    let item_count = match body.analysis_kind {
        AnalysisKind::Candidates => body.candidates.len(),
        AnalysisKind::Tree => body.tree_nodes.len(),
    };

    let paddle_env = state.config.paddle_env.as_str();
    debit_one_credit(&state.pool, uid, device_id, item_count as i64, paddle_env).await?;

    let upstream_result = match body.analysis_kind {
        AnalysisKind::Candidates => run_upstream(&state.upstream, &body.candidates).await,
        AnalysisKind::Tree => run_tree_upstream(&state.upstream, &body.tree_nodes).await,
    };
    match upstream_result {
        Ok(entries) => {
            let remaining = balance(&state.pool, uid, paddle_env).await?;
            Ok(AnalyzeResponse {
                entries,
                credits_used: 1,
                credits_remaining: remaining,
                model: model_name().to_string(),
            })
        }
        Err(e) => {
            if let Err(refund_err) =
                refund_one_credit(&state.pool, uid, device_id, paddle_env).await
            {
                tracing::error!(
                    error = %refund_err,
                    user_id = %uid,
                    device_id = %device_id,
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
