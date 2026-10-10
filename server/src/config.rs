use std::env;

#[derive(Debug, Clone)]
pub struct Config {
    pub database_url: String,
    pub jwt_secret: String,
    pub deepseek_api_key: String,
    pub resend_api_key: Option<String>,
    pub resend_from: Option<String>,
    /// When true, missing Resend credentials fall back to LogMailer (local/dev only).
    pub allow_log_mailer: bool,
    pub paddle_api_key: Option<String>,
    pub paddle_webhook_secret: Option<String>,
    /// `"sandbox"` or `"live"` — selects Paddle API base URL.
    pub paddle_env: String,
    pub bind_addr: String,
}

impl Config {
    pub fn from_env() -> Result<Self, String> {
        let paddle_api_key = optional("PADDLE_API_KEY");
        let paddle_env = validate_paddle_env(
            &env::var("PADDLE_ENV").unwrap_or_else(|_| "sandbox".into()),
        )?;
        if let Some(ref key) = paddle_api_key {
            validate_paddle_key_env(key, &paddle_env)?;
        }
        Ok(Self {
            database_url: required("DATABASE_URL")?,
            jwt_secret: required("JWT_SECRET")?,
            deepseek_api_key: env::var("DEEPSEEK_API_KEY").unwrap_or_default(),
            resend_api_key: optional("RESEND_API_KEY"),
            resend_from: optional("RESEND_FROM"),
            allow_log_mailer: env::var("ALLOW_LOG_MAILER")
                .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
                .unwrap_or(false),
            paddle_api_key,
            paddle_webhook_secret: optional("PADDLE_WEBHOOK_SECRET"),
            paddle_env,
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
            allow_log_mailer: true,
            paddle_api_key: Some("test-paddle-key".into()),
            paddle_webhook_secret: Some("test-webhook-secret".into()),
            paddle_env: "sandbox".into(),
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

fn validate_paddle_env(value: &str) -> Result<String, String> {
    match value {
        "sandbox" | "live" => Ok(value.to_owned()),
        _ => Err(format!(
            "invalid PADDLE_ENV {value:?}; expected \"sandbox\" or \"live\""
        )),
    }
}

fn validate_paddle_key_env(api_key: &str, paddle_env: &str) -> Result<(), String> {
    let key = api_key.to_ascii_lowercase();
    if !key.starts_with("pdl_") {
        return Ok(());
    }
    match paddle_env {
        "sandbox" if !key.contains("sdbx") => Err(
            "PADDLE_API_KEY must be a sandbox key (contains \"sdbx\") when PADDLE_ENV is sandbox"
                .into(),
        ),
        "live" if !key.contains("live") => Err(
            "PADDLE_API_KEY must be a live key (contains \"live\") when PADDLE_ENV is live".into(),
        ),
        _ => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::{validate_paddle_env, validate_paddle_key_env};

    #[test]
    fn paddle_env_accepts_sandbox_and_live() {
        assert_eq!(validate_paddle_env("sandbox").unwrap(), "sandbox");
        assert_eq!(validate_paddle_env("live").unwrap(), "live");
    }

    #[test]
    fn paddle_env_rejects_unknown_values() {
        assert!(validate_paddle_env("Live").is_err());
        assert!(validate_paddle_env("production").is_err());
        assert!(validate_paddle_env("").is_err());
    }

    #[test]
    fn paddle_api_key_prefix_matches_env() {
        assert!(validate_paddle_key_env("pdl_sdbx_apikey_x", "sandbox").is_ok());
        assert!(validate_paddle_key_env("pdl_live_apikey_x", "live").is_ok());
        assert!(validate_paddle_key_env("pdl_live_apikey_x", "sandbox").is_err());
        assert!(validate_paddle_key_env("pdl_sdbx_apikey_x", "live").is_err());
        assert!(validate_paddle_key_env("test-paddle-key", "live").is_ok());
        assert!(validate_paddle_key_env("pdl_unknown_apikey_x", "sandbox").is_err());
    }
}
