pub mod ai;
pub mod auth;
pub mod billing;
pub mod config;
pub mod db;
pub mod device;
pub mod error;

use std::sync::Arc;

use axum::routing::{get, post};
use axum::{Json, Router};
use serde::Serialize;
use sqlx::SqlitePool;
use tower_http::trace::TraceLayer;

use crate::ai::proxy::{HttpUpstream, UpstreamClient};
use crate::auth::email::{LogMailer, Mailer};
use crate::config::Config;

#[derive(Clone)]
pub struct AppState {
    pub pool: SqlitePool,
    pub config: Arc<Config>,
    pub mailer: Arc<dyn Mailer>,
    pub upstream: Arc<dyn UpstreamClient>,
}

impl AppState {
    pub fn new(
        pool: SqlitePool,
        config: Config,
        mailer: Arc<dyn Mailer>,
        upstream: Arc<dyn UpstreamClient>,
    ) -> Self {
        Self {
            pool,
            config: Arc::new(config),
            mailer,
            upstream,
        }
    }
}

pub fn app(state: AppState) -> Router {
    Router::new()
        .route("/health", get(health))
        .route("/v1/device/register", post(device::handlers::register))
        .route("/v1/auth/request-otp", post(auth::handlers::request_otp))
        .route("/v1/auth/verify-otp", post(auth::handlers::verify_otp))
        .route("/v1/auth/me", get(auth::handlers::me))
        .route("/v1/ai/quota", get(ai::handlers::quota))
        .route("/v1/ai/analyze", post(ai::handlers::analyze))
        .route("/v1/billing/packs", get(billing::handlers::packs))
        .route("/v1/billing/checkout", post(billing::handlers::checkout))
        .route("/v1/billing/webhook", post(billing::webhook::webhook))
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}

#[derive(Serialize)]
struct HealthResponse {
    ok: bool,
}

async fn health() -> Json<HealthResponse> {
    Json(HealthResponse { ok: true })
}

pub fn default_mailer(config: &Config) -> Result<Arc<dyn Mailer>, String> {
    match (
        config.resend_api_key.clone(),
        config.resend_from.clone(),
    ) {
        (Some(key), Some(from)) => Ok(Arc::new(auth::email::ResendMailer::new(key, from))),
        _ if config.allow_log_mailer => Ok(Arc::new(LogMailer)),
        _ => Err(
            "RESEND_API_KEY and RESEND_FROM are required \
             (set ALLOW_LOG_MAILER=1 only for local/dev)"
                .into(),
        ),
    }
}

pub fn default_upstream(config: &Config) -> Arc<dyn UpstreamClient> {
    Arc::new(HttpUpstream::new(config.deepseek_api_key.clone()))
}

#[cfg(test)]
mod api_tests;
