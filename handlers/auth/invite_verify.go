// Package auth contains HTTP handlers for the auth flow.
package auth

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"fmt"
	"net/http"
	"time"

	"loginmodule_99/response"
	"loginmodule_99/util"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ── Response types ────────────────────────────────────────────────────────────

type branchInfo struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	City      string `json:"city"`
	State     string `json:"state"`
	BoardType string `json:"board_type"`
}

type chainInfo struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	PanNumber string `json:"pan_number"`
	GSTNumber string `json:"gst_number"`
}

type inviteVerifyData struct {
	InviteID  string       `json:"invite_id"`
	Name      string       `json:"name"`
	Email     string       `json:"email"`
	Phone     string       `json:"phone"`
	Chain     chainInfo    `json:"chain"`
	Branches  []branchInfo `json:"branches"`
	ExpiresAt time.Time    `json:"expires_at"`
}

// ── Handler ───────────────────────────────────────────────────────────────────

// InviteVerify handles GET /api/v1/auth/invite/verify/{token}
// Validates the magic link token and returns invite + chain + branch info.
func InviteVerify(log *util.Logger, pg *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		rawToken := util.PathParam(r, "token")
		if rawToken == "" {
			response.Err(w, http.StatusBadRequest, "INVALID_TOKEN", "Token is required.")
			return
		}

		tokenHash := hashToken(rawToken)
		log.Info("invite verify request token_hash_prefix=%s", tokenHash[:8])
		ctx := r.Context()

		// ── Step 1: fetch invite + status + management user + chain ──────────
		invite, err := fetchInvite(ctx, pg, tokenHash)
		if err == errNotFound {
			log.Warn("invite not found token_hash_prefix=%s", tokenHash[:8])
			response.Err(w, http.StatusBadRequest, "INVALID_TOKEN", "The invite link is invalid or has already been used.")
			return
		}
		if err != nil {
			log.Error("fetchInvite error: %v", err)
			response.Err(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Something went wrong. Please try again.")
			return
		}

		// ── Step 2: check status ─────────────────────────────────────────────
		switch invite.status {
		case "accepted":
			response.Err(w, http.StatusBadRequest, "INVALID_TOKEN", "This invite has already been accepted.")
			return
		case "revoked":
			response.Err(w, http.StatusBadRequest, "TOKEN_REVOKED", "This invite has been cancelled.")
			return
		case "expired":
			response.Err(w, http.StatusBadRequest, "TOKEN_EXPIRED", "This invite has expired.")
			return
		}

		// ── Step 3: check expiry ─────────────────────────────────────────────
		if time.Now().After(invite.expiresAt) {
			log.Warn("invite token expired invite_id=%s expired_at=%s", invite.id, invite.expiresAt)
			return
		}

		// ── Step 4: fetch all branches for the chain ─────────────────────────
		branches, err := fetchBranches(ctx, pg, invite.chainID)
		if err != nil {
			log.Error("fetchBranches error: %v", err)
			response.Err(w, http.StatusInternalServerError, "INTERNAL_ERROR", "Something went wrong. Please try again.")
			return
		}

		log.Info("invite verified successfully invite_id=%s chain=%s", invite.id, invite.chainName)

		response.OK(w, inviteVerifyData{
			InviteID: invite.id,
			Name:     invite.userName,
			Email:    invite.userEmail,
			Phone:    invite.userPhone,
			Chain: chainInfo{
				ID:        invite.chainID,
				Name:      invite.chainName,
				PanNumber: invite.chainPanNumber,
				GSTNumber: invite.chainGSTNumber,
			},
			Branches:  branches,
			ExpiresAt: invite.expiresAt,
		})
	}
}

// ── DB helpers ────────────────────────────────────────────────────────────────

var errNotFound = fmt.Errorf("not found")

type inviteRecord struct {
	id             string
	status         string
	expiresAt      time.Time
	userName       string
	userEmail      string
	userPhone      string
	chainID        string
	chainName      string
	chainPanNumber string
	chainGSTNumber string
}

func fetchInvite(ctx context.Context, pg *pgxpool.Pool, tokenHash string) (*inviteRecord, error) {
	query := `
		SELECT
			i.id,
			s.name           AS status,
			i.expires_at,
			mu.name          AS user_name,
			COALESCE(mu.email, '') AS user_email,
			COALESCE(mu.phone, '') AS user_phone,
			c.id             AS chain_id,
			c.name           AS chain_name,
		COALESCE(c.pan_number, '') AS chain_pan_number,
		COALESCE(c.gst_number, '') AS chain_gst_number
		FROM auth.invite i
		JOIN auth.invite_status   s  ON s.id  = i.status_id
		JOIN auth.management_user mu ON mu.id = i.management_user_id
		JOIN onboarding.chain     c  ON c.created_by = mu.id
		WHERE i.invite_token_hash = $1
	`

	row := pg.QueryRow(ctx, query, tokenHash)

	var rec inviteRecord
	err := row.Scan(
		&rec.id,
		&rec.status,
		&rec.expiresAt,
		&rec.userName,
		&rec.userEmail,
		&rec.userPhone,
		&rec.chainID,
		&rec.chainName,
		&rec.chainPanNumber,
		&rec.chainGSTNumber,
	)
	if err != nil {
		if isNoRows(err) {
			return nil, errNotFound
		}
		return nil, fmt.Errorf("fetchInvite scan: %w", err)
	}

	return &rec, nil
}

func fetchBranches(ctx context.Context, pg *pgxpool.Pool, chainID string) ([]branchInfo, error) {
	query := `
		SELECT id, name, city, state, board_type
		FROM onboarding.branch
		WHERE chain_id = $1
		  AND is_active = true
		ORDER BY name
	`

	rows, err := pg.Query(ctx, query, chainID)
	if err != nil {
		return nil, fmt.Errorf("fetchBranches query: %w", err)
	}
	defer rows.Close()

	var branches []branchInfo
	for rows.Next() {
		var b branchInfo
		if err := rows.Scan(&b.ID, &b.Name, &b.City, &b.State, &b.BoardType); err != nil {
			return nil, fmt.Errorf("fetchBranches scan: %w", err)
		}
		branches = append(branches, b)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("fetchBranches rows: %w", err)
	}

	if branches == nil {
		branches = []branchInfo{}
	}

	return branches, nil
}

// hashToken returns the hex-encoded SHA-256 of the raw token.
func hashToken(raw string) string {
	h := sha256.Sum256([]byte(raw))
	return fmt.Sprintf("%x", h)
}

// isNoRows returns true for pgx "no rows" errors.
func isNoRows(err error) bool {
	return err != nil && (err == sql.ErrNoRows || err.Error() == "no rows in result set")
}
