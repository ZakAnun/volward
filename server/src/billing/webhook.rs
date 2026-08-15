use axum::body::Bytes;
use axum::extract::State;
use axum::http::{HeaderMap, StatusCode};
use axum::response::IntoResponse;
use uuid::Uuid;

use crate::error::AppError;
use crate::AppState;

use super::paddle::PaddleProvider;
use super::provider::PaymentProvider;

pub async fn webhook(
    State(state): State<AppState>,
    headers: HeaderMap,
    body: Bytes,
) -> Result<impl IntoResponse, AppError> {
    let secret = state
        .config
        .paddle_webhook_secret
        .as_deref()
        .ok_or(AppError::Internal("paddle_webhook_secret_missing".into()))?;
    let provider = PaddleProvider {
        api_key: state.config.paddle_api_key.clone().unwrap_or_default(),
        webhook_secret: secret.to_owned(),
        env: state.config.paddle_env.clone(),
    };
    let Some(event) = provider.verify_and_parse_webhook(&headers, &body).await? else {
        return Ok(StatusCode::OK);
    };

    let existing: Option<(String,)> =
        sqlx::query_as("SELECT id FROM transactions WHERE provider_order_id = ?")
            .bind(&event.provider_order_id)
            .fetch_optional(&state.pool)
            .await?;
    if existing.is_some() {
        return Ok(StatusCode::OK);
    }

    let credits: (i64,) = sqlx::query_as("SELECT credits FROM packs WHERE id = ? AND active = 1")
        .bind(&event.pack_id)
        .fetch_optional(&state.pool)
        .await?
        .ok_or_else(|| {
            tracing::error!(
                pack_id = %event.pack_id,
                provider_order_id = %event.provider_order_id,
                "signed Paddle webhook referenced unknown pack"
            );
            AppError::BadRequest("unknown_pack".into())
        })?;

    let mut conn = state.pool.acquire().await?;
    sqlx::query("BEGIN IMMEDIATE").execute(&mut *conn).await?;
    let update = sqlx::query("UPDATE users SET credits = credits + ? WHERE id = ?")
        .bind(credits.0)
        .bind(&event.user_id)
        .execute(&mut *conn)
        .await;
    let update = match update {
        Ok(result) => result,
        Err(e) => {
            let _ = sqlx::query("ROLLBACK").execute(&mut *conn).await;
            return Err(e.into());
        }
    };
    if update.rows_affected() == 0 {
        let _ = sqlx::query("ROLLBACK").execute(&mut *conn).await;
        tracing::error!(
            user_id = %event.user_id,
            provider_order_id = %event.provider_order_id,
            "signed Paddle webhook referenced unknown user"
        );
        return Err(AppError::BadRequest("unknown_user".into()));
    }
    let tid = Uuid::new_v4().to_string();
    let now = chrono::Utc::now().timestamp_millis();
    if let Err(e) = sqlx::query(
        r#"
        INSERT INTO transactions (id, user_id, device_id, kind, credits_delta, provider_order_id, created_at)
        VALUES (?, ?, NULL, 'purchase', ?, ?, ?)
        "#,
    )
    .bind(&tid)
    .bind(&event.user_id)
    .bind(credits.0)
    .bind(&event.provider_order_id)
    .bind(now)
    .execute(&mut *conn)
    .await
    {
        let _ = sqlx::query("ROLLBACK").execute(&mut *conn).await;
        // Unique conflict on provider_order_id means this delivery is already credited.
        if matches!(e, sqlx::Error::Database(ref d) if d.message().contains("UNIQUE")) {
            return Ok(StatusCode::OK);
        }
        return Err(e.into());
    }
    sqlx::query("COMMIT").execute(&mut *conn).await?;
    Ok(StatusCode::OK)
}
