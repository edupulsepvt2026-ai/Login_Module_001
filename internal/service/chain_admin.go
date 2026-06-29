package service

import (
	"context"
	"errors"
	"fmt"
	"log"
	"time"

	"auth-service/internal/model"
	"auth-service/internal/repository"
	"auth-service/pkg/crypto"
	"auth-service/pkg/notify"

	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrBranchNotInChain  = errors.New("branch does not belong to your chain")
	ErrTenantAdminExists = errors.New("tenant admin already exists")
)

type ChainAdminService struct {
	repo          *repository.ChainAdminRepository
	notifier      *notify.Client
	inviteBaseURL string
}

func NewChainAdminService(
	repo *repository.ChainAdminRepository,
	notifier *notify.Client,
	inviteBaseURL string,
) *ChainAdminService {
	return &ChainAdminService{
		repo:          repo,
		notifier:      notifier,
		inviteBaseURL: inviteBaseURL,
	}
}

// ── Get Branches ─────────────────────────────────────────────────

type GetBranchesResult struct {
	ChainID   string
	ChainName string
	Branches  []BranchItem
}

type BranchItem struct {
	TenantID       string
	Name           string
	City           string
	State          string
	HasTenantAdmin bool
}

func (s *ChainAdminService) GetBranches(ctx context.Context, pool *pgxpool.Pool, chainID string) (*GetBranchesResult, error) {
	chainName, err := s.repo.GetChainName(ctx, pool, chainID)
	if err != nil {
		return nil, fmt.Errorf("chain not found")
	}

	branches, err := s.repo.GetBranches(ctx, pool, chainID)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch branches")
	}

	items := make([]BranchItem, len(branches))
	for i, b := range branches {
		items[i] = branchItemFrom(b)
	}

	return &GetBranchesResult{
		ChainID:   chainID,
		ChainName: chainName,
		Branches:  items,
	}, nil
}

func branchItemFrom(b model.BranchWithAdminFlag) BranchItem {
	return BranchItem{
		TenantID:       b.TenantID,
		Name:           b.Name,
		City:           b.City,
		State:          b.State,
		HasTenantAdmin: b.HasTenantAdmin,
	}
}

// ── Invite Tenant Admin ──────────────────────────────────────────

type InviteTenantAdminRequest struct {
	BranchID string
	Name     string
	Email    *string
	Mobile   *string
}

type InviteTenantAdminResult struct {
	InviteID        string
	Message         string
	DeliveryChannel string
}

func (s *ChainAdminService) InviteTenantAdmin(
	ctx context.Context,
	pool *pgxpool.Pool,
	chainID, callerUserID string,
	req InviteTenantAdminRequest,
) (*InviteTenantAdminResult, error) {
	// Verify the branch belongs to this chain.
	branch, err := s.repo.GetBranchByTenantID(ctx, pool, req.BranchID, chainID)
	if err != nil {
		return nil, ErrBranchNotInChain
	}

	// Reject if an active tenant_admin already exists for this branch.
	exists, err := s.repo.HasActiveTenantAdmin(ctx, pool, req.BranchID)
	if err != nil {
		return nil, fmt.Errorf("failed to check tenant admin")
	}
	if exists {
		return nil, ErrTenantAdminExists
	}

	// Generate a raw token, store only its hash.
	rawToken, err := crypto.GenerateToken(32)
	if err != nil {
		return nil, fmt.Errorf("failed to generate invite token")
	}
	tokenHash := crypto.SHA256(rawToken)
	expiresAt := time.Now().Add(48 * time.Hour)

	inviteID, err := s.repo.CreateInvite(
		ctx, pool,
		callerUserID, req.BranchID, req.Name, tokenHash,
		req.Email, req.Mobile,
		expiresAt,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create invite")
	}

	// Build the magic link sent to the recipient.
	inviteLink := fmt.Sprintf("%s?token=%s", s.inviteBaseURL, rawToken)
	log.Printf("[DEV] tenant admin raw invite token: %s", rawToken)

	// Send via email (preferred) or SMS (fallback).
	deliveryChannel, err := s.sendInviteNotification(ctx, req, branch, inviteLink)
	if err != nil {
		return nil, fmt.Errorf("failed to send invite")
	}

	// Audit log — non-fatal.
	_ = s.repo.InsertAuditLog(ctx, pool, callerUserID, chainID, req.BranchID)

	return &InviteTenantAdminResult{
		InviteID:        inviteID,
		Message:         fmt.Sprintf("Invite sent to %s", req.Name),
		DeliveryChannel: deliveryChannel,
	}, nil
}

func (s *ChainAdminService) sendInviteNotification(
	ctx context.Context,
	req InviteTenantAdminRequest,
	branch *model.TenantBranch,
	inviteLink string,
) (string, error) {
	if req.Email != nil && *req.Email != "" {
		subject := fmt.Sprintf("You're invited to CampusCrew as Branch Admin — %s", branch.BranchName)
		body := fmt.Sprintf(
			"Hi %s,\n\nYou have been invited to CampusCrew as branch admin for %s (%s).\n\nActivate your account here:\n%s\n\nThis link expires in 48 hours.\n\nRegards,\nEduPulse Team",
			req.Name, branch.BranchName, branch.ChainName, inviteLink,
		)
		if err := s.notifier.SendEmail(ctx, *req.Email, subject, body); err != nil {
			return "", err
		}
		return "email", nil
	}

	message := fmt.Sprintf(
		"You have been invited to CampusCrew as branch admin for %s. Activate here: %s (expires in 48 hours)",
		branch.BranchName, inviteLink,
	)
	if err := s.notifier.SendSMS(ctx, *req.Mobile, message); err != nil {
		return "", err
	}
	return "sms", nil
}
