-- Tag Paddle purchase transactions with sandbox vs live for audit/reconciliation.
ALTER TABLE transactions ADD COLUMN paddle_env TEXT;

-- Pre-live purchases were sandbox-era test data.
UPDATE transactions
SET paddle_env = 'sandbox'
WHERE kind = 'purchase' AND paddle_env IS NULL;
