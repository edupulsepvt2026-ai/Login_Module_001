package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

type ChainMappingRepository struct {
	db *pgxpool.Pool
}

type ChainMappingResult struct {
	UserID  string
	ChainID string
	Role    string
}

func NewChainMappingRepository(db *pgxpool.Pool) *ChainMappingRepository {
	return &ChainMappingRepository{db: db}
}

func (r *ChainMappingRepository) Create(ctx context.Context, userID, role, chainID string, email, phone *string) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO auth.chain_user_mapping
			(user_id, role, chain_id, chain_db_id, email, phone, is_active, created_at)
		VALUES (
			$1, $2, $3,
			(SELECT id FROM infrastructure.chain_database WHERE chain_id = $3 AND is_active = true LIMIT 1),
			$4, $5, true, now()
		)
	`, userID, role, chainID, email, phone)
	if err != nil {
		return fmt.Errorf("failed to create chain user mapping: %w", err)
	}
	return nil
}

// GetByEmail looks up the routing info for a given email at login.
func (r *ChainMappingRepository) GetByEmail(ctx context.Context, email string) (*ChainMappingResult, error) {
	result := &ChainMappingResult{}
	err := r.db.QueryRow(ctx, `
		SELECT user_id::text, chain_id::text, role
		FROM auth.chain_user_mapping
		WHERE email = $1 AND is_active = true
		LIMIT 1
	`, email).Scan(&result.UserID, &result.ChainID, &result.Role)
	if err != nil {
		return nil, fmt.Errorf("user not found: %w", err)
	}
	return result, nil
}

// GetByUserID looks up the routing info for a given user_id.
// Used during token refresh to determine role and chain.
func (r *ChainMappingRepository) GetByUserID(ctx context.Context, userID string) (*ChainMappingResult, error) {
	result := &ChainMappingResult{}
	err := r.db.QueryRow(ctx, `
		SELECT user_id::text, chain_id::text, role
		FROM auth.chain_user_mapping
		WHERE user_id = $1::uuid AND is_active = true
		LIMIT 1
	`, userID).Scan(&result.UserID, &result.ChainID, &result.Role)
	if err != nil {
		return nil, fmt.Errorf("user not found: %w", err)
	}
	return result, nil
}
