package store

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"

	"familybudget/internal/domain"
)

type Store struct {
	db *sql.DB
}

var ErrAccountArchived = errors.New("account is archived")

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

func (s *Store) CreateAccount(ctx context.Context, account *domain.Account) error {
	_, err := s.db.ExecContext(ctx, `INSERT INTO accounts (id, family_id, name, type, currency, balance_minor, is_shared, is_archived, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		account.ID, account.FamilyID, account.Name, account.Type, account.Currency, account.BalanceMinor, account.IsShared, account.IsArchived, account.CreatedAt, account.UpdatedAt)
	return err
}

func (s *Store) ListAccountsByFamily(ctx context.Context, familyID string) ([]domain.Account, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, family_id, name, type, currency, balance_minor, is_shared, is_archived, created_at, updated_at FROM accounts WHERE family_id = ? ORDER BY created_at`, familyID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var accounts []domain.Account
	for rows.Next() {
		var account domain.Account
		var isShared bool
		var isArchived bool
		if err := rows.Scan(&account.ID, &account.FamilyID, &account.Name, &account.Type, &account.Currency, &account.BalanceMinor, &isShared, &isArchived, &account.CreatedAt, &account.UpdatedAt); err != nil {
			return nil, err
		}
		account.IsShared = isShared
		account.IsArchived = isArchived
		accounts = append(accounts, account)
	}
	return accounts, rows.Err()
}

func (s *Store) GetAccount(ctx context.Context, id string) (*domain.Account, error) {
	row := s.db.QueryRowContext(ctx, `SELECT id, family_id, name, type, currency, balance_minor, is_shared, is_archived, created_at, updated_at FROM accounts WHERE id = ?`, id)
	var account domain.Account
	var isShared bool
	var isArchived bool
	if err := row.Scan(&account.ID, &account.FamilyID, &account.Name, &account.Type, &account.Currency, &account.BalanceMinor, &isShared, &isArchived, &account.CreatedAt, &account.UpdatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	account.IsShared = isShared
	account.IsArchived = isArchived
	return &account, nil
}

func (s *Store) ListFamilyMembers(ctx context.Context, familyID string) ([]domain.FamilyMember, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, name, email, role FROM users WHERE family_id = ? ORDER BY created_at`, familyID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var members []domain.FamilyMember
	for rows.Next() {
		var member domain.FamilyMember
		if err := rows.Scan(&member.ID, &member.Name, &member.Email, &member.Role); err != nil {
			return nil, err
		}
		members = append(members, member)
	}
	return members, rows.Err()
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
	_, err := s.db.ExecContext(ctx, `INSERT INTO categories (id, family_id, parent_id, name, type, color, description, is_system, is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		category.ID, category.FamilyID, category.ParentID, category.Name, category.Type, category.Color, nullableString(category.Description), category.IsSystem, category.IsArchived, category.CreatedAt, category.UpdatedAt)
	return err
}

func (s *Store) ListCategoriesByFamily(ctx context.Context, familyID string) ([]domain.Category, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, family_id, parent_id, name, type, color, description, is_system, is_archived, created_at, updated_at FROM categories WHERE family_id = ? ORDER BY is_archived, name`, familyID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var categories []domain.Category
	for rows.Next() {
		var category domain.Category
		var parentID sql.NullString
		var description sql.NullString
		var isSystem bool
		var isArchived bool
		if err := rows.Scan(&category.ID, &category.FamilyID, &parentID, &category.Name, &category.Type, &category.Color, &description, &isSystem, &isArchived, &category.CreatedAt, &category.UpdatedAt); err != nil {
			return nil, err
		}
		if parentID.Valid {
			category.ParentID = &parentID.String
		}
		if description.Valid {
			category.Description = description.String
		}
		category.IsSystem = isSystem
		category.IsArchived = isArchived
		categories = append(categories, category)
	}
	return categories, rows.Err()
}

func (s *Store) GetCategory(ctx context.Context, id string) (*domain.Category, error) {
	row := s.db.QueryRowContext(ctx, `SELECT id, family_id, parent_id, name, type, color, description, is_system, is_archived, created_at, updated_at FROM categories WHERE id = ?`, id)
	var category domain.Category
	var parentID sql.NullString
	var description sql.NullString
	var isSystem bool
	var isArchived bool
	if err := row.Scan(&category.ID, &category.FamilyID, &parentID, &category.Name, &category.Type, &category.Color, &description, &isSystem, &isArchived, &category.CreatedAt, &category.UpdatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	if parentID.Valid {
		category.ParentID = &parentID.String
	}
	if description.Valid {
		category.Description = description.String
	}
	category.IsSystem = isSystem
	category.IsArchived = isArchived
	return &category, nil
}

func (s *Store) UpdateCategory(ctx context.Context, category *domain.Category) error {
	res, err := s.db.ExecContext(ctx, `UPDATE categories SET parent_id = ?, name = ?, type = ?, color = ?, description = ?, updated_at = ? WHERE id = ? AND family_id = ?`,
		category.ParentID, category.Name, category.Type, category.Color, nullableString(category.Description), category.UpdatedAt, category.ID, category.FamilyID)
	if err != nil {
		return err
	}
	rows, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if rows == 0 {
		return sql.ErrNoRows
	}
	return nil
}

func (s *Store) SetCategoryArchived(ctx context.Context, id, familyID string, archived bool, updatedAt time.Time) error {
	res, err := s.db.ExecContext(ctx, `UPDATE categories SET is_archived = ?, updated_at = ? WHERE id = ? AND family_id = ?`, archived, updatedAt, id, familyID)
	if err != nil {
		return err
	}
	rows, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if rows == 0 {
		return sql.ErrNoRows
	}
	return nil
}

func nullableString(value string) interface{} {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	return value
}

func (s *Store) CreateTransaction(ctx context.Context, txn *domain.Transaction) error {
	dbTx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() {
		if err != nil {
			_ = dbTx.Rollback()
		}
	}()

	row := dbTx.QueryRowContext(ctx, `SELECT family_id, balance_minor, is_archived FROM accounts WHERE id = ?`, txn.AccountID)
	var accountFamily string
	var accountBalance int64
	var isArchived bool
	if scanErr := row.Scan(&accountFamily, &accountBalance, &isArchived); scanErr != nil {
		if errors.Is(scanErr, sql.ErrNoRows) {
			err = sql.ErrNoRows
			return err
		}
		err = scanErr
		return err
	}
	_ = accountBalance
	if accountFamily != txn.FamilyID {
		err = sql.ErrNoRows
		return err
	}
	if isArchived {
		err = ErrAccountArchived
		return err
	}

	delta := txn.AmountMinor
	if strings.ToLower(txn.Type) == "expense" {
		delta = -delta
	}

	res, execErr := dbTx.ExecContext(ctx, `UPDATE accounts SET balance_minor = balance_minor + ?, updated_at = ? WHERE id = ? AND family_id = ?`, delta, txn.UpdatedAt, txn.AccountID, txn.FamilyID)
	if execErr != nil {
		err = execErr
		return err
	}
	if affected, affErr := res.RowsAffected(); affErr != nil {
		err = affErr
		return err
	} else if affected == 0 {
		err = sql.ErrNoRows
		return err
	}

	_, execErr = dbTx.ExecContext(ctx, `INSERT INTO transactions (id, family_id, user_id, account_id, category_id, type, amount_minor, currency, comment, occurred_at, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		txn.ID, txn.FamilyID, txn.UserID, txn.AccountID, txn.CategoryID, txn.Type, txn.AmountMinor, txn.Currency, nullableString(txn.Comment), txn.OccurredAt, txn.CreatedAt, txn.UpdatedAt)
	if execErr != nil {
		err = execErr
		return err
	}

	if commitErr := dbTx.Commit(); commitErr != nil {
		err = commitErr
		return err
	}
	return nil
}

type TransactionListFilters struct {
	Start      *time.Time
	End        *time.Time
	Type       string
	CategoryID string
	AccountID  string
	UserID     string
}

func (s *Store) ListTransactionsByFamily(ctx context.Context, familyID string, filters TransactionListFilters) ([]domain.TransactionWithAuthor, error) {
	baseQuery := `SELECT t.id, t.family_id, t.user_id, t.account_id, t.category_id, t.type, t.amount_minor, t.currency, t.comment, t.occurred_at, t.created_at, t.updated_at,
        u.id, u.name, u.email, u.role
FROM transactions t
JOIN users u ON u.id = t.user_id
WHERE t.family_id = ?`
	args := []interface{}{familyID}
	if filters.Start != nil {
		baseQuery += " AND t.occurred_at >= ?"
		args = append(args, filters.Start.UTC())
	}
	if filters.End != nil {
		baseQuery += " AND t.occurred_at <= ?"
		args = append(args, filters.End.UTC())
	}
	if trimmed := strings.TrimSpace(filters.Type); trimmed != "" {
		baseQuery += " AND LOWER(t.type) = ?"
		args = append(args, strings.ToLower(trimmed))
	}
	if trimmed := strings.TrimSpace(filters.CategoryID); trimmed != "" {
		baseQuery += " AND t.category_id = ?"
		args = append(args, trimmed)
	}
	if trimmed := strings.TrimSpace(filters.AccountID); trimmed != "" {
		baseQuery += " AND t.account_id = ?"
		args = append(args, trimmed)
	}
	if trimmed := strings.TrimSpace(filters.UserID); trimmed != "" {
		baseQuery += " AND t.user_id = ?"
		args = append(args, trimmed)
	}
	baseQuery += " ORDER BY t.occurred_at DESC"

	rows, err := s.db.QueryContext(ctx, baseQuery, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var txns []domain.TransactionWithAuthor
	for rows.Next() {
		var txn domain.TransactionWithAuthor
		var comment sql.NullString
		if err := rows.Scan(&txn.ID, &txn.FamilyID, &txn.UserID, &txn.AccountID, &txn.CategoryID, &txn.Type, &txn.AmountMinor, &txn.Currency, &comment, &txn.OccurredAt, &txn.CreatedAt, &txn.UpdatedAt,
			&txn.Author.ID, &txn.Author.Name, &txn.Author.Email, &txn.Author.Role); err != nil {
			return nil, err
		}
		if comment.Valid {
			txn.Comment = comment.String
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
