-- transactions.note is already defined in 004_transactions.sql (spec §6).
-- Keep this versioned migration so environments that applied an older 004
-- without `note` can be patched manually; here it is a no-op.
SELECT 1;
