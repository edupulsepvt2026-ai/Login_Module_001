package auth

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"loginmodule_99/response"
	"loginmodule_99/util"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type SendEmailVerificationRequest struct {
	InviteID string `json:"invite_id"`
	Email    string `json:"email"`
}

type VerifyEmailRequest struct {
	Email string `json:"email"`
	OTP   string `json:"otp"`
}

type RegisterChainAdminRequest struct {
	Name     string `json:"name"`
	Email    string `json:"email"`
	Phone    string `json:"phone"`
	Password string `json:"password"`
}

type LoginChainAdminRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

func SendEmailVerification(log *util.Logger, pg *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		log.Info("===== SendEmailVerification Handler HIT =====")

		var req SendEmailVerificationRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "Invalid Request", http.StatusBadRequest)
			return
		}

		if req.InviteID == "" || req.Email == "" {
			http.Error(w, "invite_id and email are required", http.StatusBadRequest)
			return
		}

		invite, err := fetchInviteByID(r.Context(), pg, req.InviteID)
		if err != nil {
			if err == errNotFound {
				log.Warn("invalid invite_id %s", req.InviteID)
				http.Error(w, "Invalid invite", http.StatusBadRequest)
				return
			}
			log.Error("fetch invite failed: %v", err)
			http.Error(w, "Failed to validate invite", http.StatusInternalServerError)
			return
		}

		if invite.userEmail != req.Email {
			http.Error(w, "Email does not match invite", http.StatusBadRequest)
			return
		}

		if invite.status == "accepted" {
			http.Error(w, "Invite already used", http.StatusBadRequest)
			return
		}

		if invite.status == "revoked" {
			http.Error(w, "Invite revoked", http.StatusBadRequest)
			return
		}

		if time.Now().After(invite.expiresAt) {
			http.Error(w, "Invite expired", http.StatusBadRequest)
			return
		}

		var lastAttempts int
		err = pg.QueryRow(
			r.Context(),
			`
			SELECT attempts
			FROM auth.otp
			WHERE LOWER(delivery_address) = LOWER($1)
			  AND otp_type_id = (
				SELECT id FROM auth.otp_type WHERE name = 'signup_email'
			)
			ORDER BY created_at DESC
			LIMIT 1
			`,
			req.Email,
		).Scan(&lastAttempts)
		if err != nil && err != pgx.ErrNoRows {
			log.Error("OTP block check failed: %v", err)
			http.Error(w, "Failed to generate OTP", http.StatusInternalServerError)
			return
		}

		if err == nil && lastAttempts >= 5 {
			http.Error(w, "OTP sending blocked due to repeated failed attempts. Try again later.", http.StatusTooManyRequests)
			return
		}

		otp := generateOTP()
		hashedOTP := hashOTP(otp)

		var otpTypeID string
		err = pg.QueryRow(
			r.Context(),
			`
			SELECT id
			FROM auth.otp_type
			WHERE name = 'signup_email'
			`,
		).Scan(&otpTypeID)
		if err != nil {
			log.Error("EMAIL OTP type not found: %v", err)
			http.Error(w, "OTP configuration missing", http.StatusInternalServerError)
			return
		}

		otpID := uuid.New().String()
		_, err = pg.Exec(
			r.Context(),
			`
			INSERT INTO auth.otp
			(
				id,
				otp_type_id,
				code_hash,
				attempts,
				is_used,
				delivery_address,
				expires_at,
				created_at
			)
			VALUES
			(
				$1,
				$2,
				$3,
				0,
				false,
				$4,
				NOW() + INTERVAL '10 minutes',
				NOW()
			)
			`,
			otpID,
			otpTypeID,
			hashedOTP,
			req.Email,
		)
		if err != nil {
			log.Error("Failed to store email OTP: %v", err)
			http.Error(w, "Failed to generate OTP", http.StatusInternalServerError)
			return
		}

		message := fmt.Sprintf("Your email verification code is %s", otp)
		subject := "Email verification code"
		if err := notifyOmniChannel("email", req.Email, subject, message); err != nil {
			log.Error("notify service error: %v", err)
			http.Error(w, "Failed to send OTP", http.StatusInternalServerError)
			return
		}

		response.OK(w, map[string]any{
			"email_verification_id": otpID,
			"expires_in_seconds":    600,
			"message":               "Verification code sent successfully",
		})
	}
}

func VerifyEmail(log *util.Logger, pg *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		log.Info("===== VerifyEmail Handler HIT =====")

		var req VerifyEmailRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "Invalid Request", http.StatusBadRequest)
			return
		}

		var userID string
		err := pg.QueryRow(
			r.Context(),
			`
			SELECT id
			FROM auth.management_user
			WHERE LOWER(email) = LOWER($1)
			`,
			req.Email,
		).Scan(&userID)
		if err != nil {
			http.Error(w, "User Not Found", http.StatusNotFound)
			return
		}

		var (
			otpID     string
			codeHash  string
			isUsed    bool
			expiresAt time.Time
			attempts  int
		)

		err = pg.QueryRow(
			r.Context(),
			`
			SELECT
				id,
				code_hash,
				is_used,
				expires_at,
				attempts
			FROM auth.otp
			WHERE LOWER(delivery_address) = LOWER($1)
			ORDER BY created_at DESC
			LIMIT 1
			`,
			req.Email,
		).Scan(&otpID, &codeHash, &isUsed, &expiresAt, &attempts)

		if err != nil {
			if err == pgx.ErrNoRows {
				http.Error(w, "OTP Not Found", http.StatusNotFound)
				return
			}
			log.Error("OTP query failed: %v", err)
			http.Error(w, "OTP Not Found", http.StatusNotFound)
			return
		}

		if attempts >= 5 {
			http.Error(w, "Too many failed OTP attempts. Try again later.", http.StatusTooManyRequests)
			return
		}

		if isUsed {
			http.Error(w, "OTP Already Used", http.StatusBadRequest)
			return
		}

		if time.Now().After(expiresAt) {
			http.Error(w, "OTP Expired", http.StatusBadRequest)
			return
		}

		if hashOTP(req.OTP) != codeHash {
			_, err = pg.Exec(
				r.Context(),
				`
				UPDATE auth.otp
				SET attempts = attempts + 1
				WHERE id = $1
				`,
				otpID,
			)
			if err != nil {
				log.Error("Failed to update failed email OTP attempt: %v", err)
			}
			http.Error(w, "Invalid OTP", http.StatusUnauthorized)
			return
		}

		_, err = pg.Exec(
			r.Context(),
			`
			UPDATE auth.otp
			SET is_used = true,
			    attempts = 0
			WHERE id = $1
			`,
			otpID,
		)
		if err != nil {
			log.Error("Failed to update OTP: %v", err)
			http.Error(w, "Verification Failed", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{
			"status":  "success",
			"message": "Email verified successfully",
		})
	}
}
