use axum::body::Bytes;
use axum::extract::State;
use axum::http::{HeaderMap, StatusCode};
use axum::response::IntoResponse;
use hmac::{Hmac, Mac};
use sha2::Sha256;
use uuid::Uuid;

use crate::error::AppError;
use crate::AppState;

type HmacSha256 = Hmac<Sha256>;

pub fn verify_signature(secret: &str, body: &[u8], signature_header: &str) -> bool {
    let sig = signature_header
        .strip_prefix("sha256=")
        .unwrap_or(signature_header);
    let Ok(mut mac) = HmacSha256::new_from_slice(secret.as_bytes()) else {
        return false;
    };
    mac.update(body);
    let expected = hex::encode(mac.finalize().into_bytes());
    // Constant-time-ish compare
    expected.len() == sig.len()
        && expected
            .bytes()
            .zip(sig.bytes())
            .fold(0u8, |acc, (a, b)| acc | (a ^ b))
            == 0
}

pub async fn webhook(
    State(state): State<AppState>,
    headers: HeaderMap,
    body: Bytes,
) -> Result<impl IntoResponse, AppError> {
    let secret = state
        .config
        .ls_webhook_secret
        .as_deref()
        .ok_or(AppError::Internal("ls_webhook_secret_missing".into()))?;
    let sig = headers
        .get("X-Signature")
        .or_else(|| headers.get("x-signature"))
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");
    if !verify_signature(secret, &body, sig) {
        return Err(AppError::Unauthorized);
    }

    let payload: serde_json::Value =
        serde_json::from_slice(&body).map_err(|e| AppError::BadRequest(e.to_string()))?;
    let event = payload
        .pointer("/meta/event_name")
        .or_else(|| payload.get("event_name"))
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let status = payload
        .pointer("/data/attributes/status")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    if event != "order_created" || status != "paid" {
        return Ok(StatusCode::OK);
    }

    let user_id = payload
        .pointer("/meta/custom_data/user_id")
        .and_then(|v| v.as_str())
        .ok_or_else(|| AppError::BadRequest("missing_user_id".into()))?;
    let pack_id = payload
        .pointer("/meta/custom_data/pack_id")
        .and_then(|v| v.as_str())
        .ok_or_else(|| AppError::BadRequest("missing_pack_id".into()))?;
    let order_id = payload
        .pointer("/data/id")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    if order_id.is_empty() {
        return Err(AppError::BadRequest("missing_order_id".into()));
    }

    let existing: Option<(String,)> =
        sqlx::query_as("SELECT id FROM transactions WHERE ls_order_id = ?")
            .bind(&order_id)
            .fetch_optional(&state.pool)
            .await?;
    if existing.is_some() {
        return Ok(StatusCode::OK);
    }

    let credits: (i64,) = sqlx::query_as("SELECT credits FROM packs WHERE id = ? AND active = 1")
        .bind(pack_id)
        .fetch_optional(&state.pool)
        .await?
        .ok_or_else(|| AppError::BadRequest("unknown_pack".into()))?;

    let mut conn = state.pool.acquire().await?;
    sqlx::query("BEGIN IMMEDIATE")
        .execute(&mut *conn)
        .await?;
    if let Err(e) = sqlx::query("UPDATE users SET credits = credits + ? WHERE id = ?")
        .bind(credits.0)
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
        INSERT INTO transactions (id, user_id, device_id, kind, credits_delta, ls_order_id, created_at)
        VALUES (?, ?, NULL, 'purchase', ?, ?, ?)
        "#,
    )
    .bind(&tid)
    .bind(user_id)
    .bind(credits.0)
    .bind(&order_id)
    .bind(now)
    .execute(&mut *conn)
    .await
    {
        let _ = sqlx::query("ROLLBACK").execute(&mut *conn).await;
        // Unique conflict on ls_order_id → idempotent success
        if matches!(e, sqlx::Error::Database(ref d) if d.message().contains("UNIQUE")) {
            return Ok(StatusCode::OK);
        }
        return Err(e.into());
    }
    sqlx::query("COMMIT").execute(&mut *conn).await?;
    Ok(StatusCode::OK)
}
