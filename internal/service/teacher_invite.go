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

type TeacherInviteInput struct {
	Name  string
	Email *string
	Phone *string
}

type TeacherInviteResult struct {
	InviteID        string
	Name            string
	DeliveryChannel string
}

type BulkTeacherInviteResult struct {
	Sent   []TeacherInviteResult
	Failed []BulkTeacherInviteError
}

type BulkTeacherInviteError struct {
	Row   int
	Name  string
	Error string
}

type TeacherInviteService struct {
	repo          *repository.TeacherInviteRepository
	notifier      *notify.Client
	inviteBaseURL string
}

func NewTeacherInviteService(
	repo *repository.TeacherInviteRepository,
	notifier *notify.Client,
	inviteBaseURL string,
) *TeacherInviteService {
	return &TeacherInviteService{
		repo:          repo,
		notifier:      notifier,
		inviteBaseURL: inviteBaseURL,
	}
}

func (s *TeacherInviteService) InviteSingle(
	ctx context.Context,
	pool *pgxpool.Pool,
	invitedByUserID, chainID, branchID string,
	input TeacherInviteInput,
) (*TeacherInviteResult, error) {
	if (input.Email == nil || *input.Email == "") && (input.Phone == nil || *input.Phone == "") {
		log.Printf("[TeacherInvite] validation failed: email or phone required — name=%s branch_id=%s", input.Name, branchID)
		return nil, fmt.Errorf("email or phone is required")
	}

	rawToken, err := crypto.GenerateToken(32)
	if err != nil {
		log.Printf("[TeacherInvite] token generation failed: name=%s branch_id=%s — %v", input.Name, branchID, err)
		return nil, fmt.Errorf("failed to generate invite token")
	}
	tokenHash := crypto.SHA256(rawToken)
	expiresAt := time.Now().Add(48 * time.Hour)

	inviteID, err := s.repo.Create(ctx, pool, invitedByUserID, branchID, input.Name, tokenHash, input.Email, input.Phone, expiresAt)
	if err != nil {
		log.Printf("[TeacherInvite] repo create failed: name=%s branch_id=%s chain_id=%s — %v", input.Name, branchID, chainID, err)
		return nil, fmt.Errorf("failed to create invite")
	}

	inviteLink := fmt.Sprintf("%s?token=%s&chain_id=%s", s.inviteBaseURL, rawToken, chainID)
	log.Printf("[DEV] teacher raw invite token: %s", rawToken)

	channel, err := s.sendNotification(ctx, input, inviteLink)
	if err != nil {
		log.Printf("[TeacherInvite] notification failed: invite_id=%s name=%s — %v", inviteID, input.Name, err)
		return nil, fmt.Errorf("invite created but notification failed: %w", err)
	}

	return &TeacherInviteResult{
		InviteID:        inviteID,
		Name:            input.Name,
		DeliveryChannel: channel,
	}, nil
}

func (s *TeacherInviteService) InviteBulk(
	ctx context.Context,
	pool *pgxpool.Pool,
	invitedByUserID, chainID, branchID string,
	inputs []TeacherInviteInput,
) (*BulkTeacherInviteResult, error) {
	result := &BulkTeacherInviteResult{
		Sent:   []TeacherInviteResult{},
		Failed: []BulkTeacherInviteError{},
	}

	for i, input := range inputs {
		row := i + 2 // row 1 is the header
		inv, err := s.InviteSingle(ctx, pool, invitedByUserID, chainID, branchID, input)
		if err != nil {
			result.Failed = append(result.Failed, BulkTeacherInviteError{
				Row:   row,
				Name:  input.Name,
				Error: err.Error(),
			})
			continue
		}
		result.Sent = append(result.Sent, *inv)
	}

	return result, nil
}

func (s *TeacherInviteService) sendNotification(ctx context.Context, input TeacherInviteInput, link string) (string, error) {
	if input.Email != nil && *input.Email != "" {
		subject := "You're invited to CampusCrew as a Teacher"
		body := fmt.Sprintf(
			"Hi %s,\n\nYou have been invited to join CampusCrew as a teacher.\n\nActivate your account here:\n%s\n\nThis link expires in 48 hours.\n\nRegards,\nEduPulse Team",
			input.Name, link,
		)
		if err := s.notifier.SendEmail(ctx, *input.Email, subject, body); err != nil {
			return "", err
		}
		return "email", nil
	}

	message := fmt.Sprintf(
		"Hi %s, you've been invited to CampusCrew as a teacher. Activate your account: %s (expires in 48 hours)",
		input.Name, link,
	)
	if err := s.notifier.SendSMS(ctx, *input.Phone, message); err != nil {
		return "", err
	}
	return "sms", nil
}
