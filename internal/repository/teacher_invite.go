package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type TeacherInviteRepository struct{}

func NewTeacherInviteRepository() *TeacherInviteRepository {
	return &TeacherInviteRepository{}
}

func (r *TeacherInviteRepository) Create(
	ctx context.Context,
	pool *pgxpool.Pool,
	invitedByUserID, branchID, name, tokenHash string,
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
			invite_token_hash,
			name,
			email,
			phone,
			expires_at,
			created_at
		) VALUES (
			$1::uuid,
			(SELECT id FROM auth.management_type WHERE name = 'tenant'),
			$2::uuid,
			(SELECT id FROM auth.role WHERE name = 'teacher'),
			(SELECT id FROM auth.invite_status WHERE name = 'pending'),
			$3, $4, $5, $6, $7, now()
		) RETURNING id::text
	`, invitedByUserID, branchID, tokenHash, name, email, phone, expiresAt).Scan(&inviteID)
	if err != nil {
		return "", fmt.Errorf("failed to create teacher invite: %w", err)
	}
	return inviteID, nil
}
