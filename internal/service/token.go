package service

import (
	"context"
	"fmt"
	"strings"

	"auth-service/internal/repository"
	"auth-service/pkg/crypto"

	"github.com/redis/go-redis/v9"
)

type TokenService struct {
	userRepo    *repository.UserRepository
	sessionSvc  *SessionService
	redis       *redis.Client
}

func NewTokenService(userRepo *repository.UserRepository, sessionSvc *SessionService, redis *redis.Client) *TokenService {
	return &TokenService{userRepo: userRepo, sessionSvc: sessionSvc, redis: redis}
}

func (s *TokenService) SetPasswordAndActivate(ctx context.Context, tempToken, password string) (*TokenPair, error) {
	redisKey := fmt.Sprintf("invite_verify:%s", tempToken)
	val, err := s.redis.Get(ctx, redisKey).Result()
	if err != nil {
		return nil, fmt.Errorf("invalid or expired verification session")
	}

	parts := strings.SplitN(val, ":", 3)
	if len(parts) < 3 || parts[2] != "otp_verified" {
		return nil, fmt.Errorf("OTP verification required before setting password")
	}
	userID := parts[0]

	if len(password) < 8 {
		return nil, fmt.Errorf("password must be at least 8 characters")
	}

	passwordHash, err := crypto.HashPassword(password)
	if err != nil {
		return nil, fmt.Errorf("failed to process password")
	}

	if err := s.userRepo.SetPassword(ctx, userID, passwordHash); err != nil {
		return nil, fmt.Errorf("failed to set password")
	}

	s.redis.Del(ctx, redisKey)

	user, err := s.userRepo.GetByID(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("user not found")
	}

	return s.sessionSvc.CreateSession(ctx, user)
}
