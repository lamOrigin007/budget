package store

import (
	"database/sql"
	"fmt"
	"strings"
)

func OpenSQLite(path string) (*sql.DB, error) {
	db, err := sql.Open("sqlite3", fmt.Sprintf("file:%s?_foreign_keys=on", path))
	if err != nil {
		return nil, err
	}
	if err := migrate(db); err != nil {
		db.Close()
		return nil, err
	}
	return db, nil
}

func migrate(db *sql.DB) error {
	schema := []string{
		`CREATE TABLE IF NOT EXISTS families (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            currency_base TEXT NOT NULL,
            created_at TIMESTAMP NOT NULL
        );`,
		`CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            family_id TEXT NOT NULL REFERENCES families(id),
            email TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL,
            name TEXT NOT NULL,
            role TEXT NOT NULL,
            locale TEXT NOT NULL,
            currency_default TEXT NOT NULL,
            display_settings TEXT NOT NULL,
            created_at TIMESTAMP NOT NULL,
            updated_at TIMESTAMP NOT NULL
        );`,
		`CREATE TABLE IF NOT EXISTS categories (
            id TEXT PRIMARY KEY,
            family_id TEXT NOT NULL REFERENCES families(id),
            parent_id TEXT NULL REFERENCES categories(id),
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            color TEXT NOT NULL,
            description TEXT,
            is_system INTEGER NOT NULL,
            is_archived INTEGER NOT NULL DEFAULT 0,
            created_at TIMESTAMP NOT NULL,
            updated_at TIMESTAMP NOT NULL
        );`,
		`CREATE TABLE IF NOT EXISTS accounts (
    id TEXT PRIMARY KEY,
    family_id TEXT NOT NULL REFERENCES families(id),
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    currency TEXT NOT NULL,
    balance_minor INTEGER NOT NULL DEFAULT 0,
    is_shared INTEGER NOT NULL DEFAULT 1,
    is_archived INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL
);`,
		`CREATE TABLE IF NOT EXISTS transactions (
            id TEXT PRIMARY KEY,
            family_id TEXT NOT NULL REFERENCES families(id),
            user_id TEXT NOT NULL REFERENCES users(id),
            account_id TEXT NOT NULL REFERENCES accounts(id),
            category_id TEXT NOT NULL REFERENCES categories(id),
            type TEXT NOT NULL,
            amount_minor INTEGER NOT NULL,
            currency TEXT NOT NULL,
            comment TEXT,
            occurred_at TIMESTAMP NOT NULL,
            created_at TIMESTAMP NOT NULL,
            updated_at TIMESTAMP NOT NULL
        );`,
		`CREATE INDEX IF NOT EXISTS idx_transactions_user ON transactions(user_id);`,
		`CREATE INDEX IF NOT EXISTS idx_accounts_family ON accounts(family_id);`,
		`CREATE INDEX IF NOT EXISTS idx_categories_family ON categories(family_id);`,
		`CREATE INDEX IF NOT EXISTS idx_users_family ON users(family_id);`,
	}

	for _, stmt := range schema {
		if _, err := db.Exec(stmt); err != nil {
			return err
		}
	}

	alterStatements := []string{
		`ALTER TABLE categories ADD COLUMN parent_id TEXT NULL REFERENCES categories(id);`,
		`ALTER TABLE categories ADD COLUMN description TEXT;`,
		`ALTER TABLE categories ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0;`,
		`ALTER TABLE categories ADD COLUMN updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP;`,
		`ALTER TABLE transactions ADD COLUMN account_id TEXT REFERENCES accounts(id);`,
		`ALTER TABLE transactions ADD COLUMN comment TEXT;`,
		`ALTER TABLE accounts ADD COLUMN is_shared INTEGER NOT NULL DEFAULT 1;`,
		`ALTER TABLE users ADD COLUMN display_settings TEXT NOT NULL DEFAULT '{"theme":"system","density":"comfortable","show_archived":false,"show_totals_in_family_currency":true}';`,
	}

	for _, stmt := range alterStatements {
		if _, err := db.Exec(stmt); err != nil {
			if !isDuplicateColumnError(err) {
				return err
			}
		}
	}
	return nil
}

func isDuplicateColumnError(err error) bool {
	return err != nil && strings.Contains(err.Error(), "duplicate column name")
}
