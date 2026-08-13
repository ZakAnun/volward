use axum::extract::State;
use axum::Json;
use chrono::Utc;
use serde::{Deserialize, Serialize};

use crate::auth::middleware::issue_token;
use crate::error::AppError;
use crate::AppState;

#[derive(Deserialize)]
pub struct RegisterBody {
    pub device_uuid: String,
    pub platform: Option<String>,
    pub app_version: Option<String>,
}

#[derive(Serialize)]
pub struct RegisterResponse {
    pub token: String,
    pub linked: bool,
}

pub async fn register(
    State(state): State<AppState>,
    Json(body): Json<RegisterBody>,
) -> Result<Json<RegisterResponse>, AppError> {
    let id = body.device_uuid.trim();
    if id.is_empty() {
        return Err(AppError::BadRequest("device_uuid_required".into()));
    }
    let now = Utc::now().timestamp_millis();
    sqlx::query(
        r#"
        INSERT INTO devices (id, user_id, platform, app_version, created_at)
        VALUES (?, NULL, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            platform = COALESCE(excluded.platform, devices.platform),
            app_version = COALESCE(excluded.app_version, devices.app_version)
        "#,
    )
    .bind(id)
    .bind(body.platform.as_deref())
    .bind(body.app_version.as_deref())
    .bind(now)
    .execute(&state.pool)
    .await?;

    let user_id: Option<(Option<String>,)> =
        sqlx::query_as("SELECT user_id FROM devices WHERE id = ?")
            .bind(id)
            .fetch_optional(&state.pool)
            .await?;
    let linked_uid = user_id.and_then(|r| r.0);
    let linked = linked_uid.is_some();
    let token = issue_token(
        &state.config.jwt_secret,
        id,
        linked_uid.as_deref(),
    )?;
    Ok(Json(RegisterResponse { token, linked }))
}
