package store

import (
	"context"
	"database/sql"
	"errors"
	"time"

	"github.com/google/uuid"

	"familybudget/internal/domain"
)

type Store struct {
	db *sql.DB
}

func New(db *sql.DB) *Store {
	return &Store{db: db}
}

func (s *Store) CreateFamily(ctx context.Context, name, currency string) (*domain.Family, error) {
	family := &domain.Family{
		ID:           uuid.NewString(),
		Name:         name,
		CurrencyBase: currency,
		CreatedAt:    time.Now().UTC(),
	}
	_, err := s.db.ExecContext(ctx, `INSERT INTO families (id, name, currency_base, created_at) VALUES (?, ?, ?, ?)`,
		family.ID, family.Name, family.CurrencyBase, family.CreatedAt)
	if err != nil {
		return nil, err
	}
	return family, nil
}

func (s *Store) CreateUser(ctx context.Context, user *domain.User, passwordHash string) error {
	_, err := s.db.ExecContext(ctx, `INSERT INTO users (id, family_id, email, password_hash, name, role, locale, currency_default, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		user.ID, user.FamilyID, user.Email, passwordHash, user.Name, user.Role, user.Locale, user.CurrencyDefault, user.CreatedAt, user.UpdatedAt)
	return err
}

func (s *Store) FindUserByEmail(ctx context.Context, email string) (*domain.User, error) {
	row := s.db.QueryRowContext(ctx, `SELECT id, family_id, email, name, role, locale, currency_default, created_at, updated_at FROM users WHERE email = ?`, email)
	var user domain.User
	if err := row.Scan(&user.ID, &user.FamilyID, &user.Email, &user.Name, &user.Role, &user.Locale, &user.CurrencyDefault, &user.CreatedAt, &user.UpdatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &user, nil
}

func (s *Store) GetUser(ctx context.Context, id string) (*domain.User, error) {
	row := s.db.QueryRowContext(ctx, `SELECT id, family_id, email, name, role, locale, currency_default, created_at, updated_at FROM users WHERE id = ?`, id)
	var user domain.User
	if err := row.Scan(&user.ID, &user.FamilyID, &user.Email, &user.Name, &user.Role, &user.Locale, &user.CurrencyDefault, &user.CreatedAt, &user.UpdatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &user, nil
}

func (s *Store) CreateCategory(ctx context.Context, category *domain.Category) error {
	_, err := s.db.ExecContext(ctx, `INSERT INTO categories (id, family_id, name, type, color, is_system, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)`,
		category.ID, category.FamilyID, category.Name, category.Type, category.Color, category.IsSystem, category.CreatedAt)
	return err
}

func (s *Store) ListCategoriesByFamily(ctx context.Context, familyID string) ([]domain.Category, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, family_id, name, type, color, is_system, created_at FROM categories WHERE family_id = ? ORDER BY name`, familyID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var categories []domain.Category
	for rows.Next() {
		var category domain.Category
		var isSystem int
		if err := rows.Scan(&category.ID, &category.FamilyID, &category.Name, &category.Type, &category.Color, &isSystem, &category.CreatedAt); err != nil {
			return nil, err
		}
		category.IsSystem = isSystem == 1
		categories = append(categories, category)
	}
	return categories, rows.Err()
}

func (s *Store) GetCategory(ctx context.Context, id string) (*domain.Category, error) {
	row := s.db.QueryRowContext(ctx, `SELECT id, family_id, name, type, color, is_system, created_at FROM categories WHERE id = ?`, id)
	var category domain.Category
	var isSystem int
	if err := row.Scan(&category.ID, &category.FamilyID, &category.Name, &category.Type, &category.Color, &isSystem, &category.CreatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	category.IsSystem = isSystem == 1
	return &category, nil
}

func (s *Store) CreateTransaction(ctx context.Context, txn *domain.Transaction) error {
	_, err := s.db.ExecContext(ctx, `INSERT INTO transactions (id, family_id, user_id, category_id, type, amount_minor, currency, description, occurred_at, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		txn.ID, txn.FamilyID, txn.UserID, txn.CategoryID, txn.Type, txn.AmountMinor, txn.Currency, txn.Description, txn.OccurredAt, txn.CreatedAt, txn.UpdatedAt)
	return err
}

func (s *Store) ListTransactionsByUser(ctx context.Context, userID string) ([]domain.Transaction, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, family_id, user_id, category_id, type, amount_minor, currency, description, occurred_at, created_at, updated_at FROM transactions WHERE user_id = ? ORDER BY occurred_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var txns []domain.Transaction
	for rows.Next() {
		var txn domain.Transaction
		if err := rows.Scan(&txn.ID, &txn.FamilyID, &txn.UserID, &txn.CategoryID, &txn.Type, &txn.AmountMinor, &txn.Currency, &txn.Description, &txn.OccurredAt, &txn.CreatedAt, &txn.UpdatedAt); err != nil {
			return nil, err
		}
		txns = append(txns, txn)
	}
	return txns, rows.Err()
}

func (s *Store) GetFamily(ctx context.Context, id string) (*domain.Family, error) {
	row := s.db.QueryRowContext(ctx, `SELECT id, name, currency_base, created_at FROM families WHERE id = ?`, id)
	var family domain.Family
	if err := row.Scan(&family.ID, &family.Name, &family.CurrencyBase, &family.CreatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &family, nil
}
