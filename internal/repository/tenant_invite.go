package repository

import (
	"context"
	"fmt"

	"auth-service/internal/model"

	"github.com/jackc/pgx/v5/pgxpool"
)

type TenantInviteRepository struct{}

func NewTenantInviteRepository() *TenantInviteRepository {
	return &TenantInviteRepository{}
}

func (r *TenantInviteRepository) GetByTokenHash(ctx context.Context, pool *pgxpool.Pool, tokenHash string) (*model.TenantInvite, error) {
	invite := &model.TenantInvite{}
	err := pool.QueryRow(ctx, `
		SELECT i.id, i.management_id, i.status_id,
		       i.invite_token_hash, i.name, i.email, i.phone,
		       i.expires_at, i.accepted_at, i.created_at
		FROM auth.invite i
		INNER JOIN auth.invite_status s ON s.id = i.status_id
		WHERE i.invite_token_hash = $1
		  AND s.name = 'pending'
		  AND i.expires_at > now()
	`, tokenHash).Scan(
		&invite.ID,
		&invite.ManagementID,
		&invite.StatusID,
		&invite.InviteTokenHash,
		&invite.Name,
		&invite.Email,
		&invite.Phone,
		&invite.ExpiresAt,
		&invite.AcceptedAt,
		&invite.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("invite not found: %w", err)
	}
	return invite, nil
}

func (r *TenantInviteRepository) MarkAccepted(ctx context.Context, pool *pgxpool.Pool, inviteID string) error {
	_, err := pool.Exec(ctx, `
		UPDATE auth.invite
		SET status_id   = (SELECT id FROM auth.invite_status WHERE name = 'accepted'),
		    accepted_at = now()
		WHERE id = $1
	`, inviteID)
	if err != nil {
		return fmt.Errorf("failed to mark invite accepted: %w", err)
	}
	return nil
}

func (r *TenantInviteRepository) GetBranchInfo(ctx context.Context, pool *pgxpool.Pool, tenantID, chainID string) (*model.BranchInfo, error) {
	info := &model.BranchInfo{}
	err := pool.QueryRow(ctx, `
		SELECT tenant_id::text, branch_name, branch_city, branch_state
		FROM management.management_table
		WHERE tenant_id = $1::uuid
		  AND chain_id  = $2::uuid
	`, tenantID, chainID).Scan(&info.ID, &info.Name, &info.City, &info.State)
	if err != nil {
		return nil, fmt.Errorf("branch not found: %w", err)
	}
	return info, nil
}

func (r *TenantInviteRepository) GetChainName(ctx context.Context, pool *pgxpool.Pool, chainID string) (string, error) {
	var name string
	err := pool.QueryRow(ctx, `
		SELECT name FROM management.chain WHERE id = $1::uuid
	`, chainID).Scan(&name)
	if err != nil {
		return "", fmt.Errorf("chain not found: %w", err)
	}
	return name, nil
}
