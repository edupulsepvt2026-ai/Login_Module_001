package repository

import (
	"context"
	"fmt"
	"time"

	"auth-service/internal/model"

	"github.com/jackc/pgx/v5/pgxpool"
)

type ChainAdminRepository struct{}

func NewChainAdminRepository() *ChainAdminRepository {
	return &ChainAdminRepository{}
}

// GetChainName returns the name of the chain from management.chain.
func (r *ChainAdminRepository) GetChainName(ctx context.Context, pool *pgxpool.Pool, chainID string) (string, error) {
	var name string
	err := pool.QueryRow(ctx, `
		SELECT name FROM management.chain WHERE id = $1
	`, chainID).Scan(&name)
	if err != nil {
		return "", fmt.Errorf("chain not found: %w", err)
	}
	return name, nil
}

// GetBranches returns all active branches for the chain with a flag indicating
// whether each branch already has an active tenant_admin.
func (r *ChainAdminRepository) GetBranches(ctx context.Context, pool *pgxpool.Pool, chainID string) ([]model.BranchWithAdminFlag, error) {
	rows, err := pool.Query(ctx, `
		SELECT
			m.tenant_id,
			m.branch_name,
			COALESCE(m.branch_city, ''),
			COALESCE(m.branch_state, ''),
			EXISTS (
				SELECT 1
				FROM auth."user" u
				JOIN auth.role ro ON u.role_id = ro.id
				WHERE u.management_id = m.tenant_id
				  AND ro.name = 'tenant_admin'
				  AND u.is_active = true
			) AS has_tenant_admin
		FROM management.management_table m
		WHERE m.chain_id = $1
		  AND m.is_active = true
		ORDER BY m.branch_name
	`, chainID)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch branches: %w", err)
	}
	defer rows.Close()

	var branches []model.BranchWithAdminFlag
	for rows.Next() {
		var b model.BranchWithAdminFlag
		if err := rows.Scan(&b.TenantID, &b.Name, &b.City, &b.State, &b.HasTenantAdmin); err != nil {
			return nil, fmt.Errorf("failed to scan branch: %w", err)
		}
		branches = append(branches, b)
	}
	return branches, nil
}

// GetBranchByTenantID fetches a branch row and verifies it belongs to the given chain.
// Returns an error if the branch does not exist or belongs to a different chain.
func (r *ChainAdminRepository) GetBranchByTenantID(ctx context.Context, pool *pgxpool.Pool, tenantID, chainID string) (*model.TenantBranch, error) {
	var b model.TenantBranch
	err := pool.QueryRow(ctx, `
		SELECT tenant_id, chain_name, branch_name
		FROM management.management_table
		WHERE tenant_id = $1
		  AND chain_id  = $2
		  AND is_active = true
	`, tenantID, chainID).Scan(&b.TenantID, &b.ChainName, &b.BranchName)
	if err != nil {
		return nil, fmt.Errorf("branch not found: %w", err)
	}
	return &b, nil
}

// HasActiveTenantAdmin checks whether an active tenant_admin user already exists
// for the given tenant (branch).
func (r *ChainAdminRepository) HasActiveTenantAdmin(ctx context.Context, pool *pgxpool.Pool, tenantID string) (bool, error) {
	var exists bool
	err := pool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1
			FROM auth."user" u
			JOIN auth.role ro ON u.role_id = ro.id
			WHERE u.management_id = $1
			  AND ro.name = 'tenant_admin'
			  AND u.is_active = true
		)
	`, tenantID).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("failed to check tenant admin existence: %w", err)
	}
	return exists, nil
}

// CreateInvite inserts an invite record into auth.invite.
// Returns the generated invite UUID.
func (r *ChainAdminRepository) CreateInvite(
	ctx context.Context,
	pool *pgxpool.Pool,
	invitedByUserID, tenantID, name, tokenHash string,
	email, phone *string,
	expiresAt time.Time,
) (string, error) {
	var inviteID string
	err := pool.QueryRow(ctx, `
		INSERT INTO auth.invite (
			invited_by_user_id,
			management_type_id,
			management_id,
			target_role_id,
			status_id,
			name,
			email,
			phone,
			invite_token_hash,
			expires_at,
			created_at
		) VALUES (
			$1,
			(SELECT id FROM auth.management_type  WHERE name = 'tenant'),
			$2,
			(SELECT id FROM auth.role             WHERE name = 'tenant_admin'),
			(SELECT id FROM auth.invite_status    WHERE name = 'pending'),
			$3, $4, $5, $6, $7,
			now()
		)
		RETURNING id
	`, invitedByUserID, tenantID, name, email, phone, tokenHash, expiresAt).Scan(&inviteID)
	if err != nil {
		return "", fmt.Errorf("failed to create invite: %w", err)
	}
	return inviteID, nil
}

// InsertAuditLog writes an invite_sent audit event scoped to the chain.
func (r *ChainAdminRepository) InsertAuditLog(ctx context.Context, pool *pgxpool.Pool, userID, chainID, tenantID string) error {
	_, err := pool.Exec(ctx, `
		INSERT INTO auth.audit_log (
			user_id,
			management_type_id,
			management_id,
			event_type_id,
			metadata,
			is_suspicious,
			created_at
		) VALUES (
			$1,
			(SELECT id FROM auth.management_type     WHERE name = 'chain'),
			$2,
			(SELECT id FROM auth.audit_event_type    WHERE name = 'invite_sent'),
			jsonb_build_object('target_role', 'tenant_admin', 'branch_id', $3),
			false,
			now()
		)
	`, userID, chainID, tenantID)
	if err != nil {
		return fmt.Errorf("failed to insert audit log: %w", err)
	}
	return nil
}
