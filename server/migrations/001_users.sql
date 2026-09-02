CREATE TABLE IF NOT EXISTS users (
    id          TEXT    PRIMARY KEY,          -- UUID v4，服务端生成
    email       TEXT    NOT NULL UNIQUE,
    credits     INTEGER NOT NULL DEFAULT 0,
    created_at  INTEGER NOT NULL,             -- unix ms
    last_seen_at INTEGER
);
