package repository

import (
	"context"
	"fmt"

	"auth-service/internal/model"

	"github.com/jackc/pgx/v5/pgxpool"
)

type UserRepository struct {
	db *pgxpool.Pool
}

func NewUserRepository(db *pgxpool.Pool) *UserRepository {
	return &UserRepository{db: db}
}

func (r *UserRepository) GetByID(ctx context.Context, id string) (*model.ManagementUser, error) {
	user := &model.ManagementUser{}
	err := r.db.QueryRow(ctx, `
		SELECT id, chain_id, email, phone, username, name,
		       password_hash, is_active, is_email_verified, is_phone_verified,
		       failed_login_attempts, locked_until, last_login_at, created_at, updated_at
		FROM auth.management_user
		WHERE id = $1 AND is_active = true
	`, id).Scan(
		&user.ID, &user.ChainID, &user.Email, &user.Phone,
		&user.Username, &user.Name, &user.PasswordHash,
		&user.IsActive, &user.IsEmailVerified, &user.IsPhoneVerified,
		&user.FailedLoginAttempts, &user.LockedUntil,
		&user.LastLoginAt, &user.CreatedAt, &user.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("user not found: %w", err)
	}
	return user, nil
}

func (r *UserRepository) GetByEmail(ctx context.Context, email string) (*model.ManagementUser, error) {
	user := &model.ManagementUser{}
	err := r.db.QueryRow(ctx, `
		SELECT id, chain_id, email, phone, username, name,
		       password_hash, is_active, is_email_verified, is_phone_verified,
		       failed_login_attempts, locked_until, last_login_at, created_at, updated_at
		FROM auth.management_user
		WHERE email = $1 AND is_active = true
	`, email).Scan(
		&user.ID, &user.ChainID, &user.Email, &user.Phone,
		&user.Username, &user.Name, &user.PasswordHash,
		&user.IsActive, &user.IsEmailVerified, &user.IsPhoneVerified,
		&user.FailedLoginAttempts, &user.LockedUntil,
		&user.LastLoginAt, &user.CreatedAt, &user.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("user not found: %w", err)
	}
	return user, nil
}

func (r *UserRepository) SetPassword(ctx context.Context, userID, passwordHash string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE auth.management_user
		SET password_hash = $1, updated_at = now()
		WHERE id = $2
	`, passwordHash, userID)
	if err != nil {
		return fmt.Errorf("failed to set password: %w", err)
	}
	return nil
}

func (r *UserRepository) IncrementFailedLogin(ctx context.Context, userID string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE auth.management_user
		SET failed_login_attempts = failed_login_attempts + 1, updated_at = now()
		WHERE id = $1
	`, userID)
	return err
}

func (r *UserRepository) ResetFailedLogin(ctx context.Context, userID string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE auth.management_user
		SET failed_login_attempts = 0, locked_until = NULL,
		    last_login_at = now(), updated_at = now()
		WHERE id = $1
	`, userID)
	return err
}
