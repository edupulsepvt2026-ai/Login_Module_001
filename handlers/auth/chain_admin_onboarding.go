package auth

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"regexp"
	"strings"
	"time"

	"loginmodule_99/db"
	"loginmodule_99/response"
	"loginmodule_99/util"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
)

const (
	sessionCookieName     = "session_token"
	otpSessionTTL         = 10 * time.Minute
	emailSessionTTL       = 10 * time.Minute
	loginSessionTTL       = 24 * time.Hour
	otpTypeSMS            = "signup_sms"
	otpTypeEmail          = "signup_email"
	otpTokenType          = "otp_session"
	emailTokenType        = "email_session"
	loginSessionTokenType = "login_session"
)

var (
	usernameRegex = regexp.MustCompile(`^[A-Za-z0-9_]{4,30}$`)
	passwordRegex = regexp.MustCompile(`^.{8,}$`)
)

func validatePassword(password string) bool {
	if len(password) < 8 {
		return false
	}

	hasUpper := false
	hasDigit := false
	hasSpecial := false
	for _, r := range password {
		switch {
		case r >= 'A' && r <= 'Z':
			hasUpper = true
		case r >= '0' && r <= '9':
			hasDigit = true
		case !(r >= 'A' && r <= 'Z') && !(r >= 'a' && r <= 'z') && !(r >= '0' && r <= '9'):
			hasSpecial = true
		}
	}

	return hasUpper && hasDigit && hasSpecial
}

type verifyCodeRequest struct {
	OTPID string `json:"otp_id"`
	Code  string `json:"code"`
}

type sessionTokenPayload struct {
	TokenType string `json:"token_type"`
	OTPID     string `json:"otp_id,omitempty"`
	Delivery  string `json:"delivery,omitempty"`
	ExpiresAt int64  `json:"expires_at"`
}

type registerChainAdminRequest struct {
	InviteID          string          `json:"invite_id"`
	OTPSessionToken   string          `json:"otp_session_token"`
	EmailSessionToken string          `json:"email_session_token"`
	Username          string          `json:"username"`
	Password          string          `json:"password"`
	ConfirmPassword   string          `json:"confirm_password"`
	Chain             chainPayload    `json:"chain"`
	Branches          []branchPayload `json:"branches"`
}

type chainPayload struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	PanNumber string `json:"pan_number"`
	GSTNumber string `json:"gst_number"`
}

type branchPayload struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	City      string `json:"city"`
	State     string `json:"state"`
	BoardType string `json:"board_type"`
}

type loginChainAdminRequest struct {
	Identifier string `json:"identifier"`
	Password   string `json:"password"`
}

type chainAdminResponse struct {
	Message  string          `json:"message"`
	User     any             `json:"user"`
	Chain    chainPayload    `json:"chain"`
	Branches []branchPayload `json:"branches"`
}

func VerifyOTPWithSession(log *util.Logger, pg *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		log.Info("===== VerifyOTPWithSession Handler HIT =====")

		var req verifyCodeRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			response.Err(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid request payload.")
			return
		}

		if req.OTPID == "" || req.Code == "" {
			response.Err(w, http.StatusBadRequest, "INVALID_REQUEST", "otp_id and code are required.")
			return
		}

		otpID, delivery, err := validateOTPAndMarkUsed(r, pg, req.OTPID, otpTypeSMS, req.Code)
		if err != nil {
			if err == pgx.ErrNoRows {
				response.Err(w, http.StatusBadRequest, "INVALID_OTP", "OTP not found or invalid.")
				return
			}
			if strings.Contains(err.Error(), "already used") {
				response.Err(w, http.StatusBadRequest, "CODE_ALREADY_USED", "OTP already used.")
				return
			}
			if strings.Contains(err.Error(), "expired") {
				response.Err(w, http.StatusBadRequest, "CODE_EXPIRED", "OTP expired.")
				return
			}
			if strings.Contains(err.Error(), "locked") {
				response.Err(w, http.StatusTooManyRequests, "MAX_ATTEMPTS", "Too many wrong attempts. Try again later.")
				return
			}
			log.Error("verify otp failed: %v", err)
			response.Err(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to verify OTP.")
			return
		}

		token, err := buildSessionToken(sessionTokenPayload{
			TokenType: otpTokenType,
			OTPID:     otpID,
			Delivery:  delivery,
			ExpiresAt: time.Now().Add(otpSessionTTL).Unix(),
		})
		if err != nil {
			log.Error("failed to build otp session token: %v", err)
			response.Err(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to issue OTP session token.")
			return
		}

		response.OK(w, map[string]any{
			"message":           "OTP verified successfully",
			"otp_session_token": token,
		})
	}
}

func VerifyEmailWithSession(log *util.Logger, pg *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		log.Info("===== VerifyEmailWithSession Handler HIT =====")

		var req verifyCodeRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			response.Err(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid request payload.")
			return
		}

		if req.OTPID == "" || req.Code == "" {
			response.Err(w, http.StatusBadRequest, "INVALID_REQUEST", "otp_id and code are required.")
			return
		}

		otpID, delivery, err := validateOTPAndMarkUsed(r, pg, req.OTPID, otpTypeEmail, req.Code)
		if err != nil {
			if err == pgx.ErrNoRows {
				response.Err(w, http.StatusBadRequest, "INVALID_CODE", "Verification code not found.")
				return
			}
			if strings.Contains(err.Error(), "already used") {
				response.Err(w, http.StatusBadRequest, "CODE_ALREADY_USED", "Email code already used.")
				return
			}
			if strings.Contains(err.Error(), "expired") {
				response.Err(w, http.StatusBadRequest, "CODE_EXPIRED", "Verification code expired.")
				return
			}
			if strings.Contains(err.Error(), "locked") {
				response.Err(w, http.StatusTooManyRequests, "MAX_ATTEMPTS", "Too many wrong attempts. Try again later.")
				return
			}
			log.Error("verify email failed: %v", err)
			response.Err(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to verify email code.")
			return
		}

		token, err := buildSessionToken(sessionTokenPayload{
			TokenType: emailTokenType,
			OTPID:     otpID,
			Delivery:  delivery,
			ExpiresAt: time.Now().Add(emailSessionTTL).Unix(),
		})
		if err != nil {
			log.Error("failed to build email session token: %v", err)
			response.Err(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to issue email session token.")
			return
		}

		response.OK(w, map[string]any{
			"message":             "Email verified successfully",
			"email_session_token": token,
		})
	}
}

func RegisterChainAdmin(log *util.Logger, pg *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		log.Info("===== RegisterChainAdmin Handler HIT =====")

		var req registerChainAdminRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			response.Err(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid request payload.")
			return
		}

		if req.InviteID == "" || req.OTPSessionToken == "" || req.EmailSessionToken == "" || req.Username == "" || req.Password == "" || req.ConfirmPassword == "" {
			response.Err(w, http.StatusBadRequest, "INVALID_REQUEST", "Missing required fields.")
			return
		}

		if req.Password != req.ConfirmPassword {
			response.Err(w, http.StatusBadRequest, "INVALID_REQUEST", "Password and confirm password must match.")
			return
		}

		if !usernameRegex.MatchString(req.Username) {
			response.Err(w, http.StatusUnprocessableEntity, "WEAK_USERNAME", "Username must be 4-30 characters and contain only letters, numbers, or underscore.")
			return
		}

		if !passwordRegex.MatchString(req.Password) || !validatePassword(req.Password) {
			response.Err(w, http.StatusUnprocessableEntity, "WEAK_PASSWORD", "Password must be at least 8 characters and include uppercase, number and special character.")
			return
		}

		invite, err := fetchInviteByID(r.Context(), pg, req.InviteID)
		if err != nil {
			if err == errNotFound {
				response.Err(w, http.StatusBadRequest, "INVALID_INVITE", "Invite not found or expired.")
				return
			}
			log.Error("fetchInviteByID error: %v", err)
			response.Err(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to validate invite.")
			return
		}

		switch invite.status {
		case "accepted":
			response.Err(w, http.StatusBadRequest, "INVITE_ALREADY_USED", "Account already created with this invite.")
			return
		case "revoked":
			response.Err(w, http.StatusBadRequest, "INVALID_INVITE", "Invite has been cancelled.")
			return
		case "expired":
			response.Err(w, http.StatusBadRequest, "INVALID_INVITE", "Invite has expired.")
			return
		}

		if time.Now().After(invite.expiresAt) {
			response.Err(w, http.StatusBadRequest, "INVALID_INVITE", "Invite has expired.")
			return
		}

		otpToken, err := parseSessionToken(req.OTPSessionToken)
		if err != nil || otpToken.TokenType != otpTokenType || otpToken.Delivery != invite.userPhone {
			response.Err(w, http.StatusBadRequest, "INVALID_OTP_TOKEN", "OTP session token is invalid or expired.")
			return
		}

		emailToken, err := parseSessionToken(req.EmailSessionToken)
		if err != nil || emailToken.TokenType != emailTokenType || emailToken.Delivery != invite.userEmail {
			response.Err(w, http.StatusBadRequest, "INVALID_EMAIL_TOKEN", "Email session token is invalid or expired.")
			return
		}

		hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
		if err != nil {
			log.Error("failed to hash password: %v", err)
			response.Err(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to register user.")
			return
		}

		tenantPG, err := db.Manager.GetTenantPool(r.Context(), invite.chainID)
		if err != nil {
			log.Error("failed to get tenant pool: %v", err)
			response.Err(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to register user.")
			return
		}

		if usernameExists(r.Context(), tenantPG, req.Username) {
			response.Err(w, http.StatusConflict, "USERNAME_TAKEN", "Username already exists.")
			return
		}

		tx, err := tenantPG.BeginTx(r.Context(), pgx.TxOptions{})
		if err != nil {
			log.Error("register tx begin failed: %v", err)
			response.Err(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to register user.")
			return
		}
		defer func() {
			if err != nil {
				_ = tx.Rollback(r.Context())
			}
		}()

		if err := insertChain(r.Context(), tx, req.Chain); err != nil {
			log.Error("insertChain failed: %v", err)
			response.Err(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to save chain.")
			return
		}

		if err := insertBranches(r.Context(), tx, req.Chain.ID, req.Branches); err != nil {
			log.Error("insertBranches failed: %v", err)
			response.Err(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to save branches.")
			return
		}

		userID, err := insertManagementUser(r.Context(), tx, invite.userName, req.Username, invite.userEmail, invite.userPhone, string(hashedPassword), req.Chain.ID)
		if err != nil {
			log.Error("insertManagementUser failed: %v", err)
			response.Err(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to save user.")
			return
		}

		sessionToken := uuid.New().String()
		if err := createSession(r.Context(), tx, userID, sessionToken); err != nil {
			log.Error("createSession failed: %v", err)
			response.Err(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to create session.")
			return
		}

		if err := tx.Commit(r.Context()); err != nil {
			log.Error("commit failed: %v", err)
			response.Err(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to complete registration.")
			return
		}

		if err := markInviteUsed(r.Context(), pg, req.InviteID); err != nil {
			log.Error("markInviteUsed failed: %v", err)
			response.Err(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to finalize invite.")
			return
		}

		setSessionCookie(w, sessionToken)

		response.Created(w, map[string]any{
			"message": "Account created successfully.",
			"user": map[string]any{
				"id":       userID,
				"name":     invite.userName,
				"username": req.Username,
				"email":    invite.userEmail,
				"phone":    invite.userPhone,
				"role":     "chain_admin",
			},
			"chain":    req.Chain,
			"branches": req.Branches,
		})
	}
}

func LoginChainAdmin(log *util.Logger, pg *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		log.Info("===== LoginChainAdmin Handler HIT =====")

		var req loginChainAdminRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			response.Err(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid request payload.")
			return
		}

		if req.Identifier == "" || req.Password == "" {
			response.Err(w, http.StatusBadRequest, "INVALID_REQUEST", "identifier and password are required.")
			return
		}

		chainID, err := fetchChainIDByIdentifier(r.Context(), pg, req.Identifier)
		if err != nil {
			if err == pgx.ErrNoRows {
				response.Err(w, http.StatusUnauthorized, "INVALID_CREDENTIALS", "Invalid email/mobile or password.")
				return
			}
			log.Error("fetchChainIDByIdentifier failed: %v", err)
			response.Err(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to login.")
			return
		}

		tenantPG, err := db.Manager.GetTenantPool(r.Context(), chainID)
		if err != nil {
			log.Error("failed to get tenant pool: %v", err)
			response.Err(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to login.")
			return
		}

		user, err := fetchUserByIdentifier(r.Context(), tenantPG, req.Identifier)
		if err != nil {
			if err == pgx.ErrNoRows {
				response.Err(w, http.StatusUnauthorized, "INVALID_CREDENTIALS", "Invalid email/mobile or password.")
				return
			}
			log.Error("fetchUserByIdentifier failed: %v", err)
			response.Err(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to login.")
			return
		}

		if user.Role != "chain_admin" && user.Role != "admin" {
			// allow chain admin and admin roles in the same flow
		}

		if user.IsInactive {
			response.Err(w, http.StatusForbidden, "ACCOUNT_INACTIVE", "Account is inactive.")
			return
		}

		if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
			response.Err(w, http.StatusUnauthorized, "INVALID_CREDENTIALS", "Invalid email/mobile or password.")
			return
		}

		sessionToken := uuid.New().String()
		if err := createSession(r.Context(), tenantPG, user.ID, sessionToken); err != nil {
			log.Error("createSession failed: %v", err)
			response.Err(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to create session.")
			return
		}

		chain, err := loadChainDetails(r.Context(), tenantPG, user.ChainID)
		if err != nil {
			log.Error("loadChainDetails failed: %v", err)
			response.Err(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load chain data.")
			return
		}

		branches, err := loadBranchesByChainID(r.Context(), tenantPG, user.ChainID)
		if err != nil {
			log.Error("loadBranchesByChainID failed: %v", err)
			response.Err(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Unable to load branches.")
			return
		}

		setSessionCookie(w, sessionToken)

		response.OK(w, map[string]any{
			"user": map[string]any{
				"id":       user.ID,
				"name":     user.Name,
				"username": user.Username,
				"email":    user.Email,
				"phone":    user.Phone,
				"role":     user.Role,
			},
			"chain":    chain,
			"branches": branches,
		})
	}
}

type managementUserRecord struct {
	ID           string
	Name         string
	Username     string
	Email        string
	Phone        string
	PasswordHash string
	Role         string
	ChainID      string
	IsInactive   bool
}

func validateOTPAndMarkUsed(r *http.Request, pg *pgxpool.Pool, otpID, tokenType, code string) (string, string, error) {
	ctx := r.Context()
	var (
		storedID  string
		codeHash  string
		isUsed    bool
		expiresAt time.Time
		attempts  int
		delivery  string
	)

	row := pg.QueryRow(ctx, `
		SELECT
			o.id,
			o.code_hash,
			o.is_used,
			o.expires_at,
			o.attempts,
			o.delivery_address
		FROM auth.otp o
		JOIN auth.otp_type t ON t.id = o.otp_type_id
		WHERE o.id = $1
		AND t.name = $2
		`, otpID, tokenType)

	if err := row.Scan(&storedID, &codeHash, &isUsed, &expiresAt, &attempts, &delivery); err != nil {
		return "", "", err
	}

	if isUsed {
		return "", "", fmt.Errorf("already used")
	}

	if attempts >= 5 {
		return "", "", fmt.Errorf("locked")
	}

	if time.Now().After(expiresAt) {
		return "", "", fmt.Errorf("expired")
	}

	if hashOTP(code) != codeHash {
		_, err := pg.Exec(ctx, `
			UPDATE auth.otp
			SET attempts = attempts + 1
			WHERE id = $1`, otpID)
		if err != nil {
			return "", "", fmt.Errorf("invalid code")
		}
		return "", "", fmt.Errorf("invalid code")
	}

	_, err := pg.Exec(ctx, `
		UPDATE auth.otp
		SET is_used = true,
			attempts = 0
		WHERE id = $1`, otpID)
	if err != nil {
		return "", "", err
	}

	return storedID, delivery, nil
}

func buildSessionToken(payload sessionTokenPayload) (string, error) {
	head, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}
	encoded := base64.RawURLEncoding.EncodeToString(head)
	sig := computeHMAC(encoded, getSessionSecret())
	return fmt.Sprintf("%s.%s", encoded, sig), nil
}

func parseSessionToken(token string) (sessionTokenPayload, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 2 {
		return sessionTokenPayload{}, fmt.Errorf("invalid token format")
	}

	recvSig := parts[1]
	if !hmac.Equal([]byte(recvSig), []byte(computeHMAC(parts[0], getSessionSecret()))) {
		return sessionTokenPayload{}, fmt.Errorf("invalid token signature")
	}

	data, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return sessionTokenPayload{}, err
	}

	var payload sessionTokenPayload
	if err := json.Unmarshal(data, &payload); err != nil {
		return sessionTokenPayload{}, err
	}

	if time.Now().Unix() > payload.ExpiresAt {
		return sessionTokenPayload{}, fmt.Errorf("token expired")
	}

	return payload, nil
}

func computeHMAC(data string, secret []byte) string {
	h := hmac.New(sha256.New, secret)
	_, _ = h.Write([]byte(data))
	return base64.RawURLEncoding.EncodeToString(h.Sum(nil))
}

func getSessionSecret() []byte {
	secret := os.Getenv("SESSION_TOKEN_SECRET")
	if secret == "" {
		secret = "default-chain-admin-secret-change-me"
	}
	return []byte(secret)
}

func setSessionCookie(w http.ResponseWriter, token string) {
	http.SetCookie(w, &http.Cookie{
		Name:     sessionCookieName,
		Value:    token,
		HttpOnly: true,
		Secure:   true,
		SameSite: http.SameSiteStrictMode,
		Path:     "/",
		MaxAge:   int(loginSessionTTL.Seconds()),
	})
}

func usernameExists(ctx context.Context, pg *pgxpool.Pool, username string) bool {
	var existing string
	err := pg.QueryRow(ctx, `SELECT id FROM auth.management_user WHERE LOWER(username) = LOWER($1)`, username).Scan(&existing)
	return err == nil
}

func fetchInviteByID(ctx context.Context, pg *pgxpool.Pool, inviteID string) (*inviteRecord, error) {
	query := `
		SELECT
			i.id,
			s.name AS status,
			i.expires_at,
			mu.name AS user_name,
			COALESCE(mu.email, '') AS user_email,
			COALESCE(mu.phone, '') AS user_phone,
			c.id AS chain_id,
			c.name AS chain_name
		FROM auth.invite i
		JOIN auth.invite_status s ON s.id = i.status_id
		JOIN auth.management_user mu ON mu.id = i.management_user_id
		JOIN onboarding.chain c ON c.created_by = mu.id
		WHERE i.id = $1
	`

	row := pg.QueryRow(ctx, query, inviteID)

	var rec inviteRecord
	if err := row.Scan(&rec.id, &rec.status, &rec.expiresAt, &rec.userName, &rec.userEmail, &rec.userPhone, &rec.chainID, &rec.chainName); err != nil {
		if isNoRows(err) {
			return nil, errNotFound
		}
		return nil, err
	}

	return &rec, nil
}

func insertChain(ctx context.Context, tx pgx.Tx, chain chainPayload) error {
	_, err := tx.Exec(ctx, `
		INSERT INTO management.chain (id, name, pan_number, gst_number, created_at)
		VALUES ($1, $2, $3, $4, NOW())
	`, chain.ID, chain.Name, chain.PanNumber, chain.GSTNumber)
	return err
}

func insertBranches(ctx context.Context, tx pgx.Tx, chainID string, branches []branchPayload) error {
	for _, branch := range branches {
		_, err := tx.Exec(ctx, `
			INSERT INTO management.management_table (
				id,
				tenant_id,
				chain_id,
				branch_name,
				city,
				state,
				board_type,
				created_at
			)
			VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
		`, uuid.NewString(), branch.ID, chainID, branch.Name, branch.City, branch.State, branch.BoardType)
		if err != nil {
			return err
		}
	}
	return nil
}

func insertManagementUser(ctx context.Context, tx pgx.Tx, name, username, email, phone, passwordHash, chainID string) (string, error) {
	userID := uuid.NewString()
	_, err := tx.Exec(ctx, `
		INSERT INTO auth.management_user (
			id,
			name,
			username,
			email,
			phone,
			password_hash,
			chain_id,
			role,
			created_at
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, 'chain_admin', NOW())
	`, userID, name, username, email, phone, passwordHash, chainID)
	return userID, err
}

func markInviteUsed(ctx context.Context, ex interface {
	Exec(context.Context, string, ...any) (pgconn.CommandTag, error)
}, inviteID string) error {
	_, err := ex.Exec(ctx, `
		UPDATE auth.invite
		SET is_used = true,
			used_at = NOW()
		WHERE id = $1
	`, inviteID)
	return err
}

func createSession(ctx context.Context, ex interface {
	Exec(context.Context, string, ...any) (pgconn.CommandTag, error)
}, userID, token string) error {
	_, err := ex.Exec(ctx, `
		INSERT INTO auth.session (id, user_id, token, expires_at, created_at)
		VALUES ($1, $2, $3, NOW() + INTERVAL '24 hours', NOW())
	`, uuid.NewString(), userID, token)
	return err
}

type chainDetails struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	PanNumber string `json:"pan_number"`
	GSTNumber string `json:"gst_number"`
}

func loadChainDetails(ctx context.Context, pg *pgxpool.Pool, chainID string) (chainDetails, error) {
	var chain chainDetails
	if err := pg.QueryRow(ctx, `
		SELECT id, name, pan_number, gst_number
		FROM management.chain
		WHERE id = $1
	`, chainID).Scan(&chain.ID, &chain.Name, &chain.PanNumber, &chain.GSTNumber); err != nil {
		return chainDetails{}, err
	}
	return chain, nil
}

func loadBranchesByChainID(ctx context.Context, pg *pgxpool.Pool, chainID string) ([]branchPayload, error) {
	rows, err := pg.Query(ctx, `
		SELECT tenant_id, branch_name, city, state, board_type
		FROM management.management_table
		WHERE chain_id = $1
		ORDER BY branch_name
	`, chainID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var branches []branchPayload
	for rows.Next() {
		var branch branchPayload
		if err := rows.Scan(&branch.ID, &branch.Name, &branch.City, &branch.State, &branch.BoardType); err != nil {
			return nil, err
		}
		branches = append(branches, branch)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return branches, nil
}

func fetchChainIDByIdentifier(ctx context.Context, pg *pgxpool.Pool, identifier string) (string, error) {
	var chainID string
	err := pg.QueryRow(ctx, `
		SELECT c.id
		FROM auth.management_user mu
		JOIN onboarding.chain c ON c.created_by = mu.id
		WHERE LOWER(mu.email) = LOWER($1)
		   OR REPLACE(mu.phone, '+', '') = REPLACE($1, '+', '')
	`, identifier).Scan(&chainID)
	return chainID, err
}

func fetchUserByIdentifier(ctx context.Context, pg *pgxpool.Pool, identifier string) (managementUserRecord, error) {
	var rec managementUserRecord
	query := `
		SELECT id, name, username, email, phone, password_hash, role, chain_id, is_active
		FROM auth.management_user
		WHERE LOWER(email) = LOWER($1)
		OR REPLACE(phone, '+', '') = REPLACE($1, '+', '')
	`
	var isActive bool
	if err := pg.QueryRow(ctx, query, identifier).Scan(&rec.ID, &rec.Name, &rec.Username, &rec.Email, &rec.Phone, &rec.PasswordHash, &rec.Role, &rec.ChainID, &isActive); err != nil {
		return managementUserRecord{}, err
	}
	rec.IsInactive = !isActive
	return rec, nil
}
