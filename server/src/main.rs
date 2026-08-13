use volward_platform_api::config::Config;
use volward_platform_api::{app, db, AppState};

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .init();

    let config = Config::from_env().unwrap_or_else(|e| {
        tracing::error!("{e}");
        std::process::exit(1);
    });

    let pool = db::init_pool(&config.database_url)
        .await
        .unwrap_or_else(|e| {
            tracing::error!("failed to open database: {e}");
            std::process::exit(1);
        });

    let bind_addr = config.bind_addr.clone();
    let router = app(AppState::new(pool, config));

    let listener = tokio::net::TcpListener::bind(&bind_addr)
        .await
        .unwrap_or_else(|e| {
            tracing::error!("failed to bind {bind_addr}: {e}");
            std::process::exit(1);
        });
    tracing::info!("listening on {bind_addr}");
    axum::serve(listener, router).await.unwrap_or_else(|e| {
        tracing::error!("server error: {e}");
        std::process::exit(1);
    });
}
