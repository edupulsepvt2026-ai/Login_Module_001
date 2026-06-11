package repository

import (
	"context"
	"fmt"
	"time"

	"auth-service/internal/model"

	"github.com/jackc/pgx/v5/pgxpool"
)

type SessionRepository struct {
	db *pgxpool.Pool
}

func NewSessionRepository(db *pgxpool.Pool) *SessionRepository {
	return &SessionRepository{db: db}
}

func (r *SessionRepository) Create(ctx context.Context, userID, accessHash, refreshHash string, accessExp, refreshExp time.Time) (*model.Session, error) {
	session := &model.Session{}
	err := r.db.QueryRow(ctx, `
		INSERT INTO auth.session (user_id, access_token_hash, refresh_token_hash, access_token_expires_at, refresh_token_expires_at)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id, user_id, access_token_hash, refresh_token_hash,
		          access_token_expires_at, refresh_token_expires_at, created_at
	`, userID, accessHash, refreshHash, accessExp, refreshExp).Scan(
		&session.ID,
		&session.UserID,
		&session.AccessTokenHash,
		&session.RefreshTokenHash,
		&session.AccessTokenExpiresAt,
		&session.RefreshTokenExpiresAt,
		&session.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create session: %w", err)
	}
	return session, nil
}

func (r *SessionRepository) GetByRefreshHash(ctx context.Context, refreshHash string) (*model.Session, error) {
	session := &model.Session{}
	err := r.db.QueryRow(ctx, `
		SELECT id, user_id, access_token_hash, refresh_token_hash,
		       access_token_expires_at, refresh_token_expires_at, revoked_at, created_at
		FROM auth.session
		WHERE refresh_token_hash = $1
		  AND revoked_at IS NULL
		  AND refresh_token_expires_at > now()
	`, refreshHash).Scan(
		&session.ID,
		&session.UserID,
		&session.AccessTokenHash,
		&session.RefreshTokenHash,
		&session.AccessTokenExpiresAt,
		&session.RefreshTokenExpiresAt,
		&session.RevokedAt,
		&session.CreatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("session not found: %w", err)
	}
	return session, nil
}

func (r *SessionRepository) Revoke(ctx context.Context, sessionID string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE auth.session SET revoked_at = now() WHERE id = $1
	`, sessionID)
	if err != nil {
		return fmt.Errorf("failed to revoke session: %w", err)
	}
	return nil
}

func (r *SessionRepository) RevokeByAccessHash(ctx context.Context, accessHash string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE auth.session SET revoked_at = now() WHERE access_token_hash = $1
	`, accessHash)
	return err
}
