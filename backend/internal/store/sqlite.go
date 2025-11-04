package store

import (
	"database/sql"
	"fmt"
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
            created_at TIMESTAMP NOT NULL,
            updated_at TIMESTAMP NOT NULL
        );`,
		`CREATE TABLE IF NOT EXISTS categories (
            id TEXT PRIMARY KEY,
            family_id TEXT NOT NULL REFERENCES families(id),
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            color TEXT NOT NULL,
            is_system INTEGER NOT NULL,
            created_at TIMESTAMP NOT NULL
        );`,
		`CREATE TABLE IF NOT EXISTS transactions (
            id TEXT PRIMARY KEY,
            family_id TEXT NOT NULL REFERENCES families(id),
            user_id TEXT NOT NULL REFERENCES users(id),
            category_id TEXT NOT NULL REFERENCES categories(id),
            type TEXT NOT NULL,
            amount_minor INTEGER NOT NULL,
            currency TEXT NOT NULL,
            description TEXT,
            occurred_at TIMESTAMP NOT NULL,
            created_at TIMESTAMP NOT NULL,
            updated_at TIMESTAMP NOT NULL
        );`,
		`CREATE INDEX IF NOT EXISTS idx_transactions_user ON transactions(user_id);`,
		`CREATE INDEX IF NOT EXISTS idx_categories_family ON categories(family_id);`,
		`CREATE INDEX IF NOT EXISTS idx_users_family ON users(family_id);`,
	}

	for _, stmt := range schema {
		if _, err := db.Exec(stmt); err != nil {
			return err
		}
	}
	return nil
}
