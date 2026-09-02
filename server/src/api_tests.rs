use std::sync::Arc;
use std::sync::Mutex;
use std::time::Duration;

use async_trait::async_trait;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use hmac::{Hmac, Mac};
use http_body_util::BodyExt;
use serde_json::json;
use sha2::Sha256;
use tokio::sync::oneshot;
use tower::ServiceExt;

use crate::ai::proxy::UpstreamClient;
use crate::auth::email::TestMailer;
use crate::error::AppError;
use crate::{app, db, AppState};

type HmacSha256 = Hmac<Sha256>;

struct TestCtx {
    app: axum::Router,
    mailer: TestMailer,
    pool: sqlx::SqlitePool,
    _dir: tempfile::TempDir,
}

struct MockUpstream {
    mode: MockMode,
}

enum MockMode {
    OkKeep,
    Fail,
    Park(Mutex<Option<oneshot::Receiver<()>>>),
}

#[async_trait]
impl UpstreamClient for MockUpstream {
    async fn complete(&self, _request_body: String) -> Result<String, AppError> {
        match &self.mode {
            MockMode::OkKeep => Ok(r#"{
              "choices":[{
                "message":{"content":"[{\"path\":\"/a\",\"verdict\":\"keep\",\"confidence\":\"high\",\"reason\":\"ok\"}]"}
              }]
            }"#.into()),
            MockMode::Fail => Err(AppError::BadGateway),
            MockMode::Park(rx_slot) => {
                let rx = rx_slot.lock().unwrap().take();
                if let Some(rx) = rx {
                    let _ = rx.await;
                }
                Ok(r#"{
                  "choices":[{
                    "message":{"content":"[{\"path\":\"/a\",\"verdict\":\"keep\",\"confidence\":\"high\",\"reason\":\"ok\"}]"}
                  }]
                }"#.into())
            }
        }
    }
}

async fn test_ctx_with_config(
    upstream: Arc<dyn UpstreamClient>,
    configure: impl FnOnce(&mut crate::config::Config),
) -> TestCtx {
    let dir = tempfile::tempdir().expect("tempdir");
    let db_path = dir.path().join("platform.db");
    let url = format!("sqlite:{}?mode=rwc", db_path.display());

    let mut config = crate::config::Config::for_test(url.clone());
    configure(&mut config);
    let pool = db::init_pool(&url).await.expect("init pool");
    let mailer = TestMailer::default();
    let app = app(AppState::new(
        pool.clone(),
        config,
        Arc::new(mailer.clone()),
        upstream,
    ));
    TestCtx {
        app,
        mailer,
        pool,
        _dir: dir,
    }
}

async fn test_ctx_with_upstream(upstream: Arc<dyn UpstreamClient>) -> TestCtx {
    test_ctx_with_config(upstream, |_| {}).await
}

async fn test_ctx() -> TestCtx {
    test_ctx_with_upstream(Arc::new(MockUpstream {
        mode: MockMode::OkKeep,
    }))
    .await
}

async fn body_json(res: axum::response::Response) -> serde_json::Value {
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    serde_json::from_slice(&bytes).unwrap_or(json!({}))
}

async fn post_json(app: &axum::Router, path: &str, body: &str) -> (StatusCode, serde_json::Value) {
    let res = app
        .clone()
        .oneshot(
            Request::post(path)
                .header("content-type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = res.status();
    (status, body_json(res).await)
}

async fn post_auth(
    app: &axum::Router,
    path: &str,
    token: &str,
    body: &str,
) -> (StatusCode, serde_json::Value) {
    let res = app
        .clone()
        .oneshot(
            Request::post(path)
                .header("content-type", "application/json")
                .header("authorization", format!("Bearer {token}"))
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = res.status();
    (status, body_json(res).await)
}

async fn get_auth(app: &axum::Router, path: &str, token: &str) -> (StatusCode, serde_json::Value) {
    let res = app
        .clone()
        .oneshot(
            Request::get(path)
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = res.status();
    (status, body_json(res).await)
}

async fn register_and_link(ctx: &TestCtx, device: &str, email: &str, credits: i64) -> String {
    let (_, reg) = post_json(
        &ctx.app,
        "/v1/device/register",
        &json!({"device_uuid": device, "platform":"macos","app_version":"0.0.3"}).to_string(),
    )
    .await;
    let device_token = reg["token"].as_str().unwrap().to_string();
    let _ = post_auth(
        &ctx.app,
        "/v1/auth/request-otp",
        &device_token,
        &json!({"email": email}).to_string(),
    )
    .await;
    let code = ctx.mailer.last.lock().unwrap().clone().unwrap().1;
    let (_, verified) = post_auth(
        &ctx.app,
        "/v1/auth/verify-otp",
        &device_token,
        &json!({"email": email, "code": code, "device_uuid": device}).to_string(),
    )
    .await;
    let uid = verified["user_id"].as_str().unwrap().to_string();
    if credits != 0 {
        sqlx::query("UPDATE users SET credits = ? WHERE id = ?")
            .bind(credits)
            .bind(&uid)
            .execute(&ctx.pool)
            .await
            .unwrap();
    }
    verified["token"].as_str().unwrap().to_string()
}

const ONE_CANDIDATE: &str = r#"{"candidates":[{"path":"/a","size_bytes":1,"is_dir":false}]}"#;

#[tokio::test]
async fn health_ok() {
    let ctx = test_ctx().await;
    let res = ctx
        .app
        .oneshot(Request::get("/health").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
}

#[tokio::test]
async fn device_register_idempotent() {
    let ctx = test_ctx().await;
    let body = r#"{"device_uuid":"d1","platform":"macos","app_version":"0.0.3"}"#;
    let (s1, t1) = post_json(&ctx.app, "/v1/device/register", body).await;
    let (s2, t2) = post_json(&ctx.app, "/v1/device/register", body).await;
    assert_eq!(s1, StatusCode::OK);
    assert_eq!(s2, StatusCode::OK);
    assert!(t1["token"].is_string());
    assert_eq!(t1["linked"], false);
    assert!(t2["token"].is_string());
}

#[tokio::test]
async fn auth_otp_verify_binds_device_credits_zero() {
    let ctx = test_ctx().await;
    let token = register_and_link(&ctx, "dev-a", "alice@example.com", 0).await;
    let (s, me) = get_auth(&ctx.app, "/v1/auth/me", &token).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(me["credits"], 0);
}

#[tokio::test]
async fn analyze_402_when_no_credits() {
    let ctx = test_ctx().await;
    let token = register_and_link(&ctx, "d-402", "u402@example.com", 0).await;
    let (status, _) = post_auth(&ctx.app, "/v1/ai/analyze", &token, ONE_CANDIDATE).await;
    assert_eq!(status, StatusCode::PAYMENT_REQUIRED);
}

#[tokio::test]
async fn ai_analyze_happy_path() {
    let ctx = test_ctx().await;
    let token = register_and_link(&ctx, "d-ok", "uok@example.com", 5).await;
    let (status, body) = post_auth(&ctx.app, "/v1/ai/analyze", &token, ONE_CANDIDATE).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["credits_used"], 1);
    assert_eq!(body["credits_remaining"], 4);
    assert!(!body["entries"].as_array().unwrap().is_empty());
}

#[tokio::test]
async fn analyze_refunds_credit_when_upstream_fails() {
    let ctx = test_ctx_with_upstream(Arc::new(MockUpstream {
        mode: MockMode::Fail,
    }))
    .await;
    let token = register_and_link(&ctx, "d-fail", "ufail@example.com", 5).await;
    let (status, _) = post_auth(&ctx.app, "/v1/ai/analyze", &token, ONE_CANDIDATE).await;
    assert_eq!(status, StatusCode::BAD_GATEWAY);
    let credits: (i64,) = sqlx::query_as("SELECT credits FROM users WHERE email = ?")
        .bind("ufail@example.com")
        .fetch_one(&ctx.pool)
        .await
        .unwrap();
    assert_eq!(credits.0, 5);
    let kinds: Vec<(String,)> = sqlx::query_as(
        "SELECT kind FROM transactions WHERE user_id = (SELECT id FROM users WHERE email = ?) ORDER BY kind",
    )
    .bind("ufail@example.com")
    .fetch_all(&ctx.pool)
    .await
    .unwrap();
    let kinds: Vec<&str> = kinds.iter().map(|k| k.0.as_str()).collect();
    // Same-ms timestamps make created_at order non-deterministic; assert the set.
    assert_eq!(kinds, vec!["refund", "usage"]);
}

#[tokio::test]
async fn device_register_succeeds_while_analyze_awaits_upstream() {
    let (tx, rx) = oneshot::channel::<()>();
    let ctx = test_ctx_with_upstream(Arc::new(MockUpstream {
        mode: MockMode::Park(Mutex::new(Some(rx))),
    }))
    .await;
    let token = register_and_link(&ctx, "d-park", "upark@example.com", 5).await;
    let app = ctx.app.clone();
    let token_owned = token.clone();
    let analyze = tokio::spawn(async move {
        post_auth(&app, "/v1/ai/analyze", &token_owned, ONE_CANDIDATE).await
    });
    // Give analyze time to debit and park on upstream.
    tokio::time::sleep(Duration::from_millis(50)).await;
    let reg = tokio::time::timeout(
        Duration::from_secs(2),
        post_json(
            &ctx.app,
            "/v1/device/register",
            r#"{"device_uuid":"d9","platform":"macos","app_version":"0.0.3"}"#,
        ),
    )
    .await
    .expect("write blocked by analyze transaction");
    assert!(reg.1["token"].is_string());
    let _ = tx.send(());
    let (status, _) = analyze.await.unwrap();
    assert_eq!(status, StatusCode::OK);
}

fn sign_paddle(secret: &str, body: &[u8]) -> String {
    let ts = chrono::Utc::now().timestamp();
    let mut mac = HmacSha256::new_from_slice(secret.as_bytes()).unwrap();
    let mut msg = format!("{ts}:").into_bytes();
    msg.extend_from_slice(body);
    mac.update(&msg);
    format!("ts={ts};h1={}", hex::encode(mac.finalize().into_bytes()))
}

async fn post_signed(app: &axum::Router, path: &str, body: &str, signature: &str) -> StatusCode {
    let res = app
        .clone()
        .oneshot(
            Request::post(path)
                .header("content-type", "application/json")
                .header("Paddle-Signature", signature)
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    res.status()
}

#[tokio::test]
async fn billing_webhook_idempotent_purchase() {
    let ctx = test_ctx().await;
    let _token = register_and_link(&ctx, "d-bill", "bill@example.com", 0).await;
    let uid: (String,) = sqlx::query_as("SELECT id FROM users WHERE email = ?")
        .bind("bill@example.com")
        .fetch_one(&ctx.pool)
        .await
        .unwrap();
    let body = json!({
        "event_type": "transaction.completed",
        "data": {
            "id": "txn_ord_1",
            "status": "completed",
            "custom_data": { "user_id": uid.0, "pack_id": "starter" }
        }
    })
    .to_string();
    let sig = sign_paddle("test-webhook-secret", body.as_bytes());
    let s1 = post_signed(&ctx.app, "/v1/billing/webhook", &body, &sig).await;
    let s2 = post_signed(&ctx.app, "/v1/billing/webhook", &body, &sig).await;
    assert_eq!(s1, StatusCode::OK);
    assert_eq!(s2, StatusCode::OK);
    let credits: (i64,) = sqlx::query_as("SELECT credits FROM users WHERE email = ?")
        .bind("bill@example.com")
        .fetch_one(&ctx.pool)
        .await
        .unwrap();
    assert_eq!(credits.0, 50);
    let kinds: Vec<(String,)> =
        sqlx::query_as("SELECT kind FROM transactions WHERE user_id = ? ORDER BY created_at")
            .bind(&uid.0)
            .fetch_all(&ctx.pool)
            .await
            .unwrap();
    assert_eq!(kinds.len(), 1);
    assert_eq!(kinds[0].0, "purchase");
}

#[tokio::test]
async fn billing_webhook_rejects_forged_signature() {
    let ctx = test_ctx().await;
    let _token = register_and_link(&ctx, "d-forge", "forge@example.com", 0).await;
    let uid: (String,) = sqlx::query_as("SELECT id FROM users WHERE email = ?")
        .bind("forge@example.com")
        .fetch_one(&ctx.pool)
        .await
        .unwrap();
    let body = json!({
        "event_type": "transaction.completed",
        "data": {
            "id": "txn_ord_forge",
            "status": "completed",
            "custom_data": { "user_id": uid.0, "pack_id": "starter" }
        }
    })
    .to_string();
    let ts = chrono::Utc::now().timestamp();
    let status = post_signed(
        &ctx.app,
        "/v1/billing/webhook",
        &body,
        &format!("ts={ts};h1=deadbeef"),
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    let credits: (i64,) = sqlx::query_as("SELECT credits FROM users WHERE email = ?")
        .bind("forge@example.com")
        .fetch_one(&ctx.pool)
        .await
        .unwrap();
    assert_eq!(credits.0, 0);
}

#[tokio::test]
async fn billing_webhook_rejects_unknown_user() {
    let ctx = test_ctx().await;
    let body = json!({
        "event_type": "transaction.completed",
        "data": {
            "id": "txn_ord_unknown_user",
            "status": "completed",
            "custom_data": { "user_id": "missing-user", "pack_id": "starter" }
        }
    })
    .to_string();
    let sig = sign_paddle("test-webhook-secret", body.as_bytes());
    let status = post_signed(&ctx.app, "/v1/billing/webhook", &body, &sig).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);

    let purchases: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM transactions WHERE provider_order_id = 'txn_ord_unknown_user'",
    )
    .fetch_one(&ctx.pool)
    .await
    .unwrap();
    assert_eq!(purchases.0, 0);
}

#[tokio::test]
async fn quota_returns_credits_after_link() {
    let ctx = test_ctx().await;
    // Direct balance bump without a grant ledger row → total stays 0
    let token = register_and_link(&ctx, "d-quota", "quota@example.com", 7).await;
    let (status, body) = get_auth(&ctx.app, "/v1/ai/quota", &token).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["credits_remaining"], 7);
    assert_eq!(body["credits_total"], 0);
}

#[tokio::test]
async fn quota_total_sums_purchase_and_topup() {
    let ctx = test_ctx().await;
    let token = register_and_link(&ctx, "d-total", "total@example.com", 0).await;
    let uid: (String,) = sqlx::query_as("SELECT id FROM users WHERE email = ?")
        .bind("total@example.com")
        .fetch_one(&ctx.pool)
        .await
        .unwrap();
    let now = chrono::Utc::now().timestamp_millis();
    // purchase +50, topup +10, usage -1, refund +1 → total should be 60
    for (id, kind, delta) in [
        ("tx-p", "purchase", 50i64),
        ("tx-t", "topup", 10),
        ("tx-u", "usage", -1),
        ("tx-r", "refund", 1),
    ] {
        sqlx::query(
            "INSERT INTO transactions (id, user_id, device_id, kind, credits_delta, created_at) \
             VALUES (?, ?, NULL, ?, ?, ?)",
        )
        .bind(id)
        .bind(&uid.0)
        .bind(kind)
        .bind(delta)
        .bind(now)
        .execute(&ctx.pool)
        .await
        .unwrap();
    }
    sqlx::query("UPDATE users SET credits = 60 WHERE id = ?")
        .bind(&uid.0)
        .execute(&ctx.pool)
        .await
        .unwrap();

    let (status, body) = get_auth(&ctx.app, "/v1/ai/quota", &token).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["credits_remaining"], 60);
    assert_eq!(body["credits_total"], 60);
}

#[tokio::test]
async fn packs_returns_list_for_device() {
    let ctx = test_ctx().await;
    // Device-only token (no user link required for browsing packs)
    let (_, reg) = post_json(
        &ctx.app,
        "/v1/device/register",
        r#"{"device_uuid":"d-packs","platform":"macos","app_version":"0.0.3"}"#,
    )
    .await;
    let device_token = reg["token"].as_str().unwrap().to_string();
    let (status, body) = get_auth(&ctx.app, "/v1/billing/packs", &device_token).await;
    assert_eq!(status, StatusCode::OK);
    let packs = body.as_array().unwrap();
    let ids: Vec<&str> = packs.iter().filter_map(|p| p["id"].as_str()).collect();
    assert_eq!(
        packs.len(),
        3,
        "all seeded packs must insert despite UNIQUE(provider_product_id)"
    );
    assert!(ids.contains(&"starter"));
    assert!(ids.contains(&"pro"));
    assert!(ids.contains(&"unlimited"));
}

#[tokio::test]
async fn checkout_returns_url_for_known_pack() {
    let ctx = test_ctx().await;
    // provider_product_id = 'FILL_ME' in seeded packs → triggers dev fallback URL
    let token = register_and_link(&ctx, "d-co", "co@example.com", 0).await;
    let (status, body) = post_auth(
        &ctx.app,
        "/v1/billing/checkout",
        &token,
        r#"{"pack_id":"starter"}"#,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let url = body["checkout_url"].as_str().unwrap();
    assert!(url.contains("starter"));
}

#[tokio::test]
async fn live_checkout_rejects_placeholder_product_id() {
    let ctx = test_ctx_with_config(
        Arc::new(MockUpstream {
            mode: MockMode::OkKeep,
        }),
        |config| config.paddle_env = "live".into(),
    )
    .await;
    let token = register_and_link(&ctx, "d-live-co", "live-co@example.com", 0).await;
    let (status, body) = post_auth(
        &ctx.app,
        "/v1/billing/checkout",
        &token,
        r#"{"pack_id":"starter"}"#,
    )
    .await;

    assert_eq!(status, StatusCode::INTERNAL_SERVER_ERROR);
    assert_eq!(body["error"], "internal_error");
}

#[tokio::test]
async fn otp_429_on_resend_within_cooldown() {
    let ctx = test_ctx().await;
    let (_, reg) = post_json(
        &ctx.app,
        "/v1/device/register",
        r#"{"device_uuid":"d-cool","platform":"macos","app_version":"0.0.3"}"#,
    )
    .await;
    let device_token = reg["token"].as_str().unwrap().to_string();
    let (s1, _) = post_auth(
        &ctx.app,
        "/v1/auth/request-otp",
        &device_token,
        r#"{"email":"cool@example.com"}"#,
    )
    .await;
    // Second request within the 60s cooldown window
    let (s2, body2) = post_auth(
        &ctx.app,
        "/v1/auth/request-otp",
        &device_token,
        r#"{"email":"cool@example.com"}"#,
    )
    .await;
    assert_eq!(s1, StatusCode::OK);
    assert_eq!(s2, StatusCode::TOO_MANY_REQUESTS);
    assert_eq!(body2["error"], "rate_limited");
}

#[tokio::test]
async fn otp_blocks_after_max_attempts() {
    let ctx = test_ctx().await;
    let (_, reg) = post_json(
        &ctx.app,
        "/v1/device/register",
        r#"{"device_uuid":"d-brute","platform":"macos","app_version":"0.0.3"}"#,
    )
    .await;
    let device_token = reg["token"].as_str().unwrap().to_string();
    let _ = post_auth(
        &ctx.app,
        "/v1/auth/request-otp",
        &device_token,
        r#"{"email":"brute@example.com"}"#,
    )
    .await;
    // Submit MAX_ATTEMPTS (5) wrong codes to exhaust the attempt counter
    for _ in 0..5 {
        let _ = post_auth(
            &ctx.app,
            "/v1/auth/verify-otp",
            &device_token,
            r#"{"email":"brute@example.com","code":"000000","device_uuid":"d-brute"}"#,
        )
        .await;
    }
    // OTP row deleted after 5 failed attempts; any further attempt must fail
    let (status, body) = post_auth(
        &ctx.app,
        "/v1/auth/verify-otp",
        &device_token,
        r#"{"email":"brute@example.com","code":"000000","device_uuid":"d-brute"}"#,
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert_eq!(body["error"], "unauthorized");
}
