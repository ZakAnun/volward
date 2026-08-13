use axum::body::Body;
use axum::http::{Request, StatusCode};
use tower::ServiceExt;

use crate::{app, db, AppState};

async fn test_app() -> axum::Router {
    let dir = tempfile::tempdir().expect("tempdir");
    let db_path = dir.path().join("platform.db");
    let url = format!("sqlite:{}?mode=rwc", db_path.display());
    std::mem::forget(dir);

    let config = crate::config::Config::for_test(url.clone());
    let pool = db::init_pool(&url).await.expect("init pool");
    app(AppState::new(pool, config))
}

#[tokio::test]
async fn health_ok() {
    let app = test_app().await;
    let res = app
        .oneshot(
            Request::get("/health")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);

    let bytes = axum::body::to_bytes(res.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(json["ok"], true);
}
