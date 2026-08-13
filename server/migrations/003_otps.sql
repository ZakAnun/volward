CREATE TABLE IF NOT EXISTS otps (
    email       TEXT    PRIMARY KEY,          -- 一个邮箱同时只有一个有效 OTP
    code_hash   TEXT    NOT NULL,             -- SHA-256(code)，不存明文
    expires_at  INTEGER NOT NULL,
    attempts    INTEGER NOT NULL DEFAULT 0,   -- 超过 5 次即失效
    created_at  INTEGER NOT NULL
);
