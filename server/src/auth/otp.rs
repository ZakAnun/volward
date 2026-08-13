use chrono::Utc;
use rand::Rng;
use sha2::{Digest, Sha256};
use sqlx::SqlitePool;

use crate::error::AppError;

const OTP_TTL_MS: i64 = 300_000;
const RESEND_COOLDOWN_MS: i64 = 60_000;
const MAX_ATTEMPTS: i64 = 5;

pub fn hash_code(code: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(code.as_bytes());
    hex::encode(hasher.finalize())
}

pub fn generate_code() -> String {
    let n: u32 = rand::thread_rng().gen_range(0..1_000_000);
    format!("{n:06}")
}

pub async fn create_and_store(pool: &SqlitePool, email: &str) -> Result<String, AppError> {
    let now = Utc::now().timestamp_millis();
    let existing: Option<(i64,)> =
        sqlx::query_as("SELECT created_at FROM otps WHERE email = ?")
            .bind(email)
            .fetch_optional(pool)
            .await?;
    if let Some((created_at,)) = existing {
        if now - created_at < RESEND_COOLDOWN_MS {
            return Err(AppError::TooManyRequests);
        }
    }

    let code = generate_code();
    let hash = hash_code(&code);
    let expires = now + OTP_TTL_MS;
    sqlx::query(
        r#"
        INSERT INTO otps (email, code_hash, expires_at, attempts, created_at)
        VALUES (?, ?, ?, 0, ?)
        ON CONFLICT(email) DO UPDATE SET
            code_hash = excluded.code_hash,
            expires_at = excluded.expires_at,
            attempts = 0,
            created_at = excluded.created_at
        "#,
    )
    .bind(email)
    .bind(&hash)
    .bind(expires)
    .bind(now)
    .execute(pool)
    .await?;
    Ok(code)
}

pub async fn verify_and_consume(
    pool: &SqlitePool,
    email: &str,
    code: &str,
) -> Result<(), AppError> {
    let now = Utc::now().timestamp_millis();
    let row: Option<(String, i64, i64)> =
        sqlx::query_as("SELECT code_hash, expires_at, attempts FROM otps WHERE email = ?")
            .bind(email)
            .fetch_optional(pool)
            .await?;
    let Some((hash, expires_at, attempts)) = row else {
        return Err(AppError::UnauthorizedMsg("invalid_otp"));
    };
    if attempts >= MAX_ATTEMPTS || now > expires_at {
        let _ = sqlx::query("DELETE FROM otps WHERE email = ?")
            .bind(email)
            .execute(pool)
            .await;
        return Err(AppError::UnauthorizedMsg("invalid_otp"));
    }
    if hash != hash_code(code) {
        sqlx::query("UPDATE otps SET attempts = attempts + 1 WHERE email = ?")
            .bind(email)
            .execute(pool)
            .await?;
        return Err(AppError::UnauthorizedMsg("invalid_otp"));
    }
    sqlx::query("DELETE FROM otps WHERE email = ?")
        .bind(email)
        .execute(pool)
        .await?;
    Ok(())
}
