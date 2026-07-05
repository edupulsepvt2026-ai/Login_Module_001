package repository

import (
	"context"
	"encoding/json"
	"fmt"

	"auth-service/internal/model"

	"github.com/jackc/pgx/v5/pgxpool"
)

// TeacherAuthRepository backs the teacher account activation flow
// (invite verify, onboarding master data, profile validation, account creation).
type TeacherAuthRepository struct{}

func NewTeacherAuthRepository() *TeacherAuthRepository {
	return &TeacherAuthRepository{}
}

// GetByTokenHash resolves a pending teacher invite. Filtering on
// target_role = 'teacher' is what stops a tenant_admin/chain_admin
// invite token from being replayed against this endpoint.
func (r *TeacherAuthRepository) GetByTokenHash(ctx context.Context, pool *pgxpool.Pool, tokenHash string) (*model.TenantInvite, error) {
	invite := &model.TenantInvite{}
	err := pool.QueryRow(ctx, `
		SELECT i.id, i.management_id, i.status_id,
		       i.invite_token_hash, i.name, i.email, i.phone,
		       i.expires_at, i.accepted_at, i.created_at
		FROM auth.invite i
		INNER JOIN auth.invite_status s ON s.id = i.status_id
		INNER JOIN auth.role r          ON r.id = i.target_role_id
		WHERE i.invite_token_hash = $1
		  AND s.name = 'pending'
		  AND r.name = 'teacher'
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

func (r *TeacherAuthRepository) getOptions(ctx context.Context, pool *pgxpool.Pool, table string) ([]model.MasterOption, error) {
	rows, err := pool.Query(ctx, fmt.Sprintf(`SELECT id::text, name FROM masters.%s ORDER BY name`, table))
	if err != nil {
		return nil, fmt.Errorf("failed to fetch %s: %w", table, err)
	}
	defer rows.Close()

	var options []model.MasterOption
	for rows.Next() {
		var o model.MasterOption
		if err := rows.Scan(&o.ID, &o.Name); err != nil {
			return nil, fmt.Errorf("failed to scan %s: %w", table, err)
		}
		options = append(options, o)
	}
	return options, nil
}

func (r *TeacherAuthRepository) GetGenders(ctx context.Context, pool *pgxpool.Pool) ([]model.MasterOption, error) {
	return r.getOptions(ctx, pool, "genders")
}

func (r *TeacherAuthRepository) GetQualifications(ctx context.Context, pool *pgxpool.Pool) ([]model.MasterOption, error) {
	return r.getOptions(ctx, pool, "qualifications")
}

func (r *TeacherAuthRepository) GetSubjects(ctx context.Context, pool *pgxpool.Pool) ([]model.MasterOption, error) {
	return r.getOptions(ctx, pool, "subjects")
}

func (r *TeacherAuthRepository) GetLanguages(ctx context.Context, pool *pgxpool.Pool) ([]model.MasterOption, error) {
	return r.getOptions(ctx, pool, "languages")
}

// GetClassesWithSections returns every class, each carrying the full section
// list. masters.sections has no class_id — sections are a flat, reusable set
// (A, B, C, ...) shared across every class, not scoped per class — so the
// same section list is attached to each class here.
func (r *TeacherAuthRepository) GetClassesWithSections(ctx context.Context, pool *pgxpool.Pool) ([]model.ClassOption, error) {
	// masters.classes has no sort_order column; approximate natural order by
	// pulling the trailing number out of the name ("Class 10" -> 10) so
	// Class 2 doesn't sort after Class 10. Non-numeric names (Nursery, LKG,
	// UKG) bucket first, then fall back to name.
	classRows, err := pool.Query(ctx, `
		SELECT id::text, name
		FROM masters.classes
		ORDER BY COALESCE(NULLIF(regexp_replace(name, '[^0-9]', '', 'g'), '')::int, -1), name
	`)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch classes: %w", err)
	}
	defer classRows.Close()

	var classes []model.ClassOption
	for classRows.Next() {
		var c model.ClassOption
		if err := classRows.Scan(&c.ID, &c.Name); err != nil {
			return nil, fmt.Errorf("failed to scan class: %w", err)
		}
		classes = append(classes, c)
	}

	sections, err := r.getOptions(ctx, pool, "sections")
	if err != nil {
		return nil, fmt.Errorf("failed to fetch sections: %w", err)
	}
	for i := range classes {
		classes[i].Sections = sections
	}

	return classes, nil
}

func (r *TeacherAuthRepository) ExistsPincode(ctx context.Context, pool *pgxpool.Pool, id string) (bool, error) {
	return r.exists(ctx, pool, "masters.pincodes", id)
}

func (r *TeacherAuthRepository) ExistsGender(ctx context.Context, pool *pgxpool.Pool, id string) (bool, error) {
	return r.exists(ctx, pool, "masters.genders", id)
}

func (r *TeacherAuthRepository) ExistsQualification(ctx context.Context, pool *pgxpool.Pool, id string) (bool, error) {
	return r.exists(ctx, pool, "masters.qualifications", id)
}

func (r *TeacherAuthRepository) exists(ctx context.Context, pool *pgxpool.Pool, table, id string) (bool, error) {
	var ok bool
	err := pool.QueryRow(ctx, fmt.Sprintf(`SELECT EXISTS(SELECT 1 FROM %s WHERE id = $1::uuid)`, table), id).Scan(&ok)
	if err != nil {
		return false, fmt.Errorf("failed to validate %s: %w", table, err)
	}
	return ok, nil
}

// CountSubjects returns how many of the given IDs actually exist in masters.subjects.
func (r *TeacherAuthRepository) CountSubjects(ctx context.Context, pool *pgxpool.Pool, ids []string) (int, error) {
	return r.countByIDs(ctx, pool, "masters.subjects", ids)
}

// CountLanguages returns how many of the given IDs actually exist in masters.languages.
func (r *TeacherAuthRepository) CountLanguages(ctx context.Context, pool *pgxpool.Pool, ids []string) (int, error) {
	return r.countByIDs(ctx, pool, "masters.languages", ids)
}

func (r *TeacherAuthRepository) countByIDs(ctx context.Context, pool *pgxpool.Pool, table string, ids []string) (int, error) {
	var count int
	err := pool.QueryRow(ctx, fmt.Sprintf(`SELECT COUNT(*) FROM %s WHERE id = ANY($1::uuid[])`, table), ids).Scan(&count)
	if err != nil {
		return 0, fmt.Errorf("failed to validate %s: %w", table, err)
	}
	return count, nil
}

// ValidateClassSections checks that every class_id and section_id referenced
// in the given pairs exists. masters.sections has no class_id column — a
// section isn't scoped to a particular class in this schema — so a "pair" is
// validated as two independent membership checks rather than a relational join.
func (r *TeacherAuthRepository) ValidateClassSections(ctx context.Context, pool *pgxpool.Pool, pairs []model.ClassSectionPair) (bool, error) {
	classIDSet := make(map[string]struct{}, len(pairs))
	sectionIDSet := make(map[string]struct{}, len(pairs))
	for _, p := range pairs {
		classIDSet[p.ClassID] = struct{}{}
		sectionIDSet[p.SectionID] = struct{}{}
	}

	classIDs := make([]string, 0, len(classIDSet))
	for id := range classIDSet {
		classIDs = append(classIDs, id)
	}
	sectionIDs := make([]string, 0, len(sectionIDSet))
	for id := range sectionIDSet {
		sectionIDs = append(sectionIDs, id)
	}

	validClasses, err := r.countByIDs(ctx, pool, "masters.classes", classIDs)
	if err != nil {
		return false, err
	}
	if validClasses != len(classIDs) {
		return false, nil
	}

	validSections, err := r.countByIDs(ctx, pool, "masters.sections", sectionIDs)
	if err != nil {
		return false, err
	}
	return validSections == len(sectionIDs), nil
}

// TeacherAccountInput carries the validated invite + profile fields
// needed to activate a teacher account in a single transaction.
type TeacherAccountInput struct {
	BranchID        string
	Name            string
	Email           *string
	Phone           *string
	PasswordHash    string
	Address         string
	AlternateMobile *string
	PincodeID       string
	GenderID        string
	QualificationID *string
	SubjectIDs      []string
	LanguageIDs     []string
	ClassSections   []model.ClassSectionPair
}

// CreateTeacherAccount inserts auth.user, teachers.teachers and its child
// tables, and the activation audit log entry in a single transaction — a
// partial teacher profile (e.g. subjects saved but sections not) is worse
// than no profile at all.
func (r *TeacherAuthRepository) CreateTeacherAccount(ctx context.Context, pool *pgxpool.Pool, in TeacherAccountInput) (string, error) {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return "", fmt.Errorf("failed to start transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	var newUserID string
	err = tx.QueryRow(ctx, `
		INSERT INTO auth."user" (
			role_id, management_type_id, management_id,
			name, email, phone, password_hash,
			is_email_verified, is_phone_verified, is_active, onboarding_channel
		) VALUES (
			(SELECT id FROM auth.role WHERE name = 'teacher'),
			(SELECT id FROM auth.management_type WHERE name = 'tenant'),
			$1, $2, $3, $4, $5,
			true, true, true, 'invite'
		) RETURNING id::text
	`, in.BranchID, in.Name, in.Email, in.Phone, in.PasswordHash).Scan(&newUserID)
	if err != nil {
		return "", fmt.Errorf("failed to create user: %w", err)
	}

	var newTeacherID string
	err = tx.QueryRow(ctx, `
		INSERT INTO teachers.teachers (
			user_id, name, alternate_mobile, address, pincode_id, gender_id, qualification_id
		) VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING id::text
	`, newUserID, in.Name, in.AlternateMobile, in.Address, in.PincodeID, in.GenderID, in.QualificationID).Scan(&newTeacherID)
	if err != nil {
		return "", fmt.Errorf("failed to create teacher profile: %w", err)
	}

	for _, subjectID := range in.SubjectIDs {
		if _, err := tx.Exec(ctx, `
			INSERT INTO teachers.teacher_subjects (teacher_id, subject_id) VALUES ($1, $2)
		`, newTeacherID, subjectID); err != nil {
			return "", fmt.Errorf("failed to link subject: %w", err)
		}
	}

	for _, languageID := range in.LanguageIDs {
		if _, err := tx.Exec(ctx, `
			INSERT INTO teachers.teacher_languages (teacher_id, language_id) VALUES ($1, $2)
		`, newTeacherID, languageID); err != nil {
			return "", fmt.Errorf("failed to link language: %w", err)
		}
	}

	for _, cs := range in.ClassSections {
		if _, err := tx.Exec(ctx, `
			INSERT INTO teachers.teacher_class_sections (teacher_id, class_id, section_id) VALUES ($1, $2, $3)
		`, newTeacherID, cs.ClassID, cs.SectionID); err != nil {
			return "", fmt.Errorf("failed to link class section: %w", err)
		}
	}

	metadata, err := json.Marshal(map[string]string{"role": "teacher", "branch_id": in.BranchID})
	if err != nil {
		return "", fmt.Errorf("failed to encode audit metadata: %w", err)
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO auth.audit_log (user_id, management_type_id, management_id, event_type_id, metadata)
		VALUES (
			$1,
			(SELECT id FROM auth.management_type WHERE name = 'tenant'),
			$2,
			(SELECT id FROM auth.audit_event_type WHERE name = 'password_created'),
			$3::jsonb
		)
	`, newUserID, in.BranchID, metadata); err != nil {
		return "", fmt.Errorf("failed to write audit log: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return "", fmt.Errorf("failed to commit transaction: %w", err)
	}
	return newUserID, nil
}
