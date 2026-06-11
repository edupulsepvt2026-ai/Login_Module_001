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

type VerifyTokenResult struct {
	TempToken string
	Phone     string
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

	if err := s.inviteRepo.MarkAccepted(ctx, invite.ID.String()); err != nil {
		return nil, fmt.Errorf("failed to process invite")
	}

	tempToken := uuid.New().String()
	redisKey := fmt.Sprintf("invite_verify:%s", tempToken)
	redisVal := fmt.Sprintf("%s:%s", invite.ManagementUserID.String(), ptrStr(user.Phone))

	if err := s.redis.Set(ctx, redisKey, redisVal, 10*time.Minute).Err(); err != nil {
		return nil, fmt.Errorf("failed to create verification session")
	}

	return &VerifyTokenResult{
		TempToken: tempToken,
		Phone:     maskPhone(ptrStr(user.Phone)),
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
