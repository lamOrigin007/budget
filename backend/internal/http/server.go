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
	api.GET("/users/:id", handlers.GetUser)
	api.GET("/users/:id/categories", handlers.ListCategories)
	api.POST("/users/:id/categories", handlers.CreateCategory)
	api.PUT("/users/:id/categories/:categoryId", handlers.UpdateCategory)
	api.POST("/users/:id/categories/:categoryId/archive", handlers.ToggleCategoryArchive)
	api.POST("/transactions", handlers.CreateTransaction)
	api.GET("/users/:id/transactions", handlers.ListTransactions)
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
