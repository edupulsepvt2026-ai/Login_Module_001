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
	userID string,
	managementID string,
	email, phone *string,
	name, passwordHash string,
) error {

	var (
		managementTypeID string
		roleID           string
	)

	err := pool.QueryRow(
		ctx,
		`
		SELECT
			(SELECT id
			 FROM auth.management_type
			 WHERE LOWER(name) = 'chain'),
			(SELECT id
			 FROM auth.role
			 WHERE LOWER(name) = 'chain_admin')
		`,
	).Scan(&managementTypeID, &roleID)

	if err != nil {
		return fmt.Errorf("failed to get chain management type and role: %w", err)
	}

	_, err = pool.Exec(ctx, `
		INSERT INTO auth.user (
			id,
			role_id,
			management_type_id,
			management_id,
			email,
			phone,
			name,
			password_hash,
			is_email_verified,
			is_phone_verified,
			is_active,
			created_at,
			updated_at
		)
		VALUES (
			$1, $2, $3, $4, $5, $6, $7, $8,
			true, true, true,
			now(), now()
		)
	`,
		userID,
		roleID,
		managementTypeID,
		managementID,
		email,
		phone,
		name,
		passwordHash,
	)

	if err != nil {
		return fmt.Errorf("failed to create user: %w", err)
	}

	return nil
}

func (r *TenantUserRepository) CreateTenantAdmin(
	ctx context.Context,
	pool *pgxpool.Pool,
	userID, branchID string,
	email, phone *string,
	name, passwordHash string,
) error {
	_, err := pool.Exec(ctx, `
		INSERT INTO auth."user" (
			id,
			role_id,
			management_type_id,
			management_id,
			email,
			phone,
			name,
			password_hash,
			is_email_verified,
			is_phone_verified,
			is_active,
			onboarding_channel,
			created_at,
			updated_at
		) VALUES (
			$1,
			(SELECT id FROM auth.role            WHERE LOWER(name) = 'tenant_admin'),
			(SELECT id FROM auth.management_type WHERE LOWER(name) = 'tenant'),
			$2, $3, $4, $5, $6,
			true, true, true, 'invite',
			now(), now()
		)
	`, userID, branchID, email, phone, name, passwordHash)
	if err != nil {
		return fmt.Errorf("failed to create tenant admin user: %w", err)
	}
	return nil
}

func (r *TenantUserRepository) GetByID(ctx context.Context, pool *pgxpool.Pool, userID string) (*model.TenantUser, error) {
	user := &model.TenantUser{}
	err := pool.QueryRow(ctx, `
		SELECT
			u.id,
			CASE WHEN LOWER(mt.name) = 'chain' THEN u.management_id ELSE m.chain_id END AS chain_id,
			u.management_id,
			LOWER(r.name) AS role,
			u.email,
			u.phone,
			u.name,
			u.password_hash,
			u.is_active
		FROM auth."user" u
		JOIN auth.management_type mt ON u.management_type_id = mt.id
		JOIN auth.role r             ON u.role_id = r.id
		LEFT JOIN management.management_table m ON u.management_id = m.tenant_id
		WHERE u.id = $1
		  AND u.is_active = true
	`, userID).Scan(
		&user.ID, &user.ChainID, &user.ManagementID, &user.Role,
		&user.Email, &user.Phone, &user.Name, &user.PasswordHash, &user.IsActive,
	)
	if err != nil {
		return nil, fmt.Errorf("tenant user not found: %w", err)
	}
	return user, nil
}
