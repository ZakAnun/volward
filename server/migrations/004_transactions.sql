CREATE TABLE IF NOT EXISTS transactions (
    id            TEXT    PRIMARY KEY,
    user_id       TEXT    NOT NULL REFERENCES users(id),
    device_id     TEXT,                       -- 消耗时记录来自哪台设备
    kind          TEXT    NOT NULL CHECK(kind IN ('purchase', 'usage', 'topup', 'refund')),
    credits_delta INTEGER NOT NULL,           -- 正数=充值/退回，负数=消耗
    ls_order_id   TEXT UNIQUE,                -- purchase 时填，用于幂等
    candidate_count INTEGER,                  -- usage 时填，用于成本分析
    note          TEXT,                       -- topup/refund 人工备注（006 亦可 ALTER 追加）
    created_at    INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_tx_user ON transactions(user_id, created_at DESC);
