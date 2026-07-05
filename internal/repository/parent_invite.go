package repository

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ParentInviteRepository backs the teacher-initiated parent invite flow
// (docs/API_V4.0_PARENT_ONBOARDING.md § Phase 4).
type ParentInviteRepository struct{}

func NewParentInviteRepository() *ParentInviteRepository {
	return &ParentInviteRepository{}
}

func (r *ParentInviteRepository) ExistsClass(ctx context.Context, pool *pgxpool.Pool, id string) (bool, error) {
	return existsByID(ctx, pool, "masters.classes", id)
}

func (r *ParentInviteRepository) ExistsSection(ctx context.Context, pool *pgxpool.Pool, id string) (bool, error) {
	return existsByID(ctx, pool, "masters.sections", id)
}

func (r *ParentInviteRepository) ExistsRelationshipType(ctx context.Context, pool *pgxpool.Pool, id string) (bool, error) {
	return existsByID(ctx, pool, "masters.relationship_type", id)
}

func (r *ParentInviteRepository) GetClassIDByName(ctx context.Context, pool *pgxpool.Pool, name string) (string, bool, error) {
	return getIDByName(ctx, pool, "masters.classes", name)
}

func (r *ParentInviteRepository) GetSectionIDByName(ctx context.Context, pool *pgxpool.Pool, name string) (string, bool, error) {
	return getIDByName(ctx, pool, "masters.sections", name)
}

func (r *ParentInviteRepository) GetRelationshipTypeIDByName(ctx context.Context, pool *pgxpool.Pool, name string) (string, bool, error) {
	return getIDByName(ctx, pool, "masters.relationship_type", name)
}

// CreateStudent inserts a minimal parents.student row — only what the
// teacher knows at invite time. Remaining profile fields (DOB, gender,
// blood group, previous school) are collected from the parent later.
func (r *ParentInviteRepository) CreateStudent(ctx context.Context, pool *pgxpool.Pool, tenantID, name string) (string, error) {
	var studentID string
	err := pool.QueryRow(ctx, `
		INSERT INTO parents.student (tenant_id, name)
		VALUES ($1, $2)
		RETURNING id::text
	`, tenantID, name).Scan(&studentID)
	if err != nil {
		return "", fmt.Errorf("failed to create student: %w", err)
	}
	return studentID, nil
}

// CreateStudentEnrollment records the student's class/section for the
// current academic year — see the "flat classes + year on the fact row"
// design in docs/API_V4.0_PARENT_ONBOARDING.md.
func (r *ParentInviteRepository) CreateStudentEnrollment(ctx context.Context, pool *pgxpool.Pool, studentID, classID, sectionID, academicYear string) error {
	_, err := pool.Exec(ctx, `
		INSERT INTO parents.student_enrollment (student_id, class_id, section_id, academic_year, status)
		VALUES ($1, $2, $3, $4, 'active')
	`, studentID, classID, sectionID, academicYear)
	if err != nil {
		return fmt.Errorf("failed to create student enrollment: %w", err)
	}
	return nil
}

// FindActiveParentUserIDByContact looks for an already-activated parent
// account with a matching email or phone — the "second child, same
// parent" case where no new invite should be sent.
func (r *ParentInviteRepository) FindActiveParentUserIDByContact(ctx context.Context, pool *pgxpool.Pool, email, phone *string) (string, bool, error) {
	var userID string
	err := pool.QueryRow(ctx, `
		SELECT u.id::text
		FROM auth."user" u
		INNER JOIN auth.role r ON r.id = u.role_id
		WHERE r.name = 'parent'
		  AND u.is_active = true
		  AND ((u.email IS NOT NULL AND u.email = $1) OR (u.phone IS NOT NULL AND u.phone = $2))
		LIMIT 1
	`, email, phone).Scan(&userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, fmt.Errorf("failed to look up existing parent: %w", err)
	}
	return userID, true, nil
}

func (r *ParentInviteRepository) GetParentIDByUserID(ctx context.Context, pool *pgxpool.Pool, userID string) (string, error) {
	var parentID string
	err := pool.QueryRow(ctx, `SELECT id::text FROM parents.parent WHERE user_id = $1::uuid`, userID).Scan(&parentID)
	if err != nil {
		return "", fmt.Errorf("parent profile not found: %w", err)
	}
	return parentID, nil
}

// LinkStudentToExistingParent attaches a new child to an already-active
// parent account — no invite/OTP/password step needed.
func (r *ParentInviteRepository) LinkStudentToExistingParent(ctx context.Context, pool *pgxpool.Pool, parentID, studentID, relationshipTypeID string) error {
	_, err := pool.Exec(ctx, `
		INSERT INTO parents.parent_student (parent_id, student_id, relationship_type_id)
		VALUES ($1, $2, $3)
	`, parentID, studentID, relationshipTypeID)
	if err != nil {
		return fmt.Errorf("failed to link student to existing parent: %w", err)
	}
	return nil
}

// CreateInvite inserts a new auth.invite row with target_role='parent'.
func (r *ParentInviteRepository) CreateInvite(
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
			(SELECT id FROM auth.role WHERE name = 'parent'),
			(SELECT id FROM auth.invite_status WHERE name = 'pending'),
			$3, $4, $5, $6, $7, now()
		) RETURNING id::text
	`, invitedByUserID, branchID, tokenHash, name, email, phone, expiresAt).Scan(&inviteID)
	if err != nil {
		return "", fmt.Errorf("failed to create parent invite: %w", err)
	}
	return inviteID, nil
}

// AddInviteStudent links a student to a parent invite, with the
// relationship the invited parent has to that specific child.
func (r *ParentInviteRepository) AddInviteStudent(ctx context.Context, pool *pgxpool.Pool, inviteID, studentID, relationshipTypeID string) error {
	_, err := pool.Exec(ctx, `
		INSERT INTO parents.invite_student (invite_id, student_id, relationship_type_id)
		VALUES ($1, $2, $3)
	`, inviteID, studentID, relationshipTypeID)
	if err != nil {
		return fmt.Errorf("failed to link invite to student: %w", err)
	}
	return nil
}
