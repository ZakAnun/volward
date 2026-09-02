CREATE TABLE IF NOT EXISTS devices (
    id          TEXT    PRIMARY KEY,          -- device_uuid，App 生成
    user_id     TEXT    REFERENCES users(id), -- NULL = 未绑定邮箱
    platform    TEXT,                         -- macos | windows | linux
    app_version TEXT,
    created_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_devices_user ON devices(user_id);
