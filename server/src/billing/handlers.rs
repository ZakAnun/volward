use axum::extract::State;
use axum::http::HeaderMap;
use axum::Json;
use serde::{Deserialize, Serialize};

use crate::auth::middleware::{require_device, require_user};
use crate::error::AppError;
use crate::AppState;

use super::paddle::PaddleProvider;
use super::provider::PaymentProvider;

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

    let row: Option<(String,)> =
        sqlx::query_as("SELECT provider_product_id FROM packs WHERE id = ? AND active = 1")
            .bind(&body.pack_id)
            .fetch_optional(&state.pool)
            .await?;
    let Some((product_id,)) = row else {
        tracing::error!(pack_id = %body.pack_id, "checkout requested unknown pack");
        return Err(AppError::BadRequest("unknown_pack".into()));
    };
    if product_id.starts_with("FILL_ME") {
        if state.config.paddle_env == "live" {
            tracing::error!(
                pack_id = %body.pack_id,
                "live Paddle checkout requested with an unconfigured product id"
            );
            return Err(AppError::Internal("paddle_product_id_unconfigured".into()));
        }
        // Sandbox fallback keeps the purchase UI locally testable.
        return Ok(Json(CheckoutResponse {
            checkout_url: format!(
                "https://example.com/checkout?pack={}&user={}",
                body.pack_id, uid
            ),
        }));
    }
    let api_key = state
        .config
        .paddle_api_key
        .clone()
        .ok_or_else(|| AppError::Internal("paddle_api_key_missing".into()))?;
    let provider = PaddleProvider {
        api_key,
        webhook_secret: state
            .config
            .paddle_webhook_secret
            .clone()
            .unwrap_or_default(),
        env: state.config.paddle_env.clone(),
    };
    let url = provider
        .create_checkout(&product_id, uid, &body.pack_id)
        .await?;
    Ok(Json(CheckoutResponse { checkout_url: url }))
}
