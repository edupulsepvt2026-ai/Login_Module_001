package auth

import (
	"encoding/json"
	"net/http"
	"time"

	"loginmodule_99/util"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type VerifyOTPRequest struct {
	Phone string `json:"phone"`
	OTP   string `json:"otp"`
}

func VerifyOTP(
	log *util.Logger,
	pg *pgxpool.Pool,
) http.HandlerFunc {

	return func(w http.ResponseWriter, r *http.Request) {

		log.Info("===== VerifyOTP Handler HIT =====")

		var req VerifyOTPRequest

		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "Invalid Request", http.StatusBadRequest)
			return
		}

		// Find user by phone
		var userID string

		err := pg.QueryRow(
			r.Context(),
			`
			SELECT id
			FROM auth.management_user
			WHERE REPLACE(phone, '+', '') = REPLACE($1, '+', '')
			`,
			req.Phone,
		).Scan(&userID)

		if err != nil {
			http.Error(w, "User Not Found", http.StatusNotFound)
			return
		}

		// Get latest OTP for this user and phone
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
		WHERE REPLACE(delivery_address, '+', '') = REPLACE($1, '+', '')
		ORDER BY created_at DESC
		LIMIT 1
		`,
			req.Phone,
		).Scan(
			&otpID,
			&codeHash,
			&isUsed,
			&expiresAt,
			&attempts,
		)

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

		incomingHash := hashOTP(req.OTP)
		if incomingHash != codeHash {
			_, updateErr := pg.Exec(
				r.Context(),
				`
				UPDATE auth.otp
				SET attempts = attempts + 1
				WHERE id = $1
				`,
				otpID,
			)
			if updateErr != nil {
				log.Error("Failed to update OTP attempts: %v", updateErr)
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

		// Return user details
		var (
			id    string
			phone string
			email string
		)

		err = pg.QueryRow(
			r.Context(),
			`
			SELECT
				id,
				phone,
				email
			FROM auth.management_user
			WHERE id = $1
			`,
			userID,
		).Scan(
			&id,
			&phone,
			&email,
		)

		if err != nil {
			http.Error(w, "Failed To Load User", http.StatusInternalServerError)
			return
		}

		w.Header().Set("Content-Type", "application/json")

		json.NewEncoder(w).Encode(map[string]any{
			"status":  "success",
			"message": "OTP verified successfully",
			"user": map[string]any{
				"id":    id,
				"phone": phone,
				"email": email,
			},
		})
	}
}
