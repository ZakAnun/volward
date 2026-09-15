use anyhow::{bail, Context, Result};
use clap::{Parser, Subcommand};
use uuid::Uuid;
use volward_platform_api::db;

#[derive(Parser)]
#[command(name = "volward-admin")]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Grant credits (kind=topup) with an audit note.
    Grant {
        #[arg(long)]
        email: String,
        #[arg(long)]
        credits: i64,
        #[arg(long)]
        note: String,
    },
    /// Show credits and last 20 transactions.
    Show {
        #[arg(long)]
        email: String,
    },
    /// Platform-wide credit source totals (live vs sandbox vs topup).
    Stats,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    let url = std::env::var("DATABASE_URL").context("DATABASE_URL required")?;
    let pool = db::init_pool(&url).await.context("init pool")?;

    match cli.cmd {
        Cmd::Grant {
            email,
            credits,
            note,
        } => {
            if credits <= 0 {
                bail!("credits must be positive");
            }
            let user: Option<(String, i64)> =
                sqlx::query_as("SELECT id, credits FROM users WHERE email = ?")
                    .bind(email.trim().to_lowercase())
                    .fetch_optional(&pool)
                    .await?;
            let Some((uid, _)) = user else {
                bail!("user not found");
            };
            let mut conn = pool.acquire().await?;
            sqlx::query("BEGIN IMMEDIATE").execute(&mut *conn).await?;
            sqlx::query("UPDATE users SET credits = credits + ? WHERE id = ?")
                .bind(credits)
                .bind(&uid)
                .execute(&mut *conn)
                .await?;
            let tid = Uuid::new_v4().to_string();
            let now = chrono::Utc::now().timestamp_millis();
            sqlx::query(
                r#"
                INSERT INTO transactions (id, user_id, device_id, kind, credits_delta, note, created_at)
                VALUES (?, ?, NULL, 'topup', ?, ?, ?)
                "#,
            )
            .bind(&tid)
            .bind(&uid)
            .bind(credits)
            .bind(&note)
            .bind(now)
            .execute(&mut *conn)
            .await?;
            sqlx::query("COMMIT").execute(&mut *conn).await?;
            let (new_credits,): (i64,) = sqlx::query_as("SELECT credits FROM users WHERE id = ?")
                .bind(&uid)
                .fetch_one(&pool)
                .await?;
            println!("granted {credits} to {email}; balance={new_credits}");
        }
        Cmd::Show { email } => {
            let user: Option<(String, i64)> =
                sqlx::query_as("SELECT id, credits FROM users WHERE email = ?")
                    .bind(email.trim().to_lowercase())
                    .fetch_optional(&pool)
                    .await?;
            let Some((uid, credits)) = user else {
                bail!("user not found");
            };
            println!("user_id={uid}");
            println!("credits={credits}");
            let rows: Vec<(String, i64, Option<String>, Option<String>, i64)> = sqlx::query_as(
                r#"
                SELECT kind, credits_delta, note, paddle_env, created_at
                FROM transactions
                WHERE user_id = ?
                ORDER BY created_at DESC
                LIMIT 20
                "#,
            )
            .bind(&uid)
            .fetch_all(&pool)
            .await?;
            for (kind, delta, note, paddle_env, created) in rows {
                let env = paddle_env.unwrap_or_default();
                println!(
                    "{created}\t{kind}\t{delta}\t{env}\t{}",
                    note.unwrap_or_default()
                );
            }
        }
        Cmd::Stats => {
            let live: (i64,) = sqlx::query_as(
                "SELECT COALESCE(SUM(credits_delta), 0) FROM transactions \
                 WHERE kind = 'purchase' AND paddle_env = 'live'",
            )
            .fetch_one(&pool)
            .await?;
            let sandbox: (i64,) = sqlx::query_as(
                "SELECT COALESCE(SUM(credits_delta), 0) FROM transactions \
                 WHERE kind = 'purchase' AND paddle_env = 'sandbox'",
            )
            .fetch_one(&pool)
            .await?;
            let topup: (i64,) = sqlx::query_as(
                "SELECT COALESCE(SUM(credits_delta), 0) FROM transactions WHERE kind = 'topup'",
            )
            .fetch_one(&pool)
            .await?;
            let usage: (i64,) = sqlx::query_as(
                "SELECT COALESCE(SUM(credits_delta), 0) FROM transactions WHERE kind = 'usage'",
            )
            .fetch_one(&pool)
            .await?;
            let refund: (i64,) = sqlx::query_as(
                "SELECT COALESCE(SUM(credits_delta), 0) FROM transactions WHERE kind = 'refund'",
            )
            .fetch_one(&pool)
            .await?;
            println!("live_purchase_credits={}", live.0);
            println!("sandbox_purchase_credits={}", sandbox.0);
            println!("topup_credits={}", topup.0);
            println!("usage_credits={}", usage.0);
            println!("refund_credits={}", refund.0);
        }
    }
    Ok(())
}
