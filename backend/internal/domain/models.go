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

type PlannedOperation struct {
	ID              string     `json:"id"`
	FamilyID        string     `json:"family_id"`
	UserID          string     `json:"user_id"`
	AccountID       string     `json:"account_id"`
	CategoryID      string     `json:"category_id"`
	Type            string     `json:"type"`
	Title           string     `json:"title"`
	AmountMinor     int64      `json:"amount_minor"`
	Currency        string     `json:"currency"`
	Comment         string     `json:"comment,omitempty"`
	DueAt           time.Time  `json:"due_at"`
	Recurrence      string     `json:"recurrence,omitempty"`
	IsCompleted     bool       `json:"is_completed"`
	LastCompletedAt *time.Time `json:"last_completed_at,omitempty"`
	CreatedAt       time.Time  `json:"created_at"`
	UpdatedAt       time.Time  `json:"updated_at"`
}

type PlannedOperationWithCreator struct {
	PlannedOperation
	Creator FamilyMember `json:"creator"`
}

type ReportPeriod struct {
	Start *time.Time `json:"start_date,omitempty"`
	End   *time.Time `json:"end_date,omitempty"`
}

type CurrencyAmount struct {
	Currency    string `json:"currency"`
	AmountMinor int64  `json:"amount_minor"`
}

type CategoryReportItem struct {
	CategoryID    string `json:"category_id"`
	CategoryName  string `json:"category_name"`
	CategoryColor string `json:"category_color"`
	Currency      string `json:"currency"`
	AmountMinor   int64  `json:"amount_minor"`
}

type MovementReport struct {
	Totals     []CurrencyAmount     `json:"totals"`
	ByCategory []CategoryReportItem `json:"by_category"`
}

type AccountBalanceReport struct {
	AccountID    string `json:"account_id"`
	AccountName  string `json:"account_name"`
	AccountType  string `json:"account_type"`
	Currency     string `json:"currency"`
	BalanceMinor int64  `json:"balance_minor"`
	IsShared     bool   `json:"is_shared"`
	IsArchived   bool   `json:"is_archived"`
}

type ReportsOverview struct {
	Period          ReportPeriod           `json:"period"`
	Expenses        MovementReport         `json:"expenses"`
	Incomes         MovementReport         `json:"incomes"`
	AccountBalances []AccountBalanceReport `json:"account_balances"`
}
