-- 014_paddle_dual_env.sql
-- Dual Paddle price ids and per-environment credit balances.

ALTER TABLE users RENAME COLUMN credits TO credits_sandbox;
ALTER TABLE users ADD COLUMN credits_live INTEGER NOT NULL DEFAULT 0;

ALTER TABLE packs RENAME COLUMN provider_product_id TO provider_product_id_sandbox;
ALTER TABLE packs ADD COLUMN provider_product_id_live TEXT;
