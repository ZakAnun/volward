-- 011_credit_packs.sql
-- Retire legacy starter/pro/unlimited tiers; seed credit-based packs per design §5.4.
-- Replace FILL_ME_* with real Paddle price ids before production checkout.
UPDATE packs SET active = 0 WHERE id IN ('starter', 'pro', 'unlimited');

INSERT OR REPLACE INTO packs (id, provider_product_id, credits, price_cny, label_zh, label_en, active) VALUES
    ('trial',    'FILL_ME_trial',    30,  690,  '30 积分 · 试用',              '30 credits · Trial', 1),
    ('standard', 'FILL_ME_standard', 50,  990,  '50 积分',                   '50 credits', 1),
    ('plus',     'FILL_ME_plus',    150, 2490,  '150 积分 · 约 3 次完整分析', '150 credits · ~3 full runs', 1),
    ('max',      'FILL_ME_max',     400, 5990,  '400 积分 · 大磁盘 / 多次扫描', '400 credits · Large disk', 1);
