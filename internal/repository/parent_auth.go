package repository

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ParentAuthRepository backs the parent account activation flow
// (docs/API_V4.0_PARENT_ONBOARDING.md § Phase 5).
type ParentAuthRepository struct{}

func NewParentAuthRepository() *ParentAuthRepository {
	return &ParentAuthRepository{}
}

// InviteWithStudent is a pending parent invite joined with the one student
// it was created for (parents.invite_student is UNIQUE(invite_id) — one
// invite always covers exactly one student).
type InviteWithStudent struct {
	InviteID           string
	BranchID           string
	ParentName         string
	ParentEmail        *string
	ParentPhone        *string
	StudentID          string
	StudentName        string
	ClassName          *string
	SectionName        *string
	RelationshipTypeID string
	RelationshipName   *string
}

// GetInviteWithStudent resolves a pending parent invite by its raw token
// hash. Filtering on target_role = 'parent' is what stops a
// teacher/tenant_admin/chain_admin invite token from being replayed here.
func (r *ParentAuthRepository) GetInviteWithStudent(ctx context.Context, pool *pgxpool.Pool, tokenHash string) (*InviteWithStudent, error) {
	row := &InviteWithStudent{}
	err := pool.QueryRow(ctx, `
		SELECT i.id::text, i.management_id::text, i.name, i.email, i.phone,
		       ist.student_id::text, ist.relationship_type_id::text,
		       st.name,
		       c.name, sec.name, rt.name
		FROM auth.invite i
		INNER JOIN auth.invite_status invstatus ON invstatus.id = i.status_id
		INNER JOIN auth.role role_lookup        ON role_lookup.id = i.target_role_id
		INNER JOIN parents.invite_student ist   ON ist.invite_id = i.id
		INNER JOIN parents.student st           ON st.id = ist.student_id
		LEFT JOIN parents.student_enrollment se ON se.student_id = st.id
		LEFT JOIN masters.classes c              ON c.id = se.class_id
		LEFT JOIN masters.sections sec           ON sec.id = se.section_id
		LEFT JOIN masters.relationship_type rt   ON rt.id = ist.relationship_type_id
		WHERE i.invite_token_hash = $1
		  AND invstatus.name = 'pending'
		  AND role_lookup.name = 'parent'
		  AND i.expires_at > now()
	`, tokenHash).Scan(
		&row.InviteID, &row.BranchID, &row.ParentName, &row.ParentEmail, &row.ParentPhone,
		&row.StudentID, &row.RelationshipTypeID,
		&row.StudentName, &row.ClassName, &row.SectionName, &row.RelationshipName,
	)
	if err != nil {
		return nil, fmt.Errorf("invite not found: %w", err)
	}
	return row, nil
}
