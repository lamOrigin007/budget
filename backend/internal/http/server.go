package http

import (
	"net/http"
	"time"

	"github.com/labstack/echo/v4"
)

type Server struct {
	echo *echo.Echo
}

func New() *Server {
	e := echo.New()
	e.HideBanner = true
	e.HidePort = true
	e.HTTPErrorHandler = func(err error, c echo.Context) {
		c.Logger().Error(err)
		_ = c.JSON(http.StatusInternalServerError, map[string]string{"error": err.Error()})
	}
	e.Pre(func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			c.Response().Header().Set("Content-Type", "application/json")
			return next(c)
		}
	})
	return &Server{echo: e}
}

func (s *Server) Echo() *echo.Echo {
	return s.echo
}

func RegisterRoutes(e *echo.Echo, handlers *Handlers) {
	api := e.Group("/api/v1")
	api.POST("/users", handlers.RegisterUser)

	secured := api.Group("")
	secured.Use(handlers.RequireAuth)

	secured.GET("/users/:id", handlers.GetUser)
	secured.GET("/users/:id/settings", handlers.GetUserSettings)
	secured.PUT("/users/:id/settings", handlers.UpdateUserSettings)
	secured.GET("/users/:id/categories", handlers.ListCategories)
	secured.POST("/users/:id/categories", handlers.CreateCategory)
	secured.PUT("/users/:id/categories/:categoryId", handlers.UpdateCategory)
	secured.POST("/users/:id/categories/:categoryId/archive", handlers.ToggleCategoryArchive)
	secured.GET("/users/:id/accounts", handlers.ListAccounts)
	secured.POST("/users/:id/accounts", handlers.CreateAccount)
	secured.GET("/users/:id/members", handlers.ListMembers)
	secured.POST("/transactions", handlers.CreateTransaction)
	secured.GET("/users/:id/transactions", handlers.ListTransactions)
	secured.GET("/users/:id/reports/overview", handlers.GetReportsOverview)
	secured.GET("/users/:id/planned-operations", handlers.ListPlannedOperations)
	secured.POST("/users/:id/planned-operations", handlers.CreatePlannedOperation)
	secured.POST("/users/:id/planned-operations/:operationId/complete", handlers.CompletePlannedOperation)
}

type HealthResponse struct {
	Status    string    `json:"status"`
	Timestamp time.Time `json:"timestamp"`
}

func RegisterHealth(e *echo.Echo) {
	e.GET("/healthz", func(c echo.Context) error {
		return c.JSON(http.StatusOK, HealthResponse{Status: "ok", Timestamp: time.Now().UTC()})
	})
}
