use std::str::FromStr;

use sqlx::migrate::{Migrate, Migrator};
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

static MIGRATOR: Migrator = sqlx::migrate!("./migrations");

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
    run_migrations(&pool).await?;

    Ok(pool)
}

/// Apply sqlx migrations, adding `packs.price_usd_cents` before 013 if needed.
///
/// Production may already have the column from a manual ALTER; `ADD COLUMN` in
/// a SQL file would then fail and block startup. Fresh DBs get the column here
/// after 005 creates `packs` and before 013 writes USD list prices.
async fn run_migrations(pool: &SqlitePool) -> Result<(), sqlx::Error> {
    let mut conn = pool.acquire().await?;
    conn.lock()
        .await
        .map_err(|e| sqlx::Error::Migrate(Box::new(e)))?;
    let result: Result<(), sqlx::Error> = async {
        conn.ensure_migrations_table()
            .await
            .map_err(|e| sqlx::Error::Migrate(Box::new(e)))?;
        let applied = conn
            .list_applied_migrations()
            .await
            .map_err(|e| sqlx::Error::Migrate(Box::new(e)))?;
        for migration in MIGRATOR.iter() {
            if applied.iter().any(|a| a.version == migration.version) {
                continue;
            }
            if migration.version >= 13 {
                add_price_usd_cents_if_missing(&mut conn).await?;
            }
            conn.apply(migration)
                .await
                .map_err(|e| sqlx::Error::Migrate(Box::new(e)))?;
        }
        Ok(())
    }
    .await;
    let unlock = conn
        .unlock()
        .await
        .map_err(|e| sqlx::Error::Migrate(Box::new(e)));
    result?;
    unlock?;
    Ok(())
}

async fn add_price_usd_cents_if_missing(
    conn: &mut sqlx::pool::PoolConnection<sqlx::Sqlite>,
) -> Result<(), sqlx::Error> {
    let packs_exists: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'packs'",
    )
    .fetch_one(&mut **conn)
    .await?;
    if packs_exists == 0 {
        return Ok(());
    }
    let col_exists: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM pragma_table_info('packs') WHERE name = 'price_usd_cents'",
    )
    .fetch_one(&mut **conn)
    .await?;
    if col_exists == 0 {
        sqlx::query("ALTER TABLE packs ADD COLUMN price_usd_cents INTEGER")
            .execute(&mut **conn)
            .await?;
    }
    Ok(())
}
