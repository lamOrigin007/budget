package http

import (
	"context"
	"database/sql"
	"errors"
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

var (
	errParentNotFound = errors.New("parent category not found")
	errParentArchived = errors.New("parent category is archived")
)

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

type CategoryRequest struct {
	Name        string  `json:"name"`
	Type        string  `json:"type"`
	Color       string  `json:"color"`
	Description string  `json:"description"`
	ParentID    *string `json:"parent_id"`
}

type archiveCategoryRequest struct {
	Archived bool `json:"archived"`
}

type categoryResponse struct {
	Category domain.Category `json:"category"`
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

func (h *Handlers) CreateCategory(c echo.Context) error {
	userID := c.Param("id")
	user, err := h.store.GetUser(c.Request().Context(), userID)
	if err != nil {
		return err
	}
	if user == nil {
		return c.JSON(http.StatusNotFound, map[string]string{"error": "user not found"})
	}

	var req CategoryRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid payload"})
	}
	normalizeParent(&req)
	if err := validateCategoryPayload(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": err.Error()})
	}

	now := time.Now().UTC()
	category := &domain.Category{
		ID:          uuid.NewString(),
		FamilyID:    user.FamilyID,
		ParentID:    req.ParentID,
		Name:        strings.TrimSpace(req.Name),
		Type:        strings.ToLower(strings.TrimSpace(req.Type)),
		Color:       normalizeHexColor(req.Color),
		Description: strings.TrimSpace(req.Description),
		IsSystem:    false,
		IsArchived:  false,
		CreatedAt:   now,
		UpdatedAt:   now,
	}

	if category.ParentID != nil {
		if err := h.ensureParentCategory(c.Request().Context(), user.FamilyID, *category.ParentID); err != nil {
			if errors.Is(err, errParentNotFound) {
				return c.JSON(http.StatusBadRequest, map[string]string{"error": "parent category not found"})
			}
			if errors.Is(err, errParentArchived) {
				return c.JSON(http.StatusBadRequest, map[string]string{"error": "parent category is archived"})
			}
			return err
		}
	}

	if err := h.store.CreateCategory(c.Request().Context(), category); err != nil {
		return err
	}
	return c.JSON(http.StatusCreated, categoryResponse{Category: *category})
}

func (h *Handlers) UpdateCategory(c echo.Context) error {
	userID := c.Param("id")
	categoryID := c.Param("categoryId")

	user, err := h.store.GetUser(c.Request().Context(), userID)
	if err != nil {
		return err
	}
	if user == nil {
		return c.JSON(http.StatusNotFound, map[string]string{"error": "user not found"})
	}

	category, err := h.store.GetCategory(c.Request().Context(), categoryID)
	if err != nil {
		return err
	}
	if category == nil || category.FamilyID != user.FamilyID {
		return c.JSON(http.StatusNotFound, map[string]string{"error": "category not found"})
	}

	var req CategoryRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid payload"})
	}
	normalizeParent(&req)
	if err := validateCategoryPayload(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": err.Error()})
	}

	if req.ParentID != nil {
		if err := h.ensureParentCategory(c.Request().Context(), user.FamilyID, *req.ParentID); err != nil {
			if errors.Is(err, errParentNotFound) {
				return c.JSON(http.StatusBadRequest, map[string]string{"error": "parent category not found"})
			}
			if errors.Is(err, errParentArchived) {
				return c.JSON(http.StatusBadRequest, map[string]string{"error": "parent category is archived"})
			}
			return err
		}
	}

	category.Name = strings.TrimSpace(req.Name)
	category.Type = strings.ToLower(strings.TrimSpace(req.Type))
	category.Color = normalizeHexColor(req.Color)
	category.Description = strings.TrimSpace(req.Description)
	category.ParentID = req.ParentID
	category.UpdatedAt = time.Now().UTC()

	if err := h.store.UpdateCategory(c.Request().Context(), category); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return c.JSON(http.StatusNotFound, map[string]string{"error": "category not found"})
		}
		return err
	}

	updated, err := h.store.GetCategory(c.Request().Context(), categoryID)
	if err != nil {
		return err
	}
	if updated == nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "category not found after update"})
	}
	return c.JSON(http.StatusOK, categoryResponse{Category: *updated})
}

func (h *Handlers) ToggleCategoryArchive(c echo.Context) error {
	userID := c.Param("id")
	categoryID := c.Param("categoryId")

	user, err := h.store.GetUser(c.Request().Context(), userID)
	if err != nil {
		return err
	}
	if user == nil {
		return c.JSON(http.StatusNotFound, map[string]string{"error": "user not found"})
	}

	category, err := h.store.GetCategory(c.Request().Context(), categoryID)
	if err != nil {
		return err
	}
	if category == nil || category.FamilyID != user.FamilyID {
		return c.JSON(http.StatusNotFound, map[string]string{"error": "category not found"})
	}

	var req archiveCategoryRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid payload"})
	}

	if err := h.store.SetCategoryArchived(c.Request().Context(), categoryID, user.FamilyID, req.Archived, time.Now().UTC()); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return c.JSON(http.StatusNotFound, map[string]string{"error": "category not found"})
		}
		return err
	}

	updated, err := h.store.GetCategory(c.Request().Context(), categoryID)
	if err != nil {
		return err
	}
	if updated == nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "category not found after update"})
	}

	return c.JSON(http.StatusOK, categoryResponse{Category: *updated})
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
	if category.IsArchived {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "category is archived"})
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
		{Name: "Базовый доход семьи", Type: "income", Color: "#22c55e", Description: "Регулярные поступления (зарплаты, стипендии)"},
		{Name: "Дополнительный доход", Type: "income", Color: "#16a34a", Description: "Подработка, подарки, возврат долгов"},
		{Name: "Продуктовая корзина", Type: "expense", Color: "#ef4444", Description: "Ежедневные траты на питание семьи"},
		{Name: "Транспорт и перемещения", Type: "expense", Color: "#f97316", Description: "Проездные, такси, обслуживание авто"},
		{Name: "Досуг и семейные активности", Type: "expense", Color: "#6366f1", Description: "Развлечения, путешествия, мероприятия"},
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
		cat.UpdatedAt = now
		if err := h.store.CreateCategory(ctx, &cat); err != nil {
			return err
		}
	}
	return nil
}

func validateCategoryPayload(req *CategoryRequest) error {
	if strings.TrimSpace(req.Name) == "" {
		return errors.New("name is required")
	}
	switch strings.ToLower(strings.TrimSpace(req.Type)) {
	case "income", "expense", "transfer":
	default:
		return errors.New("type must be income, expense or transfer")
	}
	if strings.TrimSpace(req.Color) == "" {
		return errors.New("color is required")
	}
	return nil
}

func normalizeParent(req *CategoryRequest) {
	if req.ParentID == nil {
		return
	}
	trimmed := strings.TrimSpace(*req.ParentID)
	if trimmed == "" {
		req.ParentID = nil
		return
	}
	parentID := trimmed
	req.ParentID = &parentID
}

func (h *Handlers) ensureParentCategory(ctx context.Context, familyID, parentID string) error {
	parent, err := h.store.GetCategory(ctx, parentID)
	if err != nil {
		return err
	}
	if parent == nil || parent.FamilyID != familyID {
		return errParentNotFound
	}
	if parent.IsArchived {
		return errParentArchived
	}
	return nil
}

func normalizeHexColor(color string) string {
	normalized := strings.TrimSpace(color)
	if normalized == "" {
		return "#0ea5e9"
	}
	if !strings.HasPrefix(normalized, "#") {
		normalized = "#" + normalized
	}
	if len(normalized) == 4 {
		// expand short hex like #abc to #aabbcc
		r := normalized[1:2]
		g := normalized[2:3]
		b := normalized[3:4]
		normalized = "#" + r + r + g + g + b + b
	}
	return strings.ToLower(normalized)
}
