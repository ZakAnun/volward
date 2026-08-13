use axum::http::HeaderMap;
use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};

use crate::error::AppError;
use crate::AppState;

const JWT_TTL_SECS: i64 = 30 * 24 * 60 * 60;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Claims {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sub: Option<String>,
    pub did: String,
    pub exp: i64,
}

#[derive(Debug, Clone)]
pub struct AuthUser {
    pub device_id: String,
    pub user_id: Option<String>,
}

impl AuthUser {
    pub fn require_user(&self) -> Result<&str, AppError> {
        self.user_id
            .as_deref()
            .ok_or(AppError::Forbidden("link_account_required"))
    }
}

pub fn issue_token(
    secret: &str,
    device_id: &str,
    user_id: Option<&str>,
) -> Result<String, AppError> {
    let exp = chrono::Utc::now().timestamp() + JWT_TTL_SECS;
    let claims = Claims {
        sub: user_id.map(|s| s.to_string()),
        did: device_id.to_string(),
        exp,
    };
    encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(secret.as_bytes()),
    )
    .map_err(|e| AppError::Internal(e.to_string()))
}

pub fn decode_token(secret: &str, token: &str) -> Result<Claims, AppError> {
    decode::<Claims>(
        token,
        &DecodingKey::from_secret(secret.as_bytes()),
        &Validation::default(),
    )
    .map(|d| d.claims)
    .map_err(|_| AppError::Unauthorized)
}

fn bearer(headers: &HeaderMap) -> Result<&str, AppError> {
    let auth = headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .ok_or(AppError::Unauthorized)?;
    auth.strip_prefix("Bearer ")
        .ok_or(AppError::Unauthorized)
}

pub fn auth_from_headers(state: &AppState, headers: &HeaderMap) -> Result<AuthUser, AppError> {
    let token = bearer(headers)?;
    let claims = decode_token(&state.config.jwt_secret, token)?;
    Ok(AuthUser {
        device_id: claims.did,
        user_id: claims.sub,
    })
}

pub fn require_device(state: &AppState, headers: &HeaderMap) -> Result<AuthUser, AppError> {
    auth_from_headers(state, headers)
}

pub fn require_user(state: &AppState, headers: &HeaderMap) -> Result<AuthUser, AppError> {
    let user = auth_from_headers(state, headers)?;
    user.require_user()?;
    Ok(user)
}
