use async_trait::async_trait;
use std::sync::Arc;
use uuid::Uuid;

use volward_ai::{
    build_request_body, parse_response, split_batches, AiVerdict, AnalyzeCandidate, MODEL,
    UPSTREAM_ENDPOINT,
};

use crate::error::AppError;
use sqlx::SqlitePool;

#[async_trait]
pub trait UpstreamClient: Send + Sync {
    async fn complete(&self, request_body: String) -> Result<String, AppError>;
}

pub struct HttpUpstream {
    client: reqwest::Client,
    api_key: String,
}

impl HttpUpstream {
    pub fn new(api_key: String) -> Self {
        Self {
            client: reqwest::Client::new(),
            api_key,
        }
    }
}

#[async_trait]
impl UpstreamClient for HttpUpstream {
    async fn complete(&self, request_body: String) -> Result<String, AppError> {
        let res = self
            .client
            .post(UPSTREAM_ENDPOINT)
            .bearer_auth(&self.api_key)
            .header("Content-Type", "application/json")
            .body(request_body)
            .send()
            .await
            .map_err(|_| AppError::BadGateway)?;
        if !res.status().is_success() {
            return Err(AppError::BadGateway);
        }
        res.text().await.map_err(|_| AppError::BadGateway)
    }
}

pub async fn debit_one_credit(
    pool: &SqlitePool,
    user_id: &str,
    device_id: &str,
    candidate_count: i64,
    paddle_env: &str,
) -> Result<(), AppError> {
    let mut conn = pool.acquire().await?;
    sqlx::query("BEGIN IMMEDIATE")
        .execute(&mut *conn)
        .await?;
    let debit_sql = match paddle_env {
        "sandbox" => {
            "UPDATE users SET credits_sandbox = credits_sandbox - 1 WHERE id = ? AND credits_sandbox > 0"
        }
        "live" => {
            "UPDATE users SET credits_live = credits_live - 1 WHERE id = ? AND credits_live > 0"
        }
        _ => {
            let _ = sqlx::query("ROLLBACK").execute(&mut *conn).await;
            return Err(AppError::Internal("invalid_paddle_env".into()));
        }
    };
    let result = sqlx::query(debit_sql)
        .bind(user_id)
        .execute(&mut *conn)
        .await;
    let result = match result {
        Ok(r) => r,
        Err(e) => {
            let _ = sqlx::query("ROLLBACK").execute(&mut *conn).await;
            return Err(e.into());
        }
    };
    if result.rows_affected() == 0 {
        let _ = sqlx::query("ROLLBACK").execute(&mut *conn).await;
        return Err(AppError::PaymentRequired);
    }
    let tid = Uuid::new_v4().to_string();
    let now = chrono::Utc::now().timestamp_millis();
    if let Err(e) = sqlx::query(
        r#"
        INSERT INTO transactions (id, user_id, device_id, kind, credits_delta, candidate_count, paddle_env, created_at)
        VALUES (?, ?, ?, 'usage', -1, ?, ?, ?)
        "#,
    )
    .bind(&tid)
    .bind(user_id)
    .bind(device_id)
    .bind(candidate_count)
    .bind(paddle_env)
    .bind(now)
    .execute(&mut *conn)
    .await
    {
        let _ = sqlx::query("ROLLBACK").execute(&mut *conn).await;
        return Err(e.into());
    }
    sqlx::query("COMMIT").execute(&mut *conn).await?;
    Ok(())
}

pub async fn refund_one_credit(
    pool: &SqlitePool,
    user_id: &str,
    device_id: &str,
    paddle_env: &str,
) -> Result<(), AppError> {
    let mut conn = pool.acquire().await?;
    sqlx::query("BEGIN IMMEDIATE")
        .execute(&mut *conn)
        .await?;
    let refund_sql = match paddle_env {
        "sandbox" => "UPDATE users SET credits_sandbox = credits_sandbox + 1 WHERE id = ?",
        "live" => "UPDATE users SET credits_live = credits_live + 1 WHERE id = ?",
        _ => {
            let _ = sqlx::query("ROLLBACK").execute(&mut *conn).await;
            return Err(AppError::Internal("invalid_paddle_env".into()));
        }
    };
    if let Err(e) = sqlx::query(refund_sql)
        .bind(user_id)
        .execute(&mut *conn)
        .await
    {
        let _ = sqlx::query("ROLLBACK").execute(&mut *conn).await;
        return Err(e.into());
    }
    let tid = Uuid::new_v4().to_string();
    let now = chrono::Utc::now().timestamp_millis();
    if let Err(e) = sqlx::query(
        r#"
        INSERT INTO transactions (id, user_id, device_id, kind, credits_delta, paddle_env, created_at)
        VALUES (?, ?, ?, 'refund', 1, ?, ?)
        "#,
    )
    .bind(&tid)
    .bind(user_id)
    .bind(device_id)
    .bind(paddle_env)
    .bind(now)
    .execute(&mut *conn)
    .await
    {
        let _ = sqlx::query("ROLLBACK").execute(&mut *conn).await;
        return Err(e.into());
    }
    sqlx::query("COMMIT").execute(&mut *conn).await?;
    Ok(())
}

pub async fn run_upstream(
    upstream: &Arc<dyn UpstreamClient>,
    candidates: &[AnalyzeCandidate],
) -> Result<Vec<AiVerdict>, AppError> {
    let mut out = Vec::new();
    for batch in split_batches(candidates.to_vec()) {
        let body = build_request_body(&batch);
        let resp = upstream.complete(body).await?;
        out.extend(parse_response(&resp, &batch));
    }
    Ok(out)
}

pub fn model_name() -> &'static str {
    MODEL
}
