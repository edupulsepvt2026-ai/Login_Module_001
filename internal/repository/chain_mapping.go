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
}

func NewChainMappingRepository(db *pgxpool.Pool) *ChainMappingRepository {
	return &ChainMappingRepository{db: db}
}

// Create inserts a row into auth.chain_user_mapping.
// chain_db_id is resolved inline from infrastructure.chain_database.
func (r *ChainMappingRepository) Create(ctx context.Context, userID, chainID string, email, phone *string) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO auth.chain_user_mapping
			(user_id, role, chain_id, chain_db_id, email, phone, is_active, created_at)
		VALUES (
			$1, 'chain_admin', $2,
			(SELECT id FROM infrastructure.chain_database WHERE chain_id = $2 AND is_active = true LIMIT 1),
			$3, $4, true, now()
		)
	`, userID, chainID, email, phone)
	if err != nil {
		return fmt.Errorf("failed to create chain user mapping: %w", err)
	}
	return nil
}

// GetByEmail looks up the user_id and chain_id for a given email.
// Used at login to route the request to the correct tenant DB.
func (r *ChainMappingRepository) GetByEmail(ctx context.Context, email string) (*ChainMappingResult, error) {
	result := &ChainMappingResult{}
	err := r.db.QueryRow(ctx, `
		SELECT user_id::text, chain_id::text
		FROM auth.chain_user_mapping
		WHERE email = $1 AND is_active = true
		LIMIT 1
	`, email).Scan(&result.UserID, &result.ChainID)
	if err != nil {
		return nil, fmt.Errorf("user not found: %w", err)
	}
	return result, nil
}
