use crate::error::AppError;

/// Creates a Lemon Squeezy checkout URL for a pack variant.
pub async fn create_checkout(
    api_key: &str,
    store_id: &str,
    variant_id: &str,
    user_id: &str,
    pack_id: &str,
) -> Result<String, AppError> {
    let client = reqwest::Client::new();
    let body = serde_json::json!({
        "data": {
            "type": "checkouts",
            "attributes": {
                "checkout_data": {
                    "custom": {
                        "user_id": user_id,
                        "pack_id": pack_id
                    }
                }
            },
            "relationships": {
                "store": { "data": { "type": "stores", "id": store_id } },
                "variant": { "data": { "type": "variants", "id": variant_id } }
            }
        }
    });
    let res = client
        .post("https://api.lemonsqueezy.com/v1/checkouts")
        .bearer_auth(api_key)
        .header("Accept", "application/vnd.api+json")
        .header("Content-Type", "application/vnd.api+json")
        .json(&body)
        .send()
        .await
        .map_err(|e| AppError::Internal(e.to_string()))?;
    if !res.status().is_success() {
        return Err(AppError::Internal(format!(
            "ls_checkout_status_{}",
            res.status()
        )));
    }
    let json: serde_json::Value = res
        .json()
        .await
        .map_err(|e| AppError::Internal(e.to_string()))?;
    json
        .pointer("/data/attributes/url")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| AppError::Internal("ls_checkout_missing_url".into()))
}
