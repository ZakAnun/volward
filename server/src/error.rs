use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde_json::json;

#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("unauthorized")]
    Unauthorized,
    #[error("{0}")]
    UnauthorizedMsg(&'static str),
    #[error("{0}")]
    Forbidden(&'static str),
    #[error("insufficient_credits")]
    PaymentRequired,
    #[error("too many requests")]
    TooManyRequests,
    #[error("{0}")]
    BadRequest(String),
    #[error("bad gateway")]
    BadGateway,
    #[error("not found")]
    NotFound,
    #[error("internal error: {0}")]
    Internal(String),
    #[error(transparent)]
    Sqlx(#[from] sqlx::Error),
}

impl AppError {
    pub fn code(&self) -> &'static str {
        match self {
            AppError::Unauthorized | AppError::UnauthorizedMsg(_) => "unauthorized",
            AppError::Forbidden(code) => code,
            AppError::PaymentRequired => "insufficient_credits",
            AppError::TooManyRequests => "rate_limited",
            AppError::BadRequest(_) => "bad_request",
            AppError::BadGateway => "upstream_error",
            AppError::NotFound => "not_found",
            AppError::Internal(_) | AppError::Sqlx(_) => "internal_error",
        }
    }

    pub fn status(&self) -> StatusCode {
        match self {
            AppError::Unauthorized | AppError::UnauthorizedMsg(_) => StatusCode::UNAUTHORIZED,
            AppError::Forbidden(_) => StatusCode::FORBIDDEN,
            AppError::PaymentRequired => StatusCode::PAYMENT_REQUIRED,
            AppError::TooManyRequests => StatusCode::TOO_MANY_REQUESTS,
            AppError::BadRequest(_) => StatusCode::BAD_REQUEST,
            AppError::BadGateway => StatusCode::BAD_GATEWAY,
            AppError::NotFound => StatusCode::NOT_FOUND,
            AppError::Internal(_) | AppError::Sqlx(_) => StatusCode::INTERNAL_SERVER_ERROR,
        }
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        if matches!(self, AppError::Internal(_) | AppError::Sqlx(_)) {
            tracing::error!(error = %self, "internal error");
        }
        let body = json!({
            "error": self.code(),
            "message": self.to_string(),
        });
        (self.status(), Json(body)).into_response()
    }
}
