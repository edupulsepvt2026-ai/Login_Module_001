package auth

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"math/rand"
	"net/http"
	"time"

	"loginmodule_99/response"
	"loginmodule_99/util"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type SendOTPRequest struct {
	InviteID string `json:"invite_id"`
	Phone    string `json:"phone"`
	Type     string `json:"type"`
}

type SendOTPResponse struct {
	OTPID            string `json:"otp_id"`
	ExpiresInSeconds int    `json:"expires_in_seconds"`
	Message          string `json:"message"`
}

func SendOTP(
	log *util.Logger,
	pg *pgxpool.Pool,
) http.HandlerFunc {

	return func(w http.ResponseWriter, r *http.Request) {

		log.Info("===== SendOTP Handler HIT =====")

		var req SendOTPRequest

		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "Invalid Request", http.StatusBadRequest)
			return
		}

		if req.InviteID == "" || req.Phone == "" || req.Type == "" {
			http.Error(w, "invite_id, phone and type are required", http.StatusBadRequest)
			return
		}

		if req.Type != "signup_sms" {
			http.Error(w, "invalid otp type", http.StatusBadRequest)
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

		if invite.userPhone != req.Phone {
			http.Error(w, "Phone does not match invite", http.StatusBadRequest)
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

		// Step 2: Prevent new OTP when user is blocked by repeated failed attempts
		var lastAttempts int

		err = pg.QueryRow(
			r.Context(),
			`
			SELECT
				attempts
			FROM auth.otp
			WHERE REPLACE(delivery_address, '+', '') = REPLACE($1, '+', '')
			  AND otp_type_id = (
				SELECT id FROM auth.otp_type WHERE name = 'signup_sms'
			)
			ORDER BY created_at DESC
			LIMIT 1
			`,
			req.Phone,
		).Scan(&lastAttempts)

		if err != nil && err != pgx.ErrNoRows {
			log.Error("OTP block check failed: %v", err)
			http.Error(w, "Failed to generate OTP", http.StatusInternalServerError)
			return
		}

		if err == nil {
			if lastAttempts >= 5 {
				http.Error(w, "OTP sending blocked due to repeated failed attempts. Try again later.", http.StatusTooManyRequests)
				return
			}
		}

		// Step 3: Generate OTP
		otp := generateOTP()
		hashedOTP := hashOTP(otp)

		log.Info("Generated OTP: %s", otp)
		log.Info("Generated OTP Hash: %s", hashedOTP)

		var otpTypeID string

		err = pg.QueryRow(
			r.Context(),
			`
			SELECT id
			FROM auth.otp_type
			WHERE name = 'signup_sms'
			`,
		).Scan(&otpTypeID)

		if err != nil {
			log.Error("LOGIN OTP type not found: %v", err)
			http.Error(w, "OTP configuration missing", http.StatusInternalServerError)
			return
		}

		// Step 4: Store OTP
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
			hashedOTP, //  hashed OTP
			req.Phone,
		)

		if err != nil {
			log.Error("Failed to store OTP: %v", err)
			http.Error(w, "Failed to generate OTP", http.StatusInternalServerError)
			return
		}

		log.Info("OTP stored successfully")

		// TODO:
		// Send SMS using Infobip here
		smsMessage := fmt.Sprintf("Your OTP is %s", otp)
		if err := notifyOmniChannel("sms", req.Phone, "", smsMessage); err != nil {
			log.Error("notify service error: %v", err)

			http.Error(w, "Failed to send OTP", http.StatusInternalServerError)
			return
		}

		response.OK(w, SendOTPResponse{
			OTPID:            otpID,
			ExpiresInSeconds: 600,
			Message:          "OTP sent to " + req.Phone,
		})
	}
}
func generateOTP() string {
	rand.Seed(time.Now().UnixNano())

	return fmt.Sprintf(
		"%06d",
		rand.Intn(1000000),
	)
}

func hashOTP(otp string) string {
	hash := sha256.Sum256([]byte(otp))
	return hex.EncodeToString(hash[:])
}

func notifyOmniChannel(kind, to, subject, body string) error {
	payload := map[string]string{
		"kind": kind,
		"to":   to,
	}

	switch kind {
	case "email":
		payload["subject"] = subject
		payload["body"] = body
	default:
		payload["message"] = body
	}

	bodyBytes, _ := json.Marshal(payload)

	resp, err := http.Post("http://localhost:8081/api/v1/notify", "application/json", bytes.NewReader(bodyBytes))
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated && resp.StatusCode != http.StatusAccepted {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("notify failed: %s; body: %s", resp.Status, string(body))
	}
	return nil
}
