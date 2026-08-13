use std::sync::Arc;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::json;
use tower::ServiceExt;

use crate::auth::email::TestMailer;
use crate::{app, db, AppState};

struct TestCtx {
    app: axum::Router,
    mailer: TestMailer,
}

async fn test_ctx() -> TestCtx {
    let dir = tempfile::tempdir().expect("tempdir");
    let db_path = dir.path().join("platform.db");
    let url = format!("sqlite:{}?mode=rwc", db_path.display());
    std::mem::forget(dir);

    let config = crate::config::Config::for_test(url.clone());
    let pool = db::init_pool(&url).await.expect("init pool");
    let mailer = TestMailer::default();
    let app = app(AppState::new(pool, config, Arc::new(mailer.clone())));
    TestCtx { app, mailer }
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

#[tokio::test]
async fn health_ok() {
    let ctx = test_ctx().await;
    let res = ctx
        .app
        .oneshot(Request::get("/health").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let json = body_json(res).await;
    assert_eq!(json["ok"], true);
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
    let (_, reg) = post_json(
        &ctx.app,
        "/v1/device/register",
        r#"{"device_uuid":"dev-a","platform":"macos","app_version":"0.0.3"}"#,
    )
    .await;
    let device_token = reg["token"].as_str().unwrap().to_string();

    let (s, _) = post_auth(
        &ctx.app,
        "/v1/auth/request-otp",
        &device_token,
        r#"{"email":"alice@example.com"}"#,
    )
    .await;
    assert_eq!(s, StatusCode::OK);

    let (email, code) = ctx
        .mailer
        .last
        .lock()
        .unwrap()
        .clone()
        .expect("otp sent");
    assert_eq!(email, "alice@example.com");

    let (s, verified) = post_auth(
        &ctx.app,
        "/v1/auth/verify-otp",
        &device_token,
        &json!({
            "email": "alice@example.com",
            "code": code,
            "device_uuid": "dev-a"
        })
        .to_string(),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(verified["credits"], 0);
    assert_eq!(verified["email"], "alice@example.com");
    let user_token = verified["token"].as_str().unwrap();

    let (s, me) = get_auth(&ctx.app, "/v1/auth/me", user_token).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(me["email"], "alice@example.com");
    assert_eq!(me["credits"], 0);
}
