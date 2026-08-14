use axum::extract::State;
use axum::http::HeaderMap;
use axum::Json;
use serde::{Deserialize, Serialize};

use crate::auth::middleware::{require_device, require_user};
use crate::error::AppError;
use crate::AppState;

use super::lemon_squeezy::create_checkout;

#[derive(Serialize)]
pub struct PackDto {
    pub id: String,
    pub credits: i64,
    pub price_cny: i64,
    pub label_zh: String,
    pub label_en: String,
}

pub async fn packs(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<Vec<PackDto>>, AppError> {
    let _ = require_device(&state, &headers)?;
    let rows: Vec<(String, i64, i64, String, String)> = sqlx::query_as(
        "SELECT id, credits, price_cny, label_zh, label_en FROM packs WHERE active = 1",
    )
    .fetch_all(&state.pool)
    .await?;
    Ok(Json(
        rows.into_iter()
            .map(|(id, credits, price_cny, label_zh, label_en)| PackDto {
                id,
                credits,
                price_cny,
                label_zh,
                label_en,
            })
            .collect(),
    ))
}

#[derive(Deserialize)]
pub struct CheckoutBody {
    pub pack_id: String,
}

#[derive(Serialize)]
pub struct CheckoutResponse {
    pub checkout_url: String,
}

pub async fn checkout(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<CheckoutBody>,
) -> Result<Json<CheckoutResponse>, AppError> {
    let auth = require_user(&state, &headers)?;
    let uid = auth.require_user()?;
    let api_key = state
        .config
        .ls_api_key
        .as_deref()
        .ok_or_else(|| AppError::Internal("ls_api_key_missing".into()))?;
    let store_id = state
        .config
        .ls_store_id
        .as_deref()
        .ok_or_else(|| AppError::Internal("ls_store_id_missing".into()))?;

    let row: Option<(String,)> =
        sqlx::query_as("SELECT ls_variant_id FROM packs WHERE id = ? AND active = 1")
            .bind(&body.pack_id)
            .fetch_optional(&state.pool)
            .await?;
    let Some((variant_id,)) = row else {
        return Err(AppError::BadRequest("unknown_pack".into()));
    };
    if variant_id.starts_with("FILL_ME") {
        // Dev fallback: return a placeholder URL so UI can be exercised.
        return Ok(Json(CheckoutResponse {
            checkout_url: format!(
                "https://example.com/checkout?pack={}&user={}",
                body.pack_id, uid
            ),
        }));
    }
    let url = create_checkout(api_key, store_id, &variant_id, uid, &body.pack_id).await?;
    Ok(Json(CheckoutResponse { checkout_url: url }))
}
