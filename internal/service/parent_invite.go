package service

import (
	"context"
	"fmt"
	"log"
	"time"

	"auth-service/internal/repository"
	"auth-service/pkg/crypto"
	"auth-service/pkg/notify"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ParentInviteInput is a single invite request with masters.* ids already
// resolved (used by the JSON single-invite endpoint).
type ParentInviteInput struct {
	StudentName        string
	ClassID            string
	SectionID          string
	ParentName         string
	ParentEmail        *string
	ParentPhone        *string
	RelationshipTypeID string
}

// ParentInviteRawInput is a single row from a bulk CSV/Excel upload, where
// class/section/relationship are human-readable names, not ids.
type ParentInviteRawInput struct {
	StudentName string
	Class       string
	// Grade is the section label (e.g. "A") despite the name — see
	// docs/API_V4.0_PARENT_ONBOARDING.md § What the teacher fills in.
	Grade            string
	ParentName       string
	ParentEmail      *string
	ParentPhone      *string
	RelationshipType string
}

type ParentInviteResult struct {
	// Status is one of "invited", "linked_to_existing_parent".
	Status          string
	InviteID        string
	StudentID       string
	ParentName      string
	DeliveryChannel string
}

type BulkParentInviteResult struct {
	Sent   []ParentInviteResult
	Failed []BulkParentInviteError
}

type BulkParentInviteError struct {
	Row         int
	StudentName string
	Error       string
}

type ParentInviteService struct {
	repo          *repository.ParentInviteRepository
	notifier      *notify.Client
	inviteBaseURL string
}

func NewParentInviteService(repo *repository.ParentInviteRepository, notifier *notify.Client, inviteBaseURL string) *ParentInviteService {
	return &ParentInviteService{repo: repo, notifier: notifier, inviteBaseURL: inviteBaseURL}
}

// InviteSingle creates the student + enrollment for exactly one child, then
// either links that student directly to an already-active parent account
// (no invite needed — see docs/API_V4.0_PARENT_ONBOARDING.md), or sends a
// brand-new invite. One invite always covers exactly one student.
func (s *ParentInviteService) InviteSingle(
	ctx context.Context,
	pool *pgxpool.Pool,
	invitedByUserID, chainID, branchID, academicYear string,
	input ParentInviteInput,
) (*ParentInviteResult, error) {
	if input.StudentName == "" {
		return nil, fmt.Errorf("student_name is required")
	}
	if (input.ParentEmail == nil || *input.ParentEmail == "") && (input.ParentPhone == nil || *input.ParentPhone == "") {
		return nil, fmt.Errorf("parent email or mobile is required")
	}
	if ok, err := s.repo.ExistsClass(ctx, pool, input.ClassID); err != nil {
		return nil, err
	} else if !ok {
		return nil, fmt.Errorf("invalid class_id")
	}
	if ok, err := s.repo.ExistsSection(ctx, pool, input.SectionID); err != nil {
		return nil, err
	} else if !ok {
		return nil, fmt.Errorf("invalid section_id")
	}
	if ok, err := s.repo.ExistsRelationshipType(ctx, pool, input.RelationshipTypeID); err != nil {
		return nil, err
	} else if !ok {
		return nil, fmt.Errorf("invalid relationship_type_id")
	}

	studentID, err := s.repo.CreateStudent(ctx, pool, branchID, input.StudentName)
	if err != nil {
		return nil, fmt.Errorf("failed to create student: %w", err)
	}
	if err := s.repo.CreateStudentEnrollment(ctx, pool, studentID, input.ClassID, input.SectionID, academicYear); err != nil {
		return nil, fmt.Errorf("failed to create student enrollment: %w", err)
	}

	if userID, found, err := s.repo.FindActiveParentUserIDByContact(ctx, pool, input.ParentEmail, input.ParentPhone); err != nil {
		return nil, err
	} else if found {
		parentID, err := s.repo.GetParentIDByUserID(ctx, pool, userID)
		if err != nil {
			return nil, err
		}
		if err := s.repo.LinkStudentToExistingParent(ctx, pool, parentID, studentID, input.RelationshipTypeID); err != nil {
			return nil, err
		}
		log.Printf("[ParentInvite] linked new student to existing parent: parent_id=%s student_id=%s", parentID, studentID)
		return &ParentInviteResult{Status: "linked_to_existing_parent", StudentID: studentID, ParentName: input.ParentName}, nil
	}

	rawToken, err := crypto.GenerateToken(32)
	if err != nil {
		return nil, fmt.Errorf("failed to generate invite token")
	}
	tokenHash := crypto.SHA256(rawToken)
	expiresAt := time.Now().Add(48 * time.Hour)

	inviteID, err := s.repo.CreateInvite(ctx, pool, invitedByUserID, branchID, input.ParentName, tokenHash, input.ParentEmail, input.ParentPhone, expiresAt)
	if err != nil {
		return nil, fmt.Errorf("failed to create invite: %w", err)
	}
	if err := s.repo.AddInviteStudent(ctx, pool, inviteID, studentID, input.RelationshipTypeID); err != nil {
		return nil, err
	}

	inviteLink := fmt.Sprintf("%s?token=%s&chain_id=%s", s.inviteBaseURL, rawToken, chainID)
	log.Printf("[DEV] parent raw invite token: %s", rawToken)

	channel, err := s.sendNotification(ctx, input, inviteLink)
	if err != nil {
		log.Printf("[ParentInvite] notification failed: invite_id=%s parent_name=%s — %v", inviteID, input.ParentName, err)
		return nil, fmt.Errorf("invite created but notification failed: %w", err)
	}

	return &ParentInviteResult{Status: "invited", InviteID: inviteID, StudentID: studentID, ParentName: input.ParentName, DeliveryChannel: channel}, nil
}

// InviteSingleByName resolves class/section/relationship names to ids
// (bulk upload path — the template uses human-readable columns) then
// delegates to InviteSingle.
func (s *ParentInviteService) InviteSingleByName(
	ctx context.Context,
	pool *pgxpool.Pool,
	invitedByUserID, chainID, branchID, academicYear string,
	raw ParentInviteRawInput,
) (*ParentInviteResult, error) {
	classID, ok, err := s.repo.GetClassIDByName(ctx, pool, raw.Class)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, fmt.Errorf("unknown class %q", raw.Class)
	}

	sectionID, ok, err := s.repo.GetSectionIDByName(ctx, pool, raw.Grade)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, fmt.Errorf("unknown section %q", raw.Grade)
	}

	relationshipTypeID, ok, err := s.repo.GetRelationshipTypeIDByName(ctx, pool, raw.RelationshipType)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, fmt.Errorf("unknown relationship_type %q", raw.RelationshipType)
	}

	return s.InviteSingle(ctx, pool, invitedByUserID, chainID, branchID, academicYear, ParentInviteInput{
		StudentName:        raw.StudentName,
		ClassID:            classID,
		SectionID:          sectionID,
		ParentName:         raw.ParentName,
		ParentEmail:        raw.ParentEmail,
		ParentPhone:        raw.ParentPhone,
		RelationshipTypeID: relationshipTypeID,
	})
}

func (s *ParentInviteService) InviteBulk(
	ctx context.Context,
	pool *pgxpool.Pool,
	invitedByUserID, chainID, branchID, academicYear string,
	raws []ParentInviteRawInput,
) (*BulkParentInviteResult, error) {
	result := &BulkParentInviteResult{
		Sent:   []ParentInviteResult{},
		Failed: []BulkParentInviteError{},
	}

	for i, raw := range raws {
		row := i + 2 // row 1 is the header
		res, err := s.InviteSingleByName(ctx, pool, invitedByUserID, chainID, branchID, academicYear, raw)
		if err != nil {
			result.Failed = append(result.Failed, BulkParentInviteError{
				Row:         row,
				StudentName: raw.StudentName,
				Error:       err.Error(),
			})
			continue
		}
		result.Sent = append(result.Sent, *res)
	}

	return result, nil
}

func (s *ParentInviteService) sendNotification(ctx context.Context, input ParentInviteInput, link string) (string, error) {
	if input.ParentEmail != nil && *input.ParentEmail != "" {
		subject := "You're invited to CampusCrew as a Parent"
		body := fmt.Sprintf(
			"Hi %s,\n\nYou have been invited to join CampusCrew as a parent/guardian for %s.\n\nActivate your account here:\n%s\n\nThis link expires in 48 hours.\n\nRegards,\nEduPulse Team",
			input.ParentName, input.StudentName, link,
		)
		if err := s.notifier.SendEmail(ctx, *input.ParentEmail, subject, body); err != nil {
			return "", err
		}
		return "email", nil
	}

	message := fmt.Sprintf(
		"Hi %s, you've been invited to CampusCrew as a parent/guardian for %s. Activate your account: %s (expires in 48 hours)",
		input.ParentName, input.StudentName, link,
	)
	if err := s.notifier.SendSMS(ctx, *input.ParentPhone, message); err != nil {
		return "", err
	}
	return "sms", nil
}
