use axum::extract::State;
use axum::http::HeaderMap;
use axum::Json;
use chrono::Utc;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::middleware::{issue_token, require_device, require_user};
use super::otp;
use crate::error::AppError;
use crate::AppState;

#[derive(Deserialize)]
pub struct RequestOtpBody {
    pub email: String,
}

#[derive(Serialize)]
pub struct RequestOtpResponse {
    pub sent: bool,
    pub expires_in_seconds: u64,
}

pub async fn request_otp(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<RequestOtpBody>,
) -> Result<Json<RequestOtpResponse>, AppError> {
    let _auth = require_device(&state, &headers)?;
    let email = body.email.trim().to_lowercase();
    if !email.contains('@') || email.len() < 3 {
        return Err(AppError::BadRequest("invalid_email".into()));
    }
    let code = otp::create_and_store(&state.pool, &email).await?;
    state.mailer.send_otp(&email, &code).await?;
    Ok(Json(RequestOtpResponse {
        sent: true,
        expires_in_seconds: 300,
    }))
}

#[derive(Deserialize)]
pub struct VerifyOtpBody {
    pub email: String,
    pub code: String,
    pub device_uuid: String,
}

#[derive(Serialize)]
pub struct VerifyOtpResponse {
    pub token: String,
    pub user_id: String,
    pub email: String,
    pub credits: i64,
}

pub async fn verify_otp(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<VerifyOtpBody>,
) -> Result<Json<VerifyOtpResponse>, AppError> {
    let auth = require_device(&state, &headers)?;
    let email = body.email.trim().to_lowercase();
    if auth.device_id != body.device_uuid {
        return Err(AppError::UnauthorizedMsg("device_mismatch"));
    }
    otp::verify_and_consume(&state.pool, &email, body.code.trim()).await?;

    let now = Utc::now().timestamp_millis();
    let user_id = Uuid::new_v4().to_string();
    sqlx::query(
        r#"
        INSERT INTO users (id, email, credits, created_at, last_seen_at)
        VALUES (?, ?, 0, ?, ?)
        ON CONFLICT(email) DO UPDATE SET last_seen_at = excluded.last_seen_at
        "#,
    )
    .bind(&user_id)
    .bind(&email)
    .bind(now)
    .bind(now)
    .execute(&state.pool)
    .await?;

    let (uid, credits): (String, i64) =
        sqlx::query_as("SELECT id, credits FROM users WHERE email = ?")
            .bind(&email)
            .fetch_one(&state.pool)
            .await?;

    sqlx::query("UPDATE devices SET user_id = ? WHERE id = ?")
        .bind(&uid)
        .bind(&auth.device_id)
        .execute(&state.pool)
        .await?;

    let token = issue_token(&state.config.jwt_secret, &auth.device_id, Some(&uid))?;
    Ok(Json(VerifyOtpResponse {
        token,
        user_id: uid,
        email,
        credits,
    }))
}

#[derive(Serialize)]
pub struct MeResponse {
    pub user_id: String,
    pub email: String,
    pub credits: i64,
}

pub async fn me(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<MeResponse>, AppError> {
    let auth = require_user(&state, &headers)?;
    let uid = auth.require_user()?;
    let row: Option<(String, i64)> =
        sqlx::query_as("SELECT email, credits FROM users WHERE id = ?")
            .bind(uid)
            .fetch_optional(&state.pool)
            .await?;
    let Some((email, credits)) = row else {
        return Err(AppError::Unauthorized);
    };
    Ok(Json(MeResponse {
        user_id: uid.to_string(),
        email,
        credits,
    }))
}
