-- Repair environments that applied the original 005 with three identical FILL_ME
-- variant ids (UNIQUE kept only the first INSERT OR IGNORE row).
UPDATE packs SET ls_variant_id = 'FILL_ME_starter' WHERE id = 'starter' AND ls_variant_id = 'FILL_ME';
UPDATE packs SET ls_variant_id = 'FILL_ME_pro' WHERE id = 'pro' AND ls_variant_id = 'FILL_ME';
UPDATE packs SET ls_variant_id = 'FILL_ME_unlimited' WHERE id = 'unlimited' AND ls_variant_id = 'FILL_ME';

INSERT OR IGNORE INTO packs (id, ls_variant_id, credits, price_cny, label_zh, label_en) VALUES
    ('starter',   'FILL_ME_starter', 50,  990,  '入门包 50 次',  'Starter – 50 analyses'),
    ('pro',       'FILL_ME_pro', 200, 2990, '进阶包 200 次', 'Pro – 200 analyses'),
    ('unlimited', 'FILL_ME_unlimited', 999, 6990, '无限包 999 次', 'Unlimited – 999 analyses');
