package domain

import "time"

type Family struct {
	ID           string    `json:"id"`
	Name         string    `json:"name"`
	CurrencyBase string    `json:"currency_base"`
	CreatedAt    time.Time `json:"created_at"`
}

type FamilyMember struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Email string `json:"email"`
	Role  string `json:"role"`
}

type User struct {
	ID              string    `json:"id"`
	FamilyID        string    `json:"family_id"`
	Email           string    `json:"email"`
	Name            string    `json:"name"`
	Role            string    `json:"role"`
	Locale          string    `json:"locale"`
	CurrencyDefault string    `json:"currency_default"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
}

type Account struct {
	ID           string    `json:"id"`
	FamilyID     string    `json:"family_id"`
	Name         string    `json:"name"`
	Type         string    `json:"type"`
	Currency     string    `json:"currency"`
	BalanceMinor int64     `json:"balance_minor"`
	IsShared     bool      `json:"is_shared"`
	IsArchived   bool      `json:"is_archived"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

type Category struct {
	ID          string    `json:"id"`
	FamilyID    string    `json:"family_id"`
	ParentID    *string   `json:"parent_id,omitempty"`
	Name        string    `json:"name"`
	Type        string    `json:"type"`
	Color       string    `json:"color"`
	IsSystem    bool      `json:"is_system"`
	Description string    `json:"description"`
	IsArchived  bool      `json:"is_archived"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

type TransactionWithAuthor struct {
	Transaction
	Author FamilyMember `json:"author"`
}

type Transaction struct {
	ID          string    `json:"id"`
	FamilyID    string    `json:"family_id"`
	UserID      string    `json:"user_id"`
	AccountID   string    `json:"account_id"`
	CategoryID  string    `json:"category_id"`
	Type        string    `json:"type"`
	AmountMinor int64     `json:"amount_minor"`
	Currency    string    `json:"currency"`
	Comment     string    `json:"comment,omitempty"`
	OccurredAt  time.Time `json:"occurred_at"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}
