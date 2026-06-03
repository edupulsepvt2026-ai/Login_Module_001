// Package router wires HTTP routes declared in routes.toml to their
// handler functions using only the standard library's net/http ServeMux.
package router

import (
	"database/sql"
	"encoding/json"
	"net/http"

	"github.com/jackc/pgx/v5/pgxpool"
	authhandler "loginmodule_99/handlers/auth"
	"loginmodule_99/tomlloader"
	"loginmodule_99/util"
)

// New creates a *http.ServeMux with all routes from the config registered.
// Unknown handler names fall back to a 501 Not Implemented response.
func New(routes []tomlloader.RouteEntry, log *util.Logger, db *sql.DB, pg *pgxpool.Pool) *http.ServeMux {
	mux := http.NewServeMux()

	for _, r := range routes {
		handler := resolve(r.Handler, log, db, pg)
		pattern := r.Method + " " + r.Path
		mux.HandleFunc(pattern, handler)
		log.Info("route registered: %-6s %s → %s", r.Method, r.Path, r.Handler)
	}

	return mux
}

// registry maps handler names to their constructor functions.
// mssqlHandlers use the legacy MSSQL pool; pgHandlers use the master Postgres pool.
var mssqlHandlers = map[string]func(*util.Logger, *sql.DB) http.HandlerFunc{
	"HealthHandler":     healthHandler,
	"GetUsersHandler":   getUsersHandler,
	"CreateUserHandler": createUserHandler,
	"LoginHandler":      loginHandler,
}

var pgHandlers = map[string]func(*util.Logger, *pgxpool.Pool) http.HandlerFunc{
	"InviteVerifyHandler": authhandler.InviteVerify,
}

// resolve maps a handler name string to an actual http.HandlerFunc.
func resolve(name string, log *util.Logger, db *sql.DB, pg *pgxpool.Pool) http.HandlerFunc {
	if fn, ok := pgHandlers[name]; ok {
		return fn(log, pg)
	}
	if fn, ok := mssqlHandlers[name]; ok {
		return fn(log, db)
	}
	log.Warn("no handler found for %q, using 501 stub", name)
	return func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "not implemented: "+name, http.StatusNotImplemented)
	}
}

// ── handlers ─────────────────────────────────────────────────────────────────

func healthHandler(log *util.Logger, db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		log.Info("health check from %s", r.RemoteAddr)
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	}
}

func getUsersHandler(log *util.Logger, db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		log.Info("get users request")
		if db != nil {
			// Example: use the shared pool here.
			// rows, err := db.QueryContext(r.Context(), "SELECT id, name FROM users")
			// handle rows and convert to JSON.
		}

		writeJSON(w, http.StatusOK, []map[string]any{
			{"id": 1, "name": "Alice"},
			{"id": 2, "name": "Bob"},
		})
	}
}

func createUserHandler(log *util.Logger, db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		log.Info("create user request")
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			http.Error(w, "bad request", http.StatusBadRequest)
			return
		}
		if db != nil {
			// Example: insert user row with db.ExecContext.
		}
		writeJSON(w, http.StatusCreated, map[string]string{"result": "created"})
	}
}

type loginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

type loginResponse struct {
	Status  string `json:"status"`
	Message string `json:"message"`
	Token   string `json:"token,omitempty"`
}

func loginHandler(log *util.Logger, db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		log.Info("login authentication request from %s", r.RemoteAddr)

		if r.Method != http.MethodPost {
			log.Warn("invalid method %s for login", r.Method)
			writeJSON(w, http.StatusMethodNotAllowed, loginResponse{
				Status:  "error",
				Message: "Method not allowed. Use POST.",
			})
			return
		}

		var req loginRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			log.Warn("failed to decode login payload: %v", err)
			writeJSON(w, http.StatusBadRequest, loginResponse{
				Status:  "error",
				Message: "Invalid request payload. Must be valid JSON.",
			})
			return
		}

		if req.Username == "" || req.Password == "" {
			log.Warn("missing username or password in payload")
			writeJSON(w, http.StatusBadRequest, loginResponse{
				Status:  "error",
				Message: "Username and password are required.",
			})
			return
		}

		// Simple/mock authentication for development
		if req.Username == "admin" && req.Password == "admin123" {
			log.Info("successful login for user: %s", req.Username)
			writeJSON(w, http.StatusOK, loginResponse{
				Status:  "success",
				Message: "Authentication successful",
				Token:   "dummy-jwt-token-xyz",
			})
			return
		}

		log.Warn("failed authentication attempt for user: %s", req.Username)
		writeJSON(w, http.StatusUnauthorized, loginResponse{
			Status:  "error",
			Message: "Invalid username or password",
		})
	}
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
