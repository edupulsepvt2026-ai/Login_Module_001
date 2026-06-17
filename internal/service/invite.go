package service

import (
	"context"
	"fmt"
	"time"

	"auth-service/internal/repository"
	"auth-service/pkg/crypto"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
)


type InviteService struct {
	inviteRepo *repository.InviteRepository
	userRepo   *repository.UserRepository
	redis      *redis.Client
}

func NewInviteService(inviteRepo *repository.InviteRepository, userRepo *repository.UserRepository, redis *redis.Client) *InviteService {
	return &InviteService{inviteRepo: inviteRepo, userRepo: userRepo, redis: redis}
}

type BranchResult struct {
	ID        string
	Name      string
	City      string
	State     string
	BoardType string
}

type VerifyTokenResult struct {
	TempToken string
	UserName  string
	Email     string
	Phone     string
	ChainID   string
	ChainName string
	Branches  []BranchResult
}

func (s *InviteService) VerifyToken(ctx context.Context, rawToken string) (*VerifyTokenResult, error) {
	tokenHash := crypto.SHA256(rawToken)

	invite, err := s.inviteRepo.GetByTokenHash(ctx, tokenHash)
	if err != nil {
		return nil, fmt.Errorf("invalid or expired invite link")
	}

	if time.Now().After(invite.ExpiresAt) {
		return nil, fmt.Errorf("invite link has expired")
	}

	user, err := s.userRepo.GetByID(ctx, invite.ManagementUserID.String())
	if err != nil {
		return nil, fmt.Errorf("user not found")
	}

	chain, err := s.inviteRepo.GetChainByID(ctx, user.ChainID.String())
	if err != nil {
		return nil, fmt.Errorf("chain not found")
	}

	branches, err := s.inviteRepo.GetBranchesByChainID(ctx, user.ChainID.String())
	if err != nil {
		return nil, fmt.Errorf("failed to fetch branches")
	}

	if err := s.inviteRepo.MarkAccepted(ctx, invite.ID.String()); err != nil {
		return nil, fmt.Errorf("failed to process invite")
	}

	tempToken := uuid.New().String()
	redisKey := fmt.Sprintf("invite_verify:%s", tempToken)
	session := &inviteSession{
		UserID:        invite.ManagementUserID.String(),
		Phone:         ptrStr(user.Phone),
		Email:         ptrStr(user.Email),
		SMSVerified:   false,
		EmailVerified: false,
	}
	if err := saveSession(ctx, s.redis, redisKey, session); err != nil {
		return nil, fmt.Errorf("failed to create verification session")
	}

	branchResults := make([]BranchResult, len(branches))
	for i, b := range branches {
		branchResults[i] = BranchResult{
			ID:        b.ID.String(),
			Name:      b.Name,
			City:      b.City,
			State:     b.State,
			BoardType: b.BoardType,
		}
	}

	return &VerifyTokenResult{
		TempToken: tempToken,
		UserName:  user.Name,
		Email:     maskEmail(ptrStr(user.Email)),
		Phone:     maskPhone(ptrStr(user.Phone)),
		ChainID:   chain.ID.String(),
		ChainName: chain.Name,
		Branches:  branchResults,
	}, nil
}

func ptrStr(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

func maskPhone(phone string) string {
	if len(phone) < 4 {
		return "****"
	}
	return "******" + phone[len(phone)-4:]
}

func maskEmail(email string) string {
	at := -1
	for i, c := range email {
		if c == '@' {
			at = i
			break
		}
	}
	if at <= 1 {
		return "****" + email[at:]
	}
	return string(email[0]) + "****" + email[at:]
}
