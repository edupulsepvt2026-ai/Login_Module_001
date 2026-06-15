package repository

import (
	"context"
	"fmt"

	"auth-service/internal/model"

	"github.com/jackc/pgx/v5/pgxpool"
)

type InviteRepository struct {
	db *pgxpool.Pool
}

func NewInviteRepository(db *pgxpool.Pool) *InviteRepository {
	return &InviteRepository{db: db}
}

func (r *InviteRepository) GetByTokenHash(ctx context.Context, tokenHash string) (*model.Invite, error) {
	invite := &model.Invite{}
	err := r.db.QueryRow(ctx, `
		SELECT i.id, i.management_user_id, i.status_id,
		       i.invite_token_hash, i.resend_count,
		       i.expires_at, i.accepted_at, i.created_at
		FROM auth.invite i
		INNER JOIN auth.invite_status s ON s.id = i.status_id
		WHERE i.invite_token_hash = $1
		  AND s.name = 'pending'
	`, tokenHash).Scan(
		&invite.ID,
		&invite.ManagementUserID,
		&invite.StatusID,
		&invite.InviteTokenHash,
		&invite.ResendCount,
		&invite.ExpiresAt,
		&invite.AcceptedAt,
		&invite.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("invite not found: %w", err)
	}
	return invite, nil
}

func (r *InviteRepository) MarkAccepted(ctx context.Context, inviteID string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE auth.invite
		SET status_id = (SELECT id FROM auth.invite_status WHERE name = 'accepted'),
		    accepted_at = now()
		WHERE id = $1
	`, inviteID)
	if err != nil {
		return fmt.Errorf("failed to mark invite accepted: %w", err)
	}
	return nil
}

func (r *InviteRepository) RevokeAllPending(ctx context.Context, managementUserID string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE auth.invite
		SET status_id = (SELECT id FROM auth.invite_status WHERE name = 'revoked')
		WHERE management_user_id = $1
		  AND accepted_at IS NULL
		  AND expires_at > now()
	`, managementUserID)
	if err != nil {
		return fmt.Errorf("failed to revoke pending invites: %w", err)
	}
	return nil
}

func (r *InviteRepository) GetChainByID(ctx context.Context, chainID string) (*model.Chain, error) {
	chain := &model.Chain{}
	err := r.db.QueryRow(ctx, `
		SELECT id, name
		FROM onboarding.chain
		WHERE id = $1
	`, chainID).Scan(&chain.ID, &chain.Name)
	if err != nil {
		return nil, fmt.Errorf("chain not found: %w", err)
	}
	return chain, nil
}

func (r *InviteRepository) GetBranchesByChainID(ctx context.Context, chainID string) ([]model.Branch, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, name, city, state, board_type
		FROM onboarding.branch
		WHERE chain_id = $1
		ORDER BY name
	`, chainID)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch branches: %w", err)
	}
	defer rows.Close()

	var branches []model.Branch
	for rows.Next() {
		var b model.Branch
		if err := rows.Scan(&b.ID, &b.Name, &b.City, &b.State, &b.BoardType); err != nil {
			return nil, fmt.Errorf("failed to scan branch: %w", err)
		}
		branches = append(branches, b)
	}
	return branches, nil
}
