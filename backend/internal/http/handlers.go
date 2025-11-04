package http

import (
	"context"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	"golang.org/x/crypto/bcrypt"

	"familybudget/internal/domain"
	"familybudget/internal/store"
)

type Handlers struct {
	store *store.Store
}

type RegisterRequest struct {
	Email      string `json:"email"`
	Password   string `json:"password"`
	Name       string `json:"name"`
	Locale     string `json:"locale"`
	Currency   string `json:"currency"`
	FamilyName string `json:"family_name"`
}

type RegisterResponse struct {
	User       domain.User       `json:"user"`
	Family     domain.Family     `json:"family"`
	Categories []domain.Category `json:"categories"`
}

type TransactionRequest struct {
	UserID      string `json:"user_id"`
	CategoryID  string `json:"category_id"`
	Type        string `json:"type"`
	AmountMinor int64  `json:"amount_minor"`
	Currency    string `json:"currency"`
	Description string `json:"description"`
	OccurredAt  string `json:"occurred_at"`
}

type transactionResponse struct {
	Transaction domain.Transaction `json:"transaction"`
}

func NewHandlers(store *store.Store) *Handlers {
	return &Handlers{store: store}
}

func (h *Handlers) RegisterUser(c echo.Context) error {
	var req RegisterRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid payload"})
	}
	if req.Email == "" || req.Password == "" || req.Name == "" || req.Currency == "" {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "email, password, name and currency are required"})
	}
	req.Email = strings.ToLower(strings.TrimSpace(req.Email))
	if existing, err := h.store.FindUserByEmail(c.Request().Context(), req.Email); err != nil {
		return err
	} else if existing != nil {
		return c.JSON(http.StatusConflict, map[string]string{"error": "user already exists"})
	}

	familyName := req.FamilyName
	if strings.TrimSpace(familyName) == "" {
		familyName = req.Name + " family"
	}

	family, err := h.store.CreateFamily(c.Request().Context(), familyName, strings.ToUpper(req.Currency))
	if err != nil {
		return err
	}

	now := time.Now().UTC()
	user := &domain.User{
		ID:              uuid.NewString(),
		FamilyID:        family.ID,
		Email:           req.Email,
		Name:            req.Name,
		Role:            "owner",
		Locale:          defaultLocale(req.Locale),
		CurrencyDefault: strings.ToUpper(req.Currency),
		CreatedAt:       now,
		UpdatedAt:       now,
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return err
	}

	if err := h.store.CreateUser(c.Request().Context(), user, string(hash)); err != nil {
		return err
	}

	if err := h.bootstrapCategories(c.Request().Context(), family.ID); err != nil {
		return err
	}

	categories, err := h.store.ListCategoriesByFamily(c.Request().Context(), family.ID)
	if err != nil {
		return err
	}

	return c.JSON(http.StatusCreated, RegisterResponse{User: *user, Family: *family, Categories: categories})
}

func defaultLocale(locale string) string {
	if strings.TrimSpace(locale) == "" {
		return "ru-RU"
	}
	return locale
}

func (h *Handlers) GetUser(c echo.Context) error {
	id := c.Param("id")
	user, err := h.store.GetUser(c.Request().Context(), id)
	if err != nil {
		return err
	}
	if user == nil {
		return c.JSON(http.StatusNotFound, map[string]string{"error": "user not found"})
	}
	family, err := h.store.GetFamily(c.Request().Context(), user.FamilyID)
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, map[string]interface{}{
		"user":   user,
		"family": family,
	})
}

func (h *Handlers) ListCategories(c echo.Context) error {
	userID := c.Param("id")
	user, err := h.store.GetUser(c.Request().Context(), userID)
	if err != nil {
		return err
	}
	if user == nil {
		return c.JSON(http.StatusNotFound, map[string]string{"error": "user not found"})
	}
	categories, err := h.store.ListCategoriesByFamily(c.Request().Context(), user.FamilyID)
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, map[string]interface{}{"categories": categories})
}

func (h *Handlers) CreateTransaction(c echo.Context) error {
	var req TransactionRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid payload"})
	}
	if req.UserID == "" || req.CategoryID == "" || req.Type == "" || req.AmountMinor == 0 || req.Currency == "" || req.OccurredAt == "" {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "missing required fields"})
	}
	if req.Type != "income" && req.Type != "expense" {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "type must be income or expense"})
	}

	user, err := h.store.GetUser(c.Request().Context(), req.UserID)
	if err != nil {
		return err
	}
	if user == nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "user not found"})
	}

	category, err := h.store.GetCategory(c.Request().Context(), req.CategoryID)
	if err != nil {
		return err
	}
	if category == nil || category.FamilyID != user.FamilyID {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "category not found"})
	}

	occurredAt, err := time.Parse(time.RFC3339, req.OccurredAt)
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "occurred_at must be RFC3339"})
	}

	now := time.Now().UTC()
	txn := &domain.Transaction{
		ID:          uuid.NewString(),
		FamilyID:    user.FamilyID,
		UserID:      user.ID,
		CategoryID:  category.ID,
		Type:        req.Type,
		AmountMinor: req.AmountMinor,
		Currency:    strings.ToUpper(req.Currency),
		Description: req.Description,
		OccurredAt:  occurredAt,
		CreatedAt:   now,
		UpdatedAt:   now,
	}

	if err := h.store.CreateTransaction(c.Request().Context(), txn); err != nil {
		return err
	}

	return c.JSON(http.StatusCreated, transactionResponse{Transaction: *txn})
}

func (h *Handlers) ListTransactions(c echo.Context) error {
	userID := c.Param("id")
	user, err := h.store.GetUser(c.Request().Context(), userID)
	if err != nil {
		return err
	}
	if user == nil {
		return c.JSON(http.StatusNotFound, map[string]string{"error": "user not found"})
	}

	txns, err := h.store.ListTransactionsByUser(c.Request().Context(), userID)
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, map[string]interface{}{"transactions": txns})
}

func (h *Handlers) bootstrapCategories(ctx context.Context, familyID string) error {
	defaults := []domain.Category{
		{Name: "Зарплата", Type: "income", Color: "#22c55e"},
		{Name: "Подработка", Type: "income", Color: "#16a34a"},
		{Name: "Продукты", Type: "expense", Color: "#ef4444"},
		{Name: "Транспорт", Type: "expense", Color: "#f97316"},
		{Name: "Досуг", Type: "expense", Color: "#6366f1"},
	}

	existing, err := h.store.ListCategoriesByFamily(ctx, familyID)
	if err != nil {
		return err
	}
	if len(existing) > 0 {
		return nil
	}

	now := time.Now().UTC()
	for _, base := range defaults {
		cat := base
		cat.ID = uuid.NewString()
		cat.FamilyID = familyID
		cat.IsSystem = true
		cat.CreatedAt = now
		if err := h.store.CreateCategory(ctx, &cat); err != nil {
			return err
		}
	}
	return nil
}
