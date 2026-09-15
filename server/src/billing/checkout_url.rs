use crate::error::AppError;

fn is_volward_pay_checkout(parsed: &url::Url, host: &str) -> bool {
    if host != "volwardapp.com" && host != "www.volwardapp.com" {
        return false;
    }
    let path = parsed.path();
    let path_ok = path == "/pay" || path.starts_with("/pay/");
    if !path_ok {
        return false;
    }
    parsed.query_pairs().any(|(key, _)| key == "_ptxn")
}

pub fn is_allowed_paddle_checkout_url(url: &str) -> bool {
    let Ok(parsed) = url::Url::parse(url) else {
        return false;
    };
    if parsed.scheme() != "https" {
        return false;
    }
    let Some(host) = parsed.host_str() else {
        return false;
    };
    let host = host.to_ascii_lowercase();
    if is_volward_pay_checkout(&parsed, &host) {
        return true;
    }
    if host == "volwardapp.com" || host == "www.volwardapp.com" {
        return false;
    }
    const EXACT: &[&str] = &[
        "buy.paddle.com",
        "sandbox-buy.paddle.com",
        "checkout.paddle.com",
    ];
    if EXACT.contains(&host.as_str()) {
        return true;
    }
    host.ends_with(".paddle.com")
}

pub fn validate_paddle_checkout_url(url: &str) -> Result<(), AppError> {
    if is_allowed_paddle_checkout_url(url) {
        Ok(())
    } else {
        Err(AppError::CheckoutUrlInvalid)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_sandbox_buy_paddle() {
        assert!(is_allowed_paddle_checkout_url(
            "https://sandbox-buy.paddle.com/checkout?_ptxn=txn_1"
        ));
    }

    #[test]
    fn accepts_buy_paddle() {
        assert!(is_allowed_paddle_checkout_url(
            "https://buy.paddle.com/checkout?_ptxn=txn_1"
        ));
    }

    #[test]
    fn accepts_volwardapp_pay_with_ptxn() {
        assert!(is_allowed_paddle_checkout_url(
            "https://volwardapp.com/pay?_ptxn=txn_01abc"
        ));
    }

    #[test]
    fn accepts_volwardapp_pay_slash_with_ptxn() {
        assert!(is_allowed_paddle_checkout_url(
            "https://volwardapp.com/pay/?_ptxn=txn_01abc"
        ));
    }

    #[test]
    fn rejects_volwardapp_pri_path() {
        assert!(!is_allowed_paddle_checkout_url(
            "https://www.volwardapp.com/pri_01abc"
        ));
    }

    #[test]
    fn rejects_volwardapp_pay_without_ptxn() {
        assert!(!is_allowed_paddle_checkout_url(
            "https://volwardapp.com/pay"
        ));
    }

    #[test]
    fn rejects_pri_only() {
        assert!(!is_allowed_paddle_checkout_url("pri_01abc"));
    }

    #[test]
    fn rejects_http() {
        assert!(!is_allowed_paddle_checkout_url(
            "http://buy.paddle.com/checkout"
        ));
    }

    #[test]
    fn rejects_example_com() {
        assert!(!is_allowed_paddle_checkout_url(
            "https://example.com/checkout?pack=starter"
        ));
    }
}
