package repository

import (
	"context"
	"fmt"
	"time"

	"auth-service/internal/model"

	"github.com/jackc/pgx/v5/pgxpool"
)

type OTPRepository struct {
	db *pgxpool.Pool
}

func NewOTPRepository(db *pgxpool.Pool) *OTPRepository {
	return &OTPRepository{db: db}
}

func (r *OTPRepository) GetTypeIDByName(ctx context.Context, name string) (string, error) {
	var id string
	err := r.db.QueryRow(ctx, `
		SELECT id FROM auth.otp_type WHERE name = $1
	`, name).Scan(&id)
	if err != nil {
		return "", fmt.Errorf("otp_type %q not found: %w", name, err)
	}
	return id, nil
}

func (r *OTPRepository) Create(ctx context.Context, typeID, codeHash, deliveryAddress string, expiresAt time.Time) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO auth.otp (otp_type_id, code_hash, delivery_address, expires_at)
		VALUES ($1, $2, $3, $4)
	`, typeID, codeHash, deliveryAddress, expiresAt)
	if err != nil {
		return fmt.Errorf("failed to create OTP: %w", err)
	}
	return nil
}

func (r *OTPRepository) GetActive(ctx context.Context, deliveryAddress string) (*model.OTP, error) {
	otp := &model.OTP{}
	err := r.db.QueryRow(ctx, `
		SELECT id, otp_type_id, code_hash, attempts, is_used, delivery_address, expires_at, created_at
		FROM auth.otp
		WHERE delivery_address = $1
		  AND is_used = false
		  AND expires_at > now()
		ORDER BY created_at DESC
		LIMIT 1
	`, deliveryAddress).Scan(
		&otp.ID,
		&otp.OTPTypeID,
		&otp.CodeHash,
		&otp.Attempts,
		&otp.IsUsed,
		&otp.DeliveryAddress,
		&otp.ExpiresAt,
		&otp.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("active OTP not found: %w", err)
	}
	return otp, nil
}

func (r *OTPRepository) InvalidatePrevious(ctx context.Context, deliveryAddress string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE auth.otp
		SET is_used = true
		WHERE delivery_address = $1
		  AND is_used = false
		  AND expires_at > now()
	`, deliveryAddress)
	return err
}

func (r *OTPRepository) IncrementAttempt(ctx context.Context, otpID string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE auth.otp SET attempts = attempts + 1 WHERE id = $1
	`, otpID)
	return err
}

func (r *OTPRepository) MarkUsed(ctx context.Context, otpID string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE auth.otp SET is_used = true WHERE id = $1
	`, otpID)
	return err
}
