package http

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
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
	errUserNotFound   = errors.New("user not found")
	errFamilyMismatch = errors.New("family mismatch")
)

type accessScope struct {
	Mode       string `json:"mode"`
	FamilyID   string `json:"family_id"`
	FamilyName string `json:"family_name"`
	Message    string `json:"message"`
}

func buildFamilyScope(family *domain.Family) accessScope {
	return accessScope{
		Mode:       "family",
		FamilyID:   family.ID,
		FamilyName: family.Name,
		Message:    fmt.Sprintf("Вы видите только данные семьи \"%s\" (ID %s).", family.Name, family.ID),
	}
}

var supportedCurrencies = []string{"RUB", "USD", "EUR", "KZT", "BYN", "UAH", "GBP"}

const currentUserContextKey = "currentUser"

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
	Scope      accessScope           `json:"scope"`
}

type DisplaySettingsPayload struct {
	Theme                      string `json:"theme"`
	Density                    string `json:"density"`
	ShowArchived               bool   `json:"show_archived"`
	ShowTotalsInFamilyCurrency bool   `json:"show_totals_in_family_currency"`
}

type UserSettingsResponse struct {
	SupportedCurrencies []string          `json:"supported_currencies"`
	Family              familySettings    `json:"family"`
	User                userSettings      `json:"user"`
	Categories          []domain.Category `json:"categories"`
	Accounts            []domain.Account  `json:"accounts"`
}

type familySettings struct {
	ID           string `json:"id"`
	Name         string `json:"name"`
	CurrencyBase string `json:"currency_base"`
}

type userSettings struct {
	ID              string                 `json:"id"`
	Locale          string                 `json:"locale"`
	CurrencyDefault string                 `json:"currency_default"`
	Display         domain.DisplaySettings `json:"display"`
}

type UpdateUserSettingsRequest struct {
	FamilyCurrency string                 `json:"family_currency"`
	UserCurrency   string                 `json:"user_currency"`
	Locale         string                 `json:"locale"`
	Display        DisplaySettingsPayload `json:"display"`
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

type PlannedOperationRequest struct {
	AccountID   string `json:"account_id"`
	CategoryID  string `json:"category_id"`
	Type        string `json:"type"`
	Title       string `json:"title"`
	AmountMinor int64  `json:"amount_minor"`
	Currency    string `json:"currency"`
	Comment     string `json:"comment"`
	DueAt       string `json:"due_at"`
	Recurrence  string `json:"recurrence"`
}

type plannedOperationResponse struct {
	PlannedOperation domain.PlannedOperationWithCreator `json:"planned_operation"`
}

type plannedOperationsListResponse struct {
	Planned   []domain.PlannedOperationWithCreator `json:"planned_operations"`
	Completed []domain.PlannedOperationWithCreator `json:"completed_operations"`
}

type completePlannedOperationRequest struct {
	OccurredAt string `json:"occurred_at"`
}

func NewHandlers(store *store.Store) *Handlers {
	return &Handlers{store: store}
}

func (h *Handlers) RequireAuth(next echo.HandlerFunc) echo.HandlerFunc {
	return func(c echo.Context) error {
		userID := strings.TrimSpace(c.Request().Header.Get("X-User-ID"))
		if userID == "" {
			return c.JSON(http.StatusUnauthorized, map[string]string{"error": "missing X-User-ID header"})
		}

		user, err := h.store.GetUser(c.Request().Context(), userID)
		if err != nil {
			return err
		}
		if user == nil {
			return c.JSON(http.StatusUnauthorized, map[string]string{"error": "invalid user"})
		}

		c.Set(currentUserContextKey, user)
		c.Response().Header().Set("X-Family-ID", user.FamilyID)
		return next(c)
	}
}

func currentUserFromContext(c echo.Context) *domain.User {
	if value := c.Get(currentUserContextKey); value != nil {
		if user, ok := value.(*domain.User); ok {
			return user
		}
	}
	return nil
}

func (h *Handlers) resolvePathUser(c echo.Context) (*domain.User, error) {
	current := currentUserFromContext(c)
	if current == nil {
		return nil, errors.New("missing current user in context")
	}

	targetID := strings.TrimSpace(c.Param("id"))
	if targetID == "" || targetID == current.ID {
		return current, nil
	}

	user, err := h.store.GetUser(c.Request().Context(), targetID)
	if err != nil {
		return nil, err
	}
	if user == nil {
		return nil, errUserNotFound
	}
	if user.FamilyID != current.FamilyID {
		return nil, errFamilyMismatch
	}
	return user, nil
}

func (h *Handlers) handleUserAccessError(c echo.Context, err error) error {
	switch {
	case errors.Is(err, errUserNotFound):
		return c.JSON(http.StatusNotFound, map[string]string{"error": "user not found"})
	case errors.Is(err, errFamilyMismatch):
		return c.JSON(http.StatusForbidden, map[string]string{"error": "forbidden"})
	default:
		return err
	}
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
		DisplaySettings: domain.DefaultDisplaySettings(),
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

	scope := buildFamilyScope(family)

	return c.JSON(http.StatusCreated, RegisterResponse{User: *user, Family: *family, Categories: categories, Accounts: accounts, Members: members, Scope: scope})
}

func defaultLocale(locale string) string {
	if strings.TrimSpace(locale) == "" {
		return "ru-RU"
	}
	return locale
}

func (h *Handlers) GetUser(c echo.Context) error {
	user, err := h.resolvePathUser(c)
	if err != nil {
		return h.handleUserAccessError(c, err)
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

func (h *Handlers) GetAccessScope(c echo.Context) error {
	current := currentUserFromContext(c)
	if current == nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
	}

	family, err := h.store.GetFamily(c.Request().Context(), current.FamilyID)
	if err != nil {
		return err
	}
	if family == nil {
		return c.JSON(http.StatusNotFound, map[string]string{"error": "family not found"})
	}

	return c.JSON(http.StatusOK, map[string]interface{}{"scope": buildFamilyScope(family)})
}

func (h *Handlers) GetUserSettings(c echo.Context) error {
	user, err := h.resolvePathUser(c)
	if err != nil {
		return h.handleUserAccessError(c, err)
	}

	family, err := h.store.GetFamily(c.Request().Context(), user.FamilyID)
	if err != nil {
		return err
	}
	if family == nil {
		return c.JSON(http.StatusNotFound, map[string]string{"error": "family not found"})
	}
	categories, err := h.store.ListCategoriesByFamily(c.Request().Context(), family.ID)
	if err != nil {
		return err
	}
	accounts, err := h.store.ListAccountsByFamily(c.Request().Context(), family.ID)
	if err != nil {
		return err
	}

	return c.JSON(http.StatusOK, UserSettingsResponse{
		SupportedCurrencies: supportedCurrencies,
		Family: familySettings{
			ID:           family.ID,
			Name:         family.Name,
			CurrencyBase: family.CurrencyBase,
		},
		User: userSettings{
			ID:              user.ID,
			Locale:          user.Locale,
			CurrencyDefault: user.CurrencyDefault,
			Display:         user.DisplaySettings,
		},
		Categories: categories,
		Accounts:   accounts,
	})
}

func (h *Handlers) UpdateUserSettings(c echo.Context) error {
	current := currentUserFromContext(c)
	if current == nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
	}

	user, err := h.resolvePathUser(c)
	if err != nil {
		return h.handleUserAccessError(c, err)
	}

	if current.ID != user.ID {
		return c.JSON(http.StatusForbidden, map[string]string{"error": "cannot modify other members"})
	}

	var req UpdateUserSettingsRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid payload"})
	}

	family, err := h.store.GetFamily(c.Request().Context(), user.FamilyID)
	if err != nil {
		return err
	}
	if family == nil {
		return c.JSON(http.StatusNotFound, map[string]string{"error": "family not found"})
	}

	req.FamilyCurrency = strings.ToUpper(strings.TrimSpace(req.FamilyCurrency))
	req.UserCurrency = strings.ToUpper(strings.TrimSpace(req.UserCurrency))
	req.Locale = strings.TrimSpace(req.Locale)

	if req.UserCurrency == "" {
		req.UserCurrency = user.CurrencyDefault
	}
	if req.Locale == "" {
		req.Locale = user.Locale
	}

	if !isSupportedCurrency(req.UserCurrency) {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "unsupported user currency"})
	}
	if req.FamilyCurrency != "" && !isSupportedCurrency(req.FamilyCurrency) {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "unsupported family currency"})
	}

	display, err := normalizeDisplaySettings(req.Display)
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": err.Error()})
	}

	if req.FamilyCurrency != "" && req.FamilyCurrency != family.CurrencyBase {
		if current.Role != "owner" {
			return c.JSON(http.StatusForbidden, map[string]string{"error": "only owner can change family currency"})
		}
		updatedFamily, err := h.store.UpdateFamilyCurrency(c.Request().Context(), family.ID, req.FamilyCurrency)
		if err != nil {
			return err
		}
		family = updatedFamily
	}

	updatedUser, err := h.store.UpdateUserSettings(c.Request().Context(), user.ID, req.Locale, req.UserCurrency, display)
	if err != nil {
		return err
	}

	categories, err := h.store.ListCategoriesByFamily(c.Request().Context(), family.ID)
	if err != nil {
		return err
	}
	accounts, err := h.store.ListAccountsByFamily(c.Request().Context(), family.ID)
	if err != nil {
		return err
	}

	return c.JSON(http.StatusOK, UserSettingsResponse{
		SupportedCurrencies: supportedCurrencies,
		Family: familySettings{
			ID:           family.ID,
			Name:         family.Name,
			CurrencyBase: family.CurrencyBase,
		},
		User: userSettings{
			ID:              updatedUser.ID,
			Locale:          updatedUser.Locale,
			CurrencyDefault: updatedUser.CurrencyDefault,
			Display:         updatedUser.DisplaySettings,
		},
		Categories: categories,
		Accounts:   accounts,
	})
}

func normalizeDisplaySettings(payload DisplaySettingsPayload) (domain.DisplaySettings, error) {
	theme := strings.ToLower(strings.TrimSpace(payload.Theme))
	if theme == "" {
		theme = "system"
	}
	switch theme {
	case "system", "light", "dark":
	default:
		return domain.DisplaySettings{}, fmt.Errorf("unknown theme %s", payload.Theme)
	}

	density := strings.ToLower(strings.TrimSpace(payload.Density))
	if density == "" {
		density = "comfortable"
	}
	switch density {
	case "comfortable", "compact":
	default:
		return domain.DisplaySettings{}, fmt.Errorf("unknown density %s", payload.Density)
	}

	return domain.DisplaySettings{
		Theme:                      theme,
		Density:                    density,
		ShowArchived:               payload.ShowArchived,
		ShowTotalsInFamilyCurrency: payload.ShowTotalsInFamilyCurrency,
	}, nil
}

func isSupportedCurrency(code string) bool {
	code = strings.ToUpper(strings.TrimSpace(code))
	if code == "" {
		return false
	}
	for _, item := range supportedCurrencies {
		if item == code {
			return true
		}
	}
	return false
}

func (h *Handlers) ListCategories(c echo.Context) error {
	user, err := h.resolvePathUser(c)
	if err != nil {
		return h.handleUserAccessError(c, err)
	}
	categories, err := h.store.ListCategoriesByFamily(c.Request().Context(), user.FamilyID)
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, map[string]interface{}{"categories": categories})
}

func (h *Handlers) ListAccounts(c echo.Context) error {
	user, err := h.resolvePathUser(c)
	if err != nil {
		return h.handleUserAccessError(c, err)
	}
	accounts, err := h.store.ListAccountsByFamily(c.Request().Context(), user.FamilyID)
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, map[string]interface{}{"accounts": accounts})
}

func (h *Handlers) ListMembers(c echo.Context) error {
	user, err := h.resolvePathUser(c)
	if err != nil {
		return h.handleUserAccessError(c, err)
	}
	members, err := h.store.ListFamilyMembers(c.Request().Context(), user.FamilyID)
	if err != nil {
		return err
	}
	return c.JSON(http.StatusOK, map[string]interface{}{"members": members})
}

func (h *Handlers) CreateCategory(c echo.Context) error {
	user, err := h.resolvePathUser(c)
	if err != nil {
		return h.handleUserAccessError(c, err)
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
	user, err := h.resolvePathUser(c)
	if err != nil {
		return h.handleUserAccessError(c, err)
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
	categoryID := c.Param("categoryId")

	user, err := h.resolvePathUser(c)
	if err != nil {
		return h.handleUserAccessError(c, err)
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
	categoryID := c.Param("categoryId")

	user, err := h.resolvePathUser(c)
	if err != nil {
		return h.handleUserAccessError(c, err)
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
	current := currentUserFromContext(c)
	if current == nil {
		return c.JSON(http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
	}

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
	if user.FamilyID != current.FamilyID {
		return c.JSON(http.StatusForbidden, map[string]string{"error": "forbidden"})
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
	user, err := h.resolvePathUser(c)
	if err != nil {
		return h.handleUserAccessError(c, err)
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

func (h *Handlers) GetReportsOverview(c echo.Context) error {
	user, err := h.resolvePathUser(c)
	if err != nil {
		return h.handleUserAccessError(c, err)
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

	reports, err := h.store.GetReportsOverview(c.Request().Context(), user.FamilyID, startDate, endDate)
	if err != nil {
		return err
	}

	return c.JSON(http.StatusOK, map[string]interface{}{"reports": reports})
}

func (h *Handlers) CreatePlannedOperation(c echo.Context) error {
	user, err := h.resolvePathUser(c)
	if err != nil {
		return h.handleUserAccessError(c, err)
	}

	var req PlannedOperationRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid payload"})
	}

	req.Title = strings.TrimSpace(req.Title)
	if req.AccountID == "" || req.CategoryID == "" || req.Type == "" || req.Title == "" || req.AmountMinor <= 0 || req.DueAt == "" {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "missing required fields"})
	}
	normalizedType := strings.ToLower(strings.TrimSpace(req.Type))
	if normalizedType != "income" && normalizedType != "expense" {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "type must be income or expense"})
	}

	recurrence, err := normalizeRecurrence(req.Recurrence)
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": err.Error()})
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
	if strings.ToLower(category.Type) != normalizedType {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "category type mismatch"})
	}

	currency := strings.ToUpper(strings.TrimSpace(req.Currency))
	if currency == "" {
		currency = account.Currency
	}
	if currency != account.Currency {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "currency must match account currency"})
	}

	dueAt, err := time.Parse(time.RFC3339, req.DueAt)
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "due_at must be RFC3339"})
	}

	now := time.Now().UTC()
	plan := &domain.PlannedOperation{
		ID:          uuid.NewString(),
		FamilyID:    user.FamilyID,
		UserID:      user.ID,
		AccountID:   account.ID,
		CategoryID:  category.ID,
		Type:        normalizedType,
		Title:       req.Title,
		AmountMinor: req.AmountMinor,
		Currency:    currency,
		Comment:     strings.TrimSpace(req.Comment),
		DueAt:       dueAt.UTC(),
		Recurrence:  recurrence,
		IsCompleted: false,
		CreatedAt:   now,
		UpdatedAt:   now,
	}

	if err := h.store.CreatePlannedOperation(c.Request().Context(), plan); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "account not found"})
		}
		if errors.Is(err, store.ErrAccountArchived) {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "account is archived"})
		}
		return err
	}

	created, err := h.store.GetPlannedOperationWithCreator(c.Request().Context(), plan.ID)
	if err != nil {
		return err
	}
	if created == nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "planned operation not found after create"})
	}

	return c.JSON(http.StatusCreated, plannedOperationResponse{PlannedOperation: *created})
}

func (h *Handlers) ListPlannedOperations(c echo.Context) error {
	user, err := h.resolvePathUser(c)
	if err != nil {
		return h.handleUserAccessError(c, err)
	}

	planned, err := h.store.ListPlannedOperationsByFamily(c.Request().Context(), user.FamilyID, store.PlannedOperationStatusPending)
	if err != nil {
		return err
	}
	completed, err := h.store.ListPlannedOperationsByFamily(c.Request().Context(), user.FamilyID, store.PlannedOperationStatusCompleted)
	if err != nil {
		return err
	}

	return c.JSON(http.StatusOK, plannedOperationsListResponse{Planned: planned, Completed: completed})
}

func (h *Handlers) CompletePlannedOperation(c echo.Context) error {
	planID := c.Param("operationId")

	actor, err := h.resolvePathUser(c)
	if err != nil {
		return h.handleUserAccessError(c, err)
	}

	plan, err := h.store.GetPlannedOperation(c.Request().Context(), planID)
	if err != nil {
		return err
	}
	if plan == nil || plan.FamilyID != actor.FamilyID {
		return c.JSON(http.StatusNotFound, map[string]string{"error": "planned operation not found"})
	}

	recurrence := strings.TrimSpace(plan.Recurrence)
	if plan.IsCompleted && recurrence == "" {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "operation already completed"})
	}

	var req completePlannedOperationRequest
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid payload"})
	}

	occurredAt := time.Now().UTC()
	if trimmed := strings.TrimSpace(req.OccurredAt); trimmed != "" {
		parsed, err := time.Parse(time.RFC3339, trimmed)
		if err != nil {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "occurred_at must be RFC3339"})
		}
		occurredAt = parsed.UTC()
	}

	account, err := h.store.GetAccount(c.Request().Context(), plan.AccountID)
	if err != nil {
		return err
	}
	if account == nil || account.FamilyID != actor.FamilyID {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "account not found"})
	}
	if account.IsArchived {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "account is archived"})
	}
	if account.Currency != plan.Currency {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "account currency changed"})
	}

	category, err := h.store.GetCategory(c.Request().Context(), plan.CategoryID)
	if err != nil {
		return err
	}
	if category == nil || category.FamilyID != actor.FamilyID {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "category not found"})
	}
	if category.IsArchived {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "category is archived"})
	}

	comment := plan.Comment
	if strings.TrimSpace(comment) == "" {
		comment = plan.Title
	}

	now := time.Now().UTC()
	txn := &domain.Transaction{
		ID:          uuid.NewString(),
		FamilyID:    plan.FamilyID,
		UserID:      actor.ID,
		AccountID:   plan.AccountID,
		CategoryID:  plan.CategoryID,
		Type:        plan.Type,
		AmountMinor: plan.AmountMinor,
		Currency:    plan.Currency,
		Comment:     comment,
		OccurredAt:  occurredAt,
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

	plan.LastCompletedAt = &now
	plan.UpdatedAt = now
	if recurrence == "" {
		plan.IsCompleted = true
	} else {
		nextDue, nextErr := advanceRecurrence(plan.DueAt, recurrence)
		if nextErr != nil {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": nextErr.Error()})
		}
		for !nextDue.After(occurredAt) {
			nextDue, nextErr = advanceRecurrence(nextDue, recurrence)
			if nextErr != nil {
				return c.JSON(http.StatusBadRequest, map[string]string{"error": nextErr.Error()})
			}
		}
		plan.DueAt = nextDue
		plan.IsCompleted = false
	}

	if err := h.store.UpdatePlannedOperationStatus(c.Request().Context(), plan); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return c.JSON(http.StatusNotFound, map[string]string{"error": "planned operation not found"})
		}
		return err
	}

	updatedPlan, err := h.store.GetPlannedOperationWithCreator(c.Request().Context(), plan.ID)
	if err != nil {
		return err
	}
	if updatedPlan == nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "planned operation not found after update"})
	}

	txnResponse := domain.TransactionWithAuthor{Transaction: *txn, Author: domain.FamilyMember{ID: actor.ID, Name: actor.Name, Email: actor.Email, Role: actor.Role}}

	return c.JSON(http.StatusOK, map[string]interface{}{"planned_operation": updatedPlan, "transaction": txnResponse})
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

func normalizeRecurrence(value string) (string, error) {
	trimmed := strings.ToLower(strings.TrimSpace(value))
	if trimmed == "" || trimmed == "none" {
		return "", nil
	}
	switch trimmed {
	case "weekly", "monthly", "yearly":
		return trimmed, nil
	default:
		return "", fmt.Errorf("recurrence must be one of weekly, monthly, yearly or none")
	}
}

func advanceRecurrence(current time.Time, recurrence string) (time.Time, error) {
	switch strings.ToLower(strings.TrimSpace(recurrence)) {
	case "weekly":
		return current.AddDate(0, 0, 7), nil
	case "monthly":
		return current.AddDate(0, 1, 0), nil
	case "yearly":
		return current.AddDate(1, 0, 0), nil
	default:
		return time.Time{}, fmt.Errorf("unknown recurrence: %s", recurrence)
	}
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
