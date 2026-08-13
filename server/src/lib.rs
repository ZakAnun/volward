pub mod auth;
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

use crate::auth::email::{LogMailer, Mailer};
use crate::config::Config;

#[derive(Clone)]
pub struct AppState {
    pub pool: SqlitePool,
    pub config: Arc<Config>,
    pub mailer: Arc<dyn Mailer>,
}

impl AppState {
    pub fn new(pool: SqlitePool, config: Config, mailer: Arc<dyn Mailer>) -> Self {
        Self {
            pool,
            config: Arc::new(config),
            mailer,
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

pub fn default_mailer(config: &Config) -> Arc<dyn Mailer> {
    match (
        config.resend_api_key.clone(),
        config.resend_from.clone(),
    ) {
        (Some(key), Some(from)) => Arc::new(auth::email::ResendMailer::new(key, from)),
        _ => Arc::new(LogMailer),
    }
}

#[cfg(test)]
mod api_tests;
