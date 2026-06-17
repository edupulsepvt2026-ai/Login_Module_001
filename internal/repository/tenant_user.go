package repository

import (
	"context"
	"fmt"

	"auth-service/internal/model"

	"github.com/jackc/pgx/v5/pgxpool"
)

// TenantUserRepository operates on the tenant DB's auth.user table.
// The pool is passed per-call because it differs for each chain's DB.
type TenantUserRepository struct{}

func NewTenantUserRepository() *TenantUserRepository {
	return &TenantUserRepository{}
}

func (r *TenantUserRepository) Create(
	ctx context.Context,
	pool *pgxpool.Pool,
	userID, chainID string,
	email, phone *string,
	name, passwordHash string,
) error {
	_, err := pool.Exec(ctx, `
		INSERT INTO auth.user (
			id, chain_id, email, phone, name, password_hash,
			is_email_verified, is_phone_verified, is_active, created_at, updated_at
		) VALUES ($1, $2, $3, $4, $5, $6, true, true, true, now(), now())
	`, userID, chainID, email, phone, name, passwordHash)
	if err != nil {
		return fmt.Errorf("failed to create tenant user: %w", err)
	}
	return nil
}

func (r *TenantUserRepository) GetByID(ctx context.Context, pool *pgxpool.Pool, userID string) (*model.TenantUser, error) {
	user := &model.TenantUser{}
	err := pool.QueryRow(ctx, `
		SELECT id, chain_id, email, phone, name, password_hash, is_active
		FROM auth.user
		WHERE id = $1 AND is_active = true
	`, userID).Scan(
		&user.ID, &user.ChainID, &user.Email, &user.Phone,
		&user.Name, &user.PasswordHash, &user.IsActive,
	)
	if err != nil {
		return nil, fmt.Errorf("tenant user not found: %w", err)
	}
	return user, nil
}
