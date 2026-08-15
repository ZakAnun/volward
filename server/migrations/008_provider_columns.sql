-- 008_provider_columns.sql
-- Lemon Squeezy → provider-agnostic column names (Paddle price id / transaction id).
ALTER TABLE packs RENAME COLUMN ls_variant_id TO provider_product_id;
ALTER TABLE transactions RENAME COLUMN ls_order_id TO provider_order_id;

-- Do not carry production Lemon Squeezy variant ids into Paddle checkout.
-- Real Paddle price ids start with pri_; all other deployed values must be
-- replaced explicitly during the Paddle sandbox/live rollout.
UPDATE packs
SET provider_product_id = 'FILL_ME_' || id
WHERE provider_product_id NOT GLOB 'FILL_ME*'
  AND provider_product_id NOT GLOB 'pri_*';
