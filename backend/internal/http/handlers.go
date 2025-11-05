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
	FamilyID   string `json:"family_id"`
}

type RegisterResponse struct {
	User       domain.User           `json:"user"`
	Family     domain.Family         `json:"family"`
	Categories []domain.Category     `json:"categories"`
	Accounts   []domain.Account      `json:"accounts"`
	Members    []domain.FamilyMember `json:"members"`
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
	AccountID   string `json:"account_id"`
	CategoryID  string `json:"category_id"`
	Type        string `json:"type"`
	AmountMinor int64  `json:"amount_minor"`
	Currency    string `json:"currency"`
	Comment     string `json:"comment"`
	OccurredAt  string `json:"occurred_at"`
}

type transactionResponse struct {
	Transaction domain.TransactionWithAuthor `json:"transaction"`
}

type AccountRequest struct {
	Name                string `json:"name"`
	Type                string `json:"type"`
	Currency            string `json:"currency"`
	InitialBalanceMinor int64  `json:"initial_balance_minor"`
	Shared              *bool  `json:"shared"`
}

type accountResponse struct {
	Account domain.Account `json:"account"`
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

	var family *domain.Family
	var err error
	creatingNewFamily := strings.TrimSpace(req.FamilyID) == ""

	if creatingNewFamily {
		familyName := req.FamilyName
		if strings.TrimSpace(familyName) == "" {
			familyName = req.Name + " family"
		}

		family, err = h.store.CreateFamily(c.Request().Context(), familyName, strings.ToUpper(req.Currency))
		if err != nil {
			return err
		}
	} else {
		family, err = h.store.GetFamily(c.Request().Context(), strings.TrimSpace(req.FamilyID))
		if err != nil {
			return err
		}
		if family == nil {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "family not found"})
		}
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
	if !creatingNewFamily {
		user.Role = "adult"
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return err
	}

	if err := h.store.CreateUser(c.Request().Context(), user, string(hash)); err != nil {
		return err
	}

	if creatingNewFamily {
		if err := h.bootstrapCategories(c.Request().Context(), family.ID); err != nil {
			return err
		}

		if err := h.bootstrapAccounts(c.Request().Context(), family.ID, strings.ToUpper(req.Currency)); err != nil {
			return err
		}
	}

	categories, err := h.store.ListCategoriesByFamily(c.Request().Context(), family.ID)
	if err != nil {
		return err
	}

	accounts, err := h.store.ListAccountsByFamily(c.Request().Context(), family.ID)
	if err != nil {
		return err
	}

	members, err := h.store.ListFamilyMembers(c.Request().Context(), family.ID)
	if err != nil {
		return err
	}

	return c.JSON(http.StatusCreated, RegisterResponse{User: *user, Family: *family, Categories: categories, Accounts: accounts, Members: members})
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

func (h *Handlers) ListAccounts(c echo.Context) error {
	userID := c.Param("id")
	user, err := h.store.GetUser(c.Request().Context(), userID)
	if err != nil {
		return err
	}
	if user == nil {
		return c.JSON(http.StatusNotFound, map[string]string{"error": "user not found"})
	}
	accounts, err := h.store.ListAccountsByFamily(c.Request().Context(), user.FamilyID)
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, map[string]interface{}{"accounts": accounts})
}

func (h *Handlers) ListMembers(c echo.Context) error {
	userID := c.Param("id")
	user, err := h.store.GetUser(c.Request().Context(), userID)
	if err != nil {
		return err
	}
	if user == nil {
		return c.JSON(http.StatusNotFound, map[string]string{"error": "user not found"})
	}
	members, err := h.store.ListFamilyMembers(c.Request().Context(), user.FamilyID)
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, map[string]interface{}{"members": members})
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

func (h *Handlers) CreateAccount(c echo.Context) error {
	userID := c.Param("id")
	user, err := h.store.GetUser(c.Request().Context(), userID)
	if err != nil {
		return err
	}
	if user == nil {
		return c.JSON(http.StatusNotFound, map[string]string{"error": "user not found"})
	}

	var req AccountRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid payload"})
	}

	sanitizeAccountRequest(&req, user.CurrencyDefault)
	if err := validateAccountPayload(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": err.Error()})
	}

	now := time.Now().UTC()
	account := &domain.Account{
		ID:           uuid.NewString(),
		FamilyID:     user.FamilyID,
		Name:         req.Name,
		Type:         req.Type,
		Currency:     req.Currency,
		BalanceMinor: req.InitialBalanceMinor,
		IsShared:     true,
		IsArchived:   false,
		CreatedAt:    now,
		UpdatedAt:    now,
	}
	if req.Shared != nil {
		account.IsShared = *req.Shared
	}

	if err := h.store.CreateAccount(c.Request().Context(), account); err != nil {
		return err
	}

	return c.JSON(http.StatusCreated, accountResponse{Account: *account})
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
	if req.UserID == "" || req.AccountID == "" || req.CategoryID == "" || req.Type == "" || req.AmountMinor == 0 || req.OccurredAt == "" {
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

	account, err := h.store.GetAccount(c.Request().Context(), req.AccountID)
	if err != nil {
		return err
	}
	if account == nil || account.FamilyID != user.FamilyID {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "account not found"})
	}
	if account.IsArchived {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "account is archived"})
	}

	currency := strings.ToUpper(strings.TrimSpace(req.Currency))
	if currency == "" {
		currency = account.Currency
	}
	if currency != account.Currency {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "currency must match account currency"})
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
		AccountID:   account.ID,
		CategoryID:  category.ID,
		Type:        req.Type,
		AmountMinor: req.AmountMinor,
		Currency:    currency,
		Comment:     strings.TrimSpace(req.Comment),
		OccurredAt:  occurredAt.UTC(),
		CreatedAt:   now,
		UpdatedAt:   now,
	}

	if err := h.store.CreateTransaction(c.Request().Context(), txn); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "account not found"})
		}
		if errors.Is(err, store.ErrAccountArchived) {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "account is archived"})
		}
		return err
	}

	return c.JSON(http.StatusCreated, transactionResponse{Transaction: domain.TransactionWithAuthor{Transaction: *txn, Author: domain.FamilyMember{ID: user.ID, Name: user.Name, Email: user.Email, Role: user.Role}}})
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

	startDate, err := parseOptionalTime(c.QueryParam("start_date"))
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "start_date must be RFC3339"})
	}
	endDate, err := parseOptionalTime(c.QueryParam("end_date"))
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "end_date must be RFC3339"})
	}
	if startDate != nil && endDate != nil && startDate.After(*endDate) {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "start_date must be before end_date"})
	}

	txnType := strings.TrimSpace(strings.ToLower(c.QueryParam("type")))
	if txnType != "" && txnType != "income" && txnType != "expense" {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "type must be income or expense"})
	}

	categoryID := strings.TrimSpace(c.QueryParam("category_id"))
	if categoryID != "" {
		category, err := h.store.GetCategory(c.Request().Context(), categoryID)
		if err != nil {
			return err
		}
		if category == nil || category.FamilyID != user.FamilyID {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "category not found"})
		}
	}

	accountID := strings.TrimSpace(c.QueryParam("account_id"))
	if accountID != "" {
		account, err := h.store.GetAccount(c.Request().Context(), accountID)
		if err != nil {
			return err
		}
		if account == nil || account.FamilyID != user.FamilyID {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "account not found"})
		}
	}

	memberFilter := strings.TrimSpace(c.QueryParam("user_id"))
	if memberFilter != "" {
		member, err := h.store.GetUser(c.Request().Context(), memberFilter)
		if err != nil {
			return err
		}
		if member == nil || member.FamilyID != user.FamilyID {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "user not found"})
		}
	}

	filters := store.TransactionListFilters{
		Start:      startDate,
		End:        endDate,
		Type:       txnType,
		CategoryID: categoryID,
		AccountID:  accountID,
		UserID:     memberFilter,
	}

	txns, err := h.store.ListTransactionsByFamily(c.Request().Context(), user.FamilyID, filters)
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, map[string]interface{}{"transactions": txns})
}

func parseOptionalTime(value string) (*time.Time, error) {
	if strings.TrimSpace(value) == "" {
		return nil, nil
	}
	parsed, err := time.Parse(time.RFC3339, value)
	if err != nil {
		return nil, err
	}
	t := parsed.UTC()
	return &t, nil
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

func (h *Handlers) bootstrapAccounts(ctx context.Context, familyID, currency string) error {
	existing, err := h.store.ListAccountsByFamily(ctx, familyID)
	if err != nil {
		return err
	}
	if len(existing) > 0 {
		return nil
	}

	now := time.Now().UTC()
	defaults := []struct {
		name    string
		accType string
	}{
		{name: "Наличные", accType: "cash"},
		{name: "Основная карта", accType: "card"},
	}

	for _, base := range defaults {
		account := &domain.Account{
			ID:           uuid.NewString(),
			FamilyID:     familyID,
			Name:         base.name,
			Type:         base.accType,
			Currency:     currency,
			BalanceMinor: 0,
			IsShared:     true,
			IsArchived:   false,
			CreatedAt:    now,
			UpdatedAt:    now,
		}
		if err := h.store.CreateAccount(ctx, account); err != nil {
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

var allowedAccountTypes = map[string]struct{}{
	"cash":    {},
	"card":    {},
	"bank":    {},
	"deposit": {},
	"wallet":  {},
}

func sanitizeAccountRequest(req *AccountRequest, fallbackCurrency string) {
	req.Name = strings.TrimSpace(req.Name)
	req.Type = normalizeAccountType(req.Type)
	currency := strings.TrimSpace(req.Currency)
	if currency == "" {
		currency = strings.TrimSpace(fallbackCurrency)
	}
	req.Currency = strings.ToUpper(currency)
}

func normalizeAccountType(value string) string {
	t := strings.ToLower(strings.TrimSpace(value))
	if _, ok := allowedAccountTypes[t]; ok {
		return t
	}
	return "cash"
}

func validateAccountPayload(req *AccountRequest) error {
	if req.Name == "" {
		return errors.New("name is required")
	}
	if _, ok := allowedAccountTypes[req.Type]; !ok {
		return errors.New("type must be one of cash, card, bank, deposit, wallet")
	}
	if strings.TrimSpace(req.Currency) == "" {
		return errors.New("currency is required")
	}
	return nil
}
