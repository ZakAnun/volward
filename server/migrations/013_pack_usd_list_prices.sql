-- 013_pack_usd_list_prices.sql
-- Checkout list prices in USD cents (Paddle/App). price_cny = implied CNY at FX 7.2.
-- Column `price_usd_cents` is added idempotently in db.rs before this file runs.
UPDATE packs SET
  price_usd_cents = 149,
  price_cny = 1073
WHERE id = 'trial';

UPDATE packs SET
  price_usd_cents = 299,
  price_cny = 2153
WHERE id = 'standard';

UPDATE packs SET
  price_usd_cents = 649,
  price_cny = 4673
WHERE id = 'plus';

UPDATE packs SET
  price_usd_cents = 1299,
  price_cny = 9353
WHERE id = 'max';
