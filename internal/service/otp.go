package service

import (
	"context"
	"fmt"
	"strings"
	"time"

	"auth-service/internal/repository"
	"auth-service/pkg/crypto"

	"github.com/redis/go-redis/v9"
)

type OTPService struct {
	otpRepo *repository.OTPRepository
	redis   *redis.Client
}

func NewOTPService(otpRepo *repository.OTPRepository, redis *redis.Client) *OTPService {
	return &OTPService{otpRepo: otpRepo, redis: redis}
}

func (s *OTPService) SendOTP(ctx context.Context, tempToken string) error {
	redisKey := fmt.Sprintf("invite_verify:%s", tempToken)
	val, err := s.redis.Get(ctx, redisKey).Result()
	if err != nil {
		return fmt.Errorf("invalid or expired verification session")
	}

	parts := strings.SplitN(val, ":", 2)
	if len(parts) != 2 {
		return fmt.Errorf("invalid session data")
	}
	phone := parts[1]

	otp, err := crypto.GenerateOTP()
	if err != nil {
		return fmt.Errorf("failed to generate OTP")
	}

	codeHash := crypto.SHA256(otp)
	expiresAt := time.Now().Add(5 * time.Minute)

	otpTypeID := "signup_sms_type_uuid"
	if err := s.otpRepo.Create(ctx, otpTypeID, codeHash, phone, expiresAt); err != nil {
		return fmt.Errorf("failed to save OTP")
	}

	// TODO: send OTP via SMS provider (Twilio / MSG91)
	fmt.Printf("OTP for %s: %s\n", phone, otp)

	return nil
}

func (s *OTPService) VerifyOTP(ctx context.Context, tempToken, code string) (string, error) {
	redisKey := fmt.Sprintf("invite_verify:%s", tempToken)
	val, err := s.redis.Get(ctx, redisKey).Result()
	if err != nil {
		return "", fmt.Errorf("invalid or expired verification session")
	}

	parts := strings.SplitN(val, ":", 2)
	if len(parts) != 2 {
		return "", fmt.Errorf("invalid session data")
	}
	userID := parts[0]
	phone := parts[1]

	otp, err := s.otpRepo.GetActive(ctx, phone)
	if err != nil {
		return "", fmt.Errorf("OTP not found or expired")
	}

	if otp.Attempts >= 3 {
		return "", fmt.Errorf("too many incorrect attempts")
	}

	if !crypto.CompareHash(otp.CodeHash, code) {
		_ = s.otpRepo.IncrementAttempt(ctx, otp.ID.String())
		return "", fmt.Errorf("incorrect OTP")
	}

	if err := s.otpRepo.MarkUsed(ctx, otp.ID.String()); err != nil {
		return "", fmt.Errorf("failed to verify OTP")
	}

	s.redis.Set(ctx, redisKey, fmt.Sprintf("%s:%s:otp_verified", userID, phone), 10*time.Minute)

	return userID, nil
}
