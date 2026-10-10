use crate::error::AppError;

pub fn credits_column(paddle_env: &str) -> Result<&'static str, AppError> {
    match paddle_env {
        "sandbox" => Ok("credits_sandbox"),
        "live" => Ok("credits_live"),
        _ => Err(AppError::Internal("invalid_paddle_env".into())),
    }
}

pub fn pack_price_id_column(paddle_env: &str) -> Result<&'static str, AppError> {
    match paddle_env {
        "sandbox" => Ok("provider_product_id_sandbox"),
        "live" => Ok("provider_product_id_live"),
        _ => Err(AppError::Internal("invalid_paddle_env".into())),
    }
}

pub fn balance_for_env(
    credits_sandbox: i64,
    credits_live: i64,
    paddle_env: &str,
) -> Result<i64, AppError> {
    match paddle_env {
        "sandbox" => Ok(credits_sandbox),
        "live" => Ok(credits_live),
        _ => Err(AppError::Internal("invalid_paddle_env".into())),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn columns_for_sandbox_and_live() {
        assert_eq!(credits_column("sandbox").unwrap(), "credits_sandbox");
        assert_eq!(credits_column("live").unwrap(), "credits_live");
        assert_eq!(
            pack_price_id_column("sandbox").unwrap(),
            "provider_product_id_sandbox"
        );
        assert_eq!(
            pack_price_id_column("live").unwrap(),
            "provider_product_id_live"
        );
    }

    #[test]
    fn balance_for_env_picks_column() {
        assert_eq!(balance_for_env(3, 7, "sandbox").unwrap(), 3);
        assert_eq!(balance_for_env(3, 7, "live").unwrap(), 7);
    }

    #[test]
    fn invalid_env_errors() {
        assert!(credits_column("production").is_err());
    }
}
