package main

import (
	"log"
	"os"

	httpTransport "familybudget/internal/http"
	"familybudget/internal/store"
)

func main() {
	dbPath := os.Getenv("BUDGET_DB")
	if dbPath == "" {
		dbPath = "family_budget.db"
	}

	db, err := store.OpenSQLite(dbPath)
	if err != nil {
		log.Fatalf("failed to open database: %v", err)
	}
	defer db.Close()

	st := store.New(db)

	server := httpTransport.New()
	handlers := httpTransport.NewHandlers(st)
	httpTransport.RegisterHealth(server.Echo())
	httpTransport.RegisterRoutes(server.Echo(), handlers)

	addr := ":8080"
	if env := os.Getenv("BUDGET_HTTP_ADDR"); env != "" {
		addr = env
	}

	if err := server.Echo().Start(addr); err != nil {
		log.Fatalf("server error: %v", err)
	}
}
