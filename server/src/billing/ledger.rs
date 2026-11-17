use super::env_credits::{balance_for_env, user_credit_debit_sql, user_credit_refund_sql};
use crate::error::AppError;
use sqlx::SqlitePool;
use uuid::Uuid;

pub async fn balance(pool: &SqlitePool, user_id: &str, paddle_env: &str) -> Result<i64, AppError> {
    let balances: (i64, i64) =
        sqlx::query_as("SELECT credits_sandbox, credits_live FROM users WHERE id = ?")
            .bind(user_id)
            .fetch_one(pool)
            .await?;
    balance_for_env(balances.0, balances.1, paddle_env)
}

pub async fn debit_one_credit(
    pool: &SqlitePool,
    user_id: &str,
    device_id: &str,
    candidate_count: i64,
    paddle_env: &str,
) -> Result<(), AppError> {
    let mut conn = pool.acquire().await?;
    sqlx::query("BEGIN IMMEDIATE").execute(&mut *conn).await?;
    let debit_sql = match user_credit_debit_sql(paddle_env) {
        Ok(sql) => sql,
        Err(e) => {
            let _ = sqlx::query("ROLLBACK").execute(&mut *conn).await;
            return Err(e);
        }
    };
    let result = sqlx::query(debit_sql)
        .bind(user_id)
        .execute(&mut *conn)
        .await;
    let result = match result {
        Ok(r) => r,
        Err(e) => {
            let _ = sqlx::query("ROLLBACK").execute(&mut *conn).await;
            return Err(e.into());
        }
    };
    if result.rows_affected() == 0 {
        let _ = sqlx::query("ROLLBACK").execute(&mut *conn).await;
        return Err(AppError::PaymentRequired);
    }
    let tid = Uuid::new_v4().to_string();
    let now = chrono::Utc::now().timestamp_millis();
    if let Err(e) = sqlx::query(
        r#"
        INSERT INTO transactions (id, user_id, device_id, kind, credits_delta, candidate_count, paddle_env, created_at)
        VALUES (?, ?, ?, 'usage', -1, ?, ?, ?)
        "#,
    )
    .bind(&tid)
    .bind(user_id)
    .bind(device_id)
    .bind(candidate_count)
    .bind(paddle_env)
    .bind(now)
    .execute(&mut *conn)
    .await
    {
        let _ = sqlx::query("ROLLBACK").execute(&mut *conn).await;
        return Err(e.into());
    }
    sqlx::query("COMMIT").execute(&mut *conn).await?;
    Ok(())
}

pub async fn refund_one_credit(
    pool: &SqlitePool,
    user_id: &str,
    device_id: &str,
    paddle_env: &str,
) -> Result<(), AppError> {
    let mut conn = pool.acquire().await?;
    sqlx::query("BEGIN IMMEDIATE").execute(&mut *conn).await?;
    let refund_sql = match user_credit_refund_sql(paddle_env) {
        Ok(sql) => sql,
        Err(e) => {
            let _ = sqlx::query("ROLLBACK").execute(&mut *conn).await;
            return Err(e);
        }
    };
    if let Err(e) = sqlx::query(refund_sql)
        .bind(user_id)
        .execute(&mut *conn)
        .await
    {
        let _ = sqlx::query("ROLLBACK").execute(&mut *conn).await;
        return Err(e.into());
    }
    let tid = Uuid::new_v4().to_string();
    let now = chrono::Utc::now().timestamp_millis();
    if let Err(e) = sqlx::query(
        r#"
        INSERT INTO transactions (id, user_id, device_id, kind, credits_delta, paddle_env, created_at)
        VALUES (?, ?, ?, 'refund', 1, ?, ?)
        "#,
    )
    .bind(&tid)
    .bind(user_id)
    .bind(device_id)
    .bind(paddle_env)
    .bind(now)
    .execute(&mut *conn)
    .await
    {
        let _ = sqlx::query("ROLLBACK").execute(&mut *conn).await;
        return Err(e.into());
    }
    sqlx::query("COMMIT").execute(&mut *conn).await?;
    Ok(())
}
