-- 012_credit_packs_usd_anchor.sql
-- Credits + labels for scheme A (one basic Home full run ≈ default cap 100).
-- List USD / implied CNY are applied in 013. Do not write marketing CNY here.
UPDATE packs SET
  credits = 100,
  label_zh = '100 积分 · 试用（约 1 次基础完整分析）',
  label_en = '100 credits · Trial (~1 basic full run)'
WHERE id = 'trial';

UPDATE packs SET
  credits = 220,
  label_zh = '220 积分 · 约 2 次基础完整分析',
  label_en = '220 credits · ~2 basic full runs'
WHERE id = 'standard';

UPDATE packs SET
  credits = 550,
  label_zh = '550 积分 · 约 5 次基础完整分析',
  label_en = '550 credits · ~5 basic full runs'
WHERE id = 'plus';

UPDATE packs SET
  credits = 1200,
  label_zh = '1200 积分 · 大磁盘 / 多次扫描',
  label_en = '1200 credits · Large disk / many runs'
WHERE id = 'max';
