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

async fn test_ctx_with_upstream(upstream: Arc<dyn UpstreamClient>) -> TestCtx {
    let dir = tempfile::tempdir().expect("tempdir");
    let db_path = dir.path().join("platform.db");
    let url = format!("sqlite:{}?mode=rwc", db_path.display());
    std::mem::forget(dir);

    let config = crate::config::Config::for_test(url.clone());
    let pool = db::init_pool(&url).await.expect("init pool");
    let mailer = TestMailer::default();
    let app = app(AppState::new(
        pool.clone(),
        config,
        Arc::new(mailer.clone()),
        upstream,
    ));
    TestCtx { app, mailer, pool }
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

async fn get_auth(
    app: &axum::Router,
    path: &str,
    token: &str,
) -> (StatusCode, serde_json::Value) {
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

const ONE_CANDIDATE: &str =
    r#"{"candidates":[{"path":"/a","size_bytes":1,"is_dir":false}]}"#;

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
    assert!(body["entries"].as_array().unwrap().len() >= 1);
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
        "SELECT kind FROM transactions WHERE user_id = (SELECT id FROM users WHERE email = ?) ORDER BY created_at",
    )
    .bind("ufail@example.com")
    .fetch_all(&ctx.pool)
    .await
    .unwrap();
    let kinds: Vec<&str> = kinds.iter().map(|k| k.0.as_str()).collect();
    assert_eq!(kinds, vec!["usage", "refund"]);
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

fn sign_body(secret: &str, body: &[u8]) -> String {
    let mut mac = HmacSha256::new_from_slice(secret.as_bytes()).unwrap();
    mac.update(body);
    format!("sha256={}", hex::encode(mac.finalize().into_bytes()))
}

async fn post_signed(
    app: &axum::Router,
    path: &str,
    body: &str,
    signature: &str,
) -> StatusCode {
    let res = app
        .clone()
        .oneshot(
            Request::post(path)
                .header("content-type", "application/json")
                .header("X-Signature", signature)
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
        "meta": {
            "event_name": "order_created",
            "custom_data": { "user_id": uid.0, "pack_id": "starter" }
        },
        "data": { "id": "ord_1", "attributes": { "status": "paid" } }
    })
    .to_string();
    let sig = sign_body("test-webhook-secret", body.as_bytes());
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
    let kinds: Vec<(String,)> = sqlx::query_as(
        "SELECT kind FROM transactions WHERE user_id = ? ORDER BY created_at",
    )
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
        "meta": {
            "event_name": "order_created",
            "custom_data": { "user_id": uid.0, "pack_id": "starter" }
        },
        "data": { "id": "ord_forge", "attributes": { "status": "paid" } }
    })
    .to_string();
    let status = post_signed(
        &ctx.app,
        "/v1/billing/webhook",
        &body,
        "sha256=deadbeef",
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
