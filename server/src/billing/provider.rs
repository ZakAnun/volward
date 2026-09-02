use axum::http::HeaderMap;

use crate::error::AppError;

pub struct PaidEvent {
    pub user_id: String,
    pub pack_id: String,
    pub provider_order_id: String,
}

#[async_trait::async_trait]
pub trait PaymentProvider: Send + Sync {
    async fn create_checkout(
        &self,
        product_id: &str,
        user_id: &str,
        pack_id: &str,
    ) -> Result<String, AppError>;

    /// `Ok(None)` ignores events that do not grant credits.
    async fn verify_and_parse_webhook(
        &self,
        headers: &HeaderMap,
        body: &[u8],
    ) -> Result<Option<PaidEvent>, AppError>;
}
