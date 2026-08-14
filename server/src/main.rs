use volward_platform_api::config::Config;
use volward_platform_api::{app, db, default_mailer, default_upstream, AppState};

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,tower_http=info".into()),
        )
        .init();

    let config = Config::from_env().unwrap_or_else(|e| {
        eprintln!("config error: {e}");
        std::process::exit(1);
    });
    let mailer = default_mailer(&config).unwrap_or_else(|e| {
        eprintln!("mailer config error: {e}");
        std::process::exit(1);
    });
    let upstream = default_upstream(&config);
    let pool = db::init_pool(&config.database_url)
        .await
        .unwrap_or_else(|e| {
            eprintln!("db error: {e}");
            std::process::exit(1);
        });
    let bind = config.bind_addr.clone();
    let state = AppState::new(pool, config, mailer, upstream);
    let listener = tokio::net::TcpListener::bind(&bind)
        .await
        .unwrap_or_else(|e| {
            eprintln!("bind {bind}: {e}");
            std::process::exit(1);
        });
    tracing::info!("listening on {bind}");
    axum::serve(listener, app(state)).await.unwrap();
}
