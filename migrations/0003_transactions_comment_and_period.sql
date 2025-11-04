ALTER TABLE transactions
    RENAME COLUMN description TO comment;

CREATE INDEX IF NOT EXISTS idx_transactions_user_period ON transactions(user_id, occurred_at DESC);
