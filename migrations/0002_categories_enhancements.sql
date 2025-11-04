ALTER TABLE categories
    ADD COLUMN parent_id UUID NULL;

ALTER TABLE categories
    ADD COLUMN description TEXT;

ALTER TABLE categories
    ADD COLUMN is_archived BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE categories
    ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_categories_family_active ON categories(family_id, is_archived);
