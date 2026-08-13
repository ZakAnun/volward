use std::env;

#[derive(Debug, Clone)]
pub struct Config {
    pub database_url: String,
    pub jwt_secret: String,
    pub deepseek_api_key: String,
    pub resend_api_key: Option<String>,
    pub resend_from: Option<String>,
    pub ls_api_key: Option<String>,
    pub ls_webhook_secret: Option<String>,
    pub ls_store_id: Option<String>,
    pub bind_addr: String,
}

impl Config {
    pub fn from_env() -> Result<Self, String> {
        Ok(Self {
            database_url: required("DATABASE_URL")?,
            jwt_secret: required("JWT_SECRET")?,
            deepseek_api_key: env::var("DEEPSEEK_API_KEY").unwrap_or_default(),
            resend_api_key: optional("RESEND_API_KEY"),
            resend_from: optional("RESEND_FROM"),
            ls_api_key: optional("LS_API_KEY"),
            ls_webhook_secret: optional("LS_WEBHOOK_SECRET"),
            ls_store_id: optional("LS_STORE_ID"),
            bind_addr: env::var("BIND_ADDR").unwrap_or_else(|_| "0.0.0.0:8080".into()),
        })
    }

    pub fn for_test(database_url: String) -> Self {
        Self {
            database_url,
            jwt_secret: "test-jwt-secret-do-not-use-in-prod".into(),
            deepseek_api_key: "test-deepseek-key".into(),
            resend_api_key: None,
            resend_from: None,
            ls_api_key: Some("test-ls-key".into()),
            ls_webhook_secret: Some("test-webhook-secret".into()),
            ls_store_id: Some("1".into()),
            bind_addr: "127.0.0.1:0".into(),
        }
    }
}

fn required(name: &str) -> Result<String, String> {
    env::var(name).map_err(|_| format!("missing required env var {name}"))
}

fn optional(name: &str) -> Option<String> {
    env::var(name).ok().filter(|s| !s.is_empty())
}
