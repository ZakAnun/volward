use std::str::FromStr;

use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::SqlitePool;

pub fn normalize_sqlite_url(url: &str) -> String {
    let trimmed = url.trim();
    if trimmed.starts_with("sqlite:") {
        trimmed.to_string()
    } else {
        format!("sqlite:{trimmed}")
    }
}

pub async fn init_pool(database_url: &str) -> Result<SqlitePool, sqlx::Error> {
    let url = normalize_sqlite_url(database_url);
    let options = SqliteConnectOptions::from_str(&url)?.create_if_missing(true);

    let pool = SqlitePoolOptions::new()
        .max_connections(8)
        .connect_with(options)
        .await?;

    sqlx::query("PRAGMA journal_mode=WAL;")
        .execute(&pool)
        .await?;
    sqlx::query("PRAGMA busy_timeout=5000;")
        .execute(&pool)
        .await?;
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .map_err(|e| sqlx::Error::Migrate(Box::new(e)))?;

    Ok(pool)
}
