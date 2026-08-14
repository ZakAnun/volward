CREATE TABLE IF NOT EXISTS packs (
    id            TEXT    PRIMARY KEY,        -- starter | pro | unlimited
    ls_variant_id TEXT    NOT NULL UNIQUE,    -- 部署时从 LS Dashboard 填入
    credits       INTEGER NOT NULL,
    price_cny     INTEGER NOT NULL,           -- 分，仅展示用
    label_zh      TEXT    NOT NULL,
    label_en      TEXT    NOT NULL,
    active        INTEGER NOT NULL DEFAULT 1
);
-- Unique placeholders so all three rows insert under UNIQUE(ls_variant_id).
-- Replace FILL_ME_* with real Lemon Squeezy variant ids before production checkout.
INSERT OR IGNORE INTO packs (id, ls_variant_id, credits, price_cny, label_zh, label_en) VALUES
    ('starter',   'FILL_ME_starter', 50,  990,  '入门包 50 次',  'Starter – 50 analyses'),
    ('pro',       'FILL_ME_pro', 200, 2990, '进阶包 200 次', 'Pro – 200 analyses'),
    ('unlimited', 'FILL_ME_unlimited', 999, 6990, '无限包 999 次', 'Unlimited – 999 analyses');
