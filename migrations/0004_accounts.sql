-- Accounts support
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS accounts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    family_id UUID NOT NULL REFERENCES families(id),
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    currency CHAR(3) NOT NULL,
    balance_minor BIGINT NOT NULL DEFAULT 0,
    is_archived BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_accounts_family ON accounts(family_id, is_archived);

ALTER TABLE transactions
    ADD COLUMN IF NOT EXISTS account_id UUID;

ALTER TABLE transactions
    ADD COLUMN IF NOT EXISTS comment TEXT;

-- Seed default accounts for existing families
INSERT INTO accounts (family_id, name, type, currency)
SELECT f.id, 'Основной счёт', 'cash', f.currency_base
FROM families f
WHERE NOT EXISTS (
    SELECT 1 FROM accounts a WHERE a.family_id = f.id
);

-- Attach existing transactions to the first account in the family
WITH ranked_accounts AS (
    SELECT id, family_id,
           ROW_NUMBER() OVER (PARTITION BY family_id ORDER BY created_at) AS rn
    FROM accounts
)
UPDATE transactions t
SET account_id = ra.id
FROM ranked_accounts ra
WHERE ra.family_id = t.family_id AND ra.rn = 1 AND t.account_id IS NULL;

-- Ensure account reference is mandatory
ALTER TABLE transactions
    ALTER COLUMN account_id SET NOT NULL;

ALTER TABLE transactions
    ADD CONSTRAINT fk_transactions_account FOREIGN KEY (account_id) REFERENCES accounts(id);

-- Recalculate account balances from transactions
WITH deltas AS (
    SELECT account_id,
           SUM(CASE WHEN type = 'income' THEN amount_minor ELSE -amount_minor END) AS delta
    FROM transactions
    GROUP BY account_id
)
UPDATE accounts a
SET balance_minor = COALESCE(d.delta, 0),
    updated_at = NOW()
FROM deltas d
WHERE a.id = d.account_id;
