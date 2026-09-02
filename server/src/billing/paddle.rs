use axum::http::HeaderMap;
use hmac::{Hmac, Mac};
use sha2::Sha256;

use crate::billing::provider::{PaidEvent, PaymentProvider};
use crate::error::AppError;

pub const WEBHOOK_MAX_AGE_SECS: i64 = 300;

pub struct PaddleProvider {
    pub api_key: String,
    pub webhook_secret: String,
    pub env: String,
}

impl PaddleProvider {
    pub fn api_base(&self) -> &'static str {
        if self.env == "live" {
            "https://api.paddle.com"
        } else {
            "https://sandbox-api.paddle.com"
        }
    }
}

pub fn verify_paddle_signature(
    secret: &str,
    body: &[u8],
    signature_header: &str,
    now_unix: i64,
) -> bool {
    let mut ts_opt: Option<i64> = None;
    let mut h1s: Vec<&str> = Vec::new();
    for part in signature_header.split(';') {
        let part = part.trim();
        if let Some(value) = part.strip_prefix("ts=") {
            ts_opt = value.parse().ok();
        } else if let Some(value) = part.strip_prefix("h1=") {
            h1s.push(value);
        }
    }
    let Some(ts) = ts_opt else {
        return false;
    };
    if h1s.is_empty() || now_unix.abs_diff(ts) > WEBHOOK_MAX_AGE_SECS as u64 {
        return false;
    }

    let Ok(mut mac) = Hmac::<Sha256>::new_from_slice(secret.as_bytes()) else {
        return false;
    };
    let mut msg = format!("{ts}:").into_bytes();
    msg.extend_from_slice(body);
    mac.update(&msg);
    let expected = hex::encode(mac.finalize().into_bytes());
    h1s.iter().any(|h1| {
        expected.len() == h1.len()
            && expected
                .bytes()
                .zip(h1.bytes())
                .fold(0u8, |acc, (a, b)| acc | (a ^ b))
                == 0
    })
}

fn checkout_url_from_json(value: &serde_json::Value) -> Option<&str> {
    value.pointer("/data/checkout/url").and_then(|v| v.as_str())
}

fn checkout_url_result_from_json(value: &serde_json::Value) -> Result<&str, AppError> {
    checkout_url_from_json(value).ok_or_else(|| {
        tracing::error!("Paddle create_checkout response missing data.checkout.url");
        AppError::BadGateway
    })
}

fn checkout_request_body(product_id: &str, user_id: &str, pack_id: &str) -> serde_json::Value {
    serde_json::json!({
        "items": [{ "price_id": product_id, "quantity": 1 }],
        "custom_data": { "user_id": user_id, "pack_id": pack_id },
        "collection_mode": "automatic"
    })
}

#[async_trait::async_trait]
impl PaymentProvider for PaddleProvider {
    async fn create_checkout(
        &self,
        product_id: &str,
        user_id: &str,
        pack_id: &str,
    ) -> Result<String, AppError> {
        let body = checkout_request_body(product_id, user_id, pack_id);
        let response = reqwest::Client::new()
            .post(format!("{}/transactions", self.api_base()))
            .bearer_auth(&self.api_key)
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|error| {
                tracing::error!(
                    status = ?error.status(),
                    error = %error,
                    "Paddle create_checkout request failed"
                );
                AppError::BadGateway
            })?;
        let status = response.status();
        if !status.is_success() {
            const MAX_ERROR_BODY_CHARS: usize = 4096;
            match response.text().await {
                Ok(body) => {
                    let truncated = body.chars().count() > MAX_ERROR_BODY_CHARS;
                    let body: String = body.chars().take(MAX_ERROR_BODY_CHARS).collect();
                    tracing::error!(
                        %status,
                        response_body = %body,
                        body_truncated = truncated,
                        "Paddle create_checkout returned an error response"
                    );
                }
                Err(error) => {
                    tracing::error!(
                        %status,
                        error = %error,
                        "Paddle create_checkout returned an unreadable error response"
                    );
                }
            }
            return Err(AppError::BadGateway);
        }
        let value: serde_json::Value = response.json().await.map_err(|error| {
            tracing::error!(error = %error, "Paddle create_checkout returned invalid JSON");
            AppError::BadGateway
        })?;
        checkout_url_result_from_json(&value).map(str::to_owned)
    }

    async fn verify_and_parse_webhook(
        &self,
        headers: &HeaderMap,
        body: &[u8],
    ) -> Result<Option<PaidEvent>, AppError> {
        let signature = headers
            .get("Paddle-Signature")
            .and_then(|value| value.to_str().ok())
            .unwrap_or("");
        let now = chrono::Utc::now().timestamp();
        if !verify_paddle_signature(&self.webhook_secret, body, signature, now) {
            return Err(AppError::Unauthorized);
        }

        let payload: serde_json::Value =
            serde_json::from_slice(body).map_err(|e| AppError::BadRequest(e.to_string()))?;
        if payload.get("event_type").and_then(|v| v.as_str()) != Some("transaction.completed") {
            return Ok(None);
        }
        if payload
            .pointer("/data/status")
            .and_then(|v| v.as_str())
            .is_some_and(|s| s != "completed")
        {
            return Ok(None);
        }

        let provider_order_id = payload
            .pointer("/data/id")
            .and_then(|v| v.as_str())
            .filter(|value| !value.is_empty())
            .ok_or_else(|| AppError::BadRequest("missing_order_id".into()))?;
        let user_id = payload
            .pointer("/data/custom_data/user_id")
            .and_then(|v| v.as_str())
            .filter(|value| !value.is_empty())
            .ok_or_else(|| {
                tracing::error!("signed Paddle webhook missing custom_data.user_id");
                AppError::BadRequest("missing_user_id".into())
            })?;
        let pack_id = payload
            .pointer("/data/custom_data/pack_id")
            .and_then(|v| v.as_str())
            .filter(|value| !value.is_empty())
            .ok_or_else(|| {
                tracing::error!("signed Paddle webhook missing custom_data.pack_id");
                AppError::BadRequest("missing_pack_id".into())
            })?;

        Ok(Some(PaidEvent {
            user_id: user_id.to_owned(),
            pack_id: pack_id.to_owned(),
            provider_order_id: provider_order_id.to_owned(),
        }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::billing::provider::PaymentProvider;
    use hmac::{Hmac, Mac};
    use sha2::Sha256;

    type HmacSha256 = Hmac<Sha256>;

    fn sign(secret: &str, ts: i64, body: &[u8]) -> String {
        let mut mac = HmacSha256::new_from_slice(secret.as_bytes()).unwrap();
        let mut msg = format!("{ts}:").into_bytes();
        msg.extend_from_slice(body);
        mac.update(&msg);
        format!("ts={ts};h1={}", hex::encode(mac.finalize().into_bytes()))
    }

    #[test]
    fn accept_valid_signature() {
        let body = br#"{"event_type":"transaction.completed"}"#;
        let ts = 1_700_000_000i64;
        let header = sign("whsec_test", ts, body);
        assert!(verify_paddle_signature("whsec_test", body, &header, ts));
    }

    #[test]
    fn reject_tampered_body() {
        let body = br#"{"event_type":"transaction.completed"}"#;
        let ts = 1_700_000_000i64;
        let header = sign("whsec_test", ts, body);
        assert!(!verify_paddle_signature(
            "whsec_test",
            br#"{"event_type":"transaction.completed","x":1}"#,
            &header,
            ts
        ));
    }

    #[test]
    fn reject_expired_timestamp() {
        let body = b"{}";
        let ts = 1_700_000_000i64;
        let header = sign("whsec_test", ts, body);
        assert!(!verify_paddle_signature(
            "whsec_test",
            body,
            &header,
            ts + WEBHOOK_MAX_AGE_SECS + 1
        ));
    }

    #[test]
    fn reject_extreme_timestamp_without_overflow() {
        let body = b"{}";
        let header = sign("whsec_test", i64::MIN, body);
        assert!(!verify_paddle_signature(
            "whsec_test",
            body,
            &header,
            i64::MAX
        ));
    }

    #[test]
    fn reject_wrong_secret() {
        let body = b"{}";
        let ts = 1_700_000_000i64;
        let header = sign("whsec_test", ts, body);
        assert!(!verify_paddle_signature("other", body, &header, ts));
    }

    #[tokio::test]
    async fn parse_transaction_completed() {
        let p = PaddleProvider {
            api_key: "k".into(),
            webhook_secret: "whsec_test".into(),
            env: "sandbox".into(),
        };
        let now = chrono::Utc::now().timestamp();
        let body = br#"{"event_type":"transaction.completed","data":{"id":"txn_1","status":"completed","custom_data":{"user_id":"u1","pack_id":"starter"}}}"#;
        let header = sign("whsec_test", now, body);
        let mut headers = axum::http::HeaderMap::new();
        headers.insert("Paddle-Signature", header.parse().unwrap());
        let ev = p
            .verify_and_parse_webhook(&headers, body)
            .await
            .unwrap()
            .expect("paid");
        assert_eq!(ev.provider_order_id, "txn_1");
        assert_eq!(ev.user_id, "u1");
        assert_eq!(ev.pack_id, "starter");
    }

    #[tokio::test]
    async fn ignore_non_completed_event() {
        let p = PaddleProvider {
            api_key: "k".into(),
            webhook_secret: "whsec_test".into(),
            env: "sandbox".into(),
        };
        let now = chrono::Utc::now().timestamp();
        let body = br#"{"event_type":"transaction.updated","data":{"id":"txn_2","custom_data":{"user_id":"u1","pack_id":"starter"}}}"#;
        let header = sign("whsec_test", now, body);
        let mut headers = axum::http::HeaderMap::new();
        headers.insert("Paddle-Signature", header.parse().unwrap());
        let ev = p.verify_and_parse_webhook(&headers, body).await.unwrap();
        assert!(ev.is_none());
    }

    #[test]
    fn checkout_url_from_fixture_json() {
        let v: serde_json::Value = serde_json::from_str(
            r#"{"data":{"id":"txn_x","checkout":{"url":"https://pay.example/checkout?_ptxn=txn_x"}}}"#,
        )
        .unwrap();
        assert_eq!(
            checkout_url_from_json(&v),
            Some("https://pay.example/checkout?_ptxn=txn_x")
        );
    }

    #[test]
    fn checkout_url_missing_maps_to_bad_gateway() {
        let v: serde_json::Value = serde_json::from_str(r#"{"data":{"id":"txn_x"}}"#).unwrap();
        assert!(matches!(
            checkout_url_result_from_json(&v),
            Err(AppError::BadGateway)
        ));
    }

    #[test]
    fn checkout_request_body_matches_paddle_contract() {
        let body = checkout_request_body("pri_123", "user_1", "starter");
        assert_eq!(body["collection_mode"], "automatic");
        assert_eq!(body["items"][0]["price_id"], "pri_123");
        assert_eq!(body["items"][0]["quantity"], 1);
        assert_eq!(body["custom_data"]["user_id"], "user_1");
        assert_eq!(body["custom_data"]["pack_id"], "starter");
    }

    #[test]
    fn api_base_selects_paddle_environment() {
        assert_eq!(
            PaddleProvider {
                api_key: "k".into(),
                webhook_secret: "s".into(),
                env: "sandbox".into(),
            }
            .api_base(),
            "https://sandbox-api.paddle.com"
        );
        assert_eq!(
            PaddleProvider {
                api_key: "k".into(),
                webhook_secret: "s".into(),
                env: "live".into(),
            }
            .api_base(),
            "https://api.paddle.com"
        );
    }
}
