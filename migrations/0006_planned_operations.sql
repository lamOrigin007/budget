CREATE TABLE IF NOT EXISTS planned_operations (
    id UUID PRIMARY KEY,
    family_id UUID NOT NULL REFERENCES families(id),
    user_id UUID NOT NULL REFERENCES users(id),
    account_id UUID NOT NULL REFERENCES accounts(id),
    category_id UUID NOT NULL REFERENCES categories(id),
    type TEXT NOT NULL,
    title TEXT NOT NULL,
    amount_minor BIGINT NOT NULL,
    currency CHAR(3) NOT NULL,
    comment TEXT,
    due_at TIMESTAMPTZ NOT NULL,
    recurrence TEXT,
    is_completed BOOLEAN NOT NULL DEFAULT FALSE,
    last_completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_planned_operations_family_due ON planned_operations(family_id, is_completed, due_at);
CREATE INDEX IF NOT EXISTS idx_planned_operations_user ON planned_operations(user_id);
