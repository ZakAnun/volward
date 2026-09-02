use async_trait::async_trait;
use std::sync::{Arc, Mutex};

use crate::error::AppError;

#[async_trait]
pub trait Mailer: Send + Sync {
    async fn send_otp(&self, email: &str, code: &str) -> Result<(), AppError>;
}

/// Logs OTP for local/dev when Resend is not configured.
pub struct LogMailer;

#[async_trait]
impl Mailer for LogMailer {
    async fn send_otp(&self, email: &str, code: &str) -> Result<(), AppError> {
        tracing::info!(%email, %code, "OTP (dev LogMailer)");
        Ok(())
    }
}

pub struct ResendMailer {
    pub api_key: String,
    pub from: String,
    client: reqwest::Client,
}

impl ResendMailer {
    pub fn new(api_key: String, from: String) -> Self {
        Self {
            api_key,
            from,
            client: reqwest::Client::new(),
        }
    }
}

#[async_trait]
impl Mailer for ResendMailer {
    async fn send_otp(&self, email: &str, code: &str) -> Result<(), AppError> {
        let body = serde_json::json!({
            "from": self.from,
            "to": [email],
            "subject": "Your Volward verification code",
            "text": format!("Your Volward code is {code}. It expires in 5 minutes."),
        });
        let res = self
            .client
            .post("https://api.resend.com/emails")
            .bearer_auth(&self.api_key)
            .json(&body)
            .send()
            .await
            .map_err(|e| AppError::Internal(e.to_string()))?;
        if !res.status().is_success() {
            return Err(AppError::Internal(format!(
                "resend status {}",
                res.status()
            )));
        }
        Ok(())
    }
}

/// Test double that records the last OTP.
#[derive(Default, Clone)]
pub struct TestMailer {
    pub last: Arc<Mutex<Option<(String, String)>>>,
}

#[async_trait]
impl Mailer for TestMailer {
    async fn send_otp(&self, email: &str, code: &str) -> Result<(), AppError> {
        *self.last.lock().unwrap() = Some((email.to_string(), code.to_string()));
        Ok(())
    }
}
