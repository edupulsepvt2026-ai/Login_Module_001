// Package router wires HTTP routes declared in routes.toml to their
// handler functions using a lightweight custom router that supports
// HTTP method + path patterns and path parameters.
package router

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"strings"

	authhandler "loginmodule_99/handlers/auth"
	"loginmodule_99/tomlloader"
	"loginmodule_99/util"

	"github.com/jackc/pgx/v5/pgxpool"
)

type contextKey string

const pathParamsContextKey contextKey = "pathParams"

type routeEntry struct {
	method   string
	segments []string
	handler  http.HandlerFunc
}

type Router struct {
	routes []routeEntry
	log    *util.Logger
}

// New creates a custom router from routes.toml.
func New(routes []tomlloader.RouteEntry, log *util.Logger, db *sql.DB, pg *pgxpool.Pool) http.Handler {
	router := &Router{log: log}

	for _, r := range routes {
		handler := resolve(r.Handler, log, db, pg)
		router.routes = append(router.routes, routeEntry{
			method:   strings.ToUpper(strings.TrimSpace(r.Method)),
			segments: splitSegments(r.Path),
			handler:  handler,
		})
		log.Info("route registered: %-6s %s → %s", r.Method, r.Path, r.Handler)
	}

	return router
}

func (r *Router) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	pathSegments := splitSegments(req.URL.Path)
	method := req.Method
	var pathMatched bool

	for _, route := range r.routes {
		params, ok := matchRoute(route.segments, pathSegments)
		if !ok {
			continue
		}

		pathMatched = true
		if route.method != method {
			http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
			return
		}

		if len(params) > 0 {
			req = WithPathParams(req, params)
		}

		route.handler(w, req)
		return
	}

	if pathMatched {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}

	http.NotFound(w, req)
}

func splitSegments(path string) []string {
	trimmed := strings.Trim(path, "/")
	if trimmed == "" {
		return []string{}
	}
	return strings.Split(trimmed, "/")
}

func matchRoute(pattern, actual []string) (map[string]string, bool) {
	if len(pattern) != len(actual) {
		return nil, false
	}

	params := map[string]string{}
	for i, segment := range pattern {
		if strings.HasPrefix(segment, "{") && strings.HasSuffix(segment, "}") {
			key := segment[1 : len(segment)-1]
			params[key] = actual[i]
			continue
		}

		if segment != actual[i] {
			return nil, false
		}
	}

	return params, true
}

func WithPathParams(r *http.Request, params map[string]string) *http.Request {
	return r.WithContext(context.WithValue(r.Context(), util.PathParamsKey, params))
}

func PathValue(r *http.Request, key string) string {
	return util.PathParam(r, key)
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
	"InviteVerifyHandler":          authhandler.InviteVerify,
	"SendOTPHandler":               authhandler.SendOTP,
	"SendEmailVerificationHandler": authhandler.SendEmailVerification,
	"VerifyOTPHandler":             authhandler.VerifyOTPWithSession,
	"VerifyEmailHandler":           authhandler.VerifyEmailWithSession,
	"RegisterChainAdminHandler":    authhandler.RegisterChainAdmin,
	"LoginChainAdminHandler":       authhandler.LoginChainAdmin,
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
