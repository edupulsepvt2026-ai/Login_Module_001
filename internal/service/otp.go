package service

import (
	"context"
	"fmt"
	"strings"
	"time"

	"auth-service/internal/repository"
	"auth-service/pkg/crypto"
	"auth-service/pkg/notify"

	"github.com/redis/go-redis/v9"
)

type OTPService struct {
	otpRepo  *repository.OTPRepository
	redis    *redis.Client
	notifier *notify.Client
}

func NewOTPService(otpRepo *repository.OTPRepository, redis *redis.Client, notifier *notify.Client) *OTPService {
	return &OTPService{otpRepo: otpRepo, redis: redis, notifier: notifier}
}

// SendOTP sends a 6-digit OTP to the delivery address determined by channel ("sms" or "email").
func (s *OTPService) SendOTP(ctx context.Context, tempToken, channel string) error {
	if channel != "sms" && channel != "email" {
		return fmt.Errorf("channel must be sms or email")
	}

	redisKey := fmt.Sprintf("invite_verify:%s", tempToken)
	val, err := s.redis.Get(ctx, redisKey).Result()
	if err != nil {
		return fmt.Errorf("invalid or expired verification session")
	}

	// Step 1 stores: {user_id}:{phone}:{email}
	parts := strings.SplitN(val, ":", 3)
	if len(parts) != 3 {
		return fmt.Errorf("invalid session data")
	}
	userID, phone, email := parts[0], parts[1], parts[2]

	var deliveryAddress, otpTypeName string
	if channel == "sms" {
		if phone == "" {
			return fmt.Errorf("phone not registered for this account")
		}
		deliveryAddress = phone
		otpTypeName = "signup_sms"
	} else {
		if email == "" {
			return fmt.Errorf("email not registered for this account")
		}
		deliveryAddress = email
		otpTypeName = "signup_email"
	}

	otpTypeID, err := s.otpRepo.GetTypeIDByName(ctx, otpTypeName)
	if err != nil {
		return fmt.Errorf("OTP type configuration missing: %w", err)
	}

	otp, err := crypto.GenerateOTP()
	if err != nil {
		return fmt.Errorf("failed to generate OTP")
	}

	codeHash := crypto.SHA256(otp)
	expiresAt := time.Now().Add(5 * time.Minute)

	if err := s.otpRepo.Create(ctx, otpTypeID, codeHash, deliveryAddress, expiresAt); err != nil {
		return fmt.Errorf("failed to save OTP")
	}

	message := fmt.Sprintf("Your EduPulse OTP is %s. Valid for 5 minutes. Do not share.", otp)
	if channel == "sms" {
		if err := s.notifier.SendSMS(ctx, phone, message); err != nil {
			return fmt.Errorf("failed to send OTP: %w", err)
		}
	} else {
		if err := s.notifier.SendEmail(ctx, email, "Your EduPulse OTP", message); err != nil {
			return fmt.Errorf("failed to send OTP: %w", err)
		}
	}

	// Advance Redis state: append channel so VerifyOTP knows how to find the OTP
	s.redis.Set(ctx, redisKey, fmt.Sprintf("%s:%s:%s:%s", userID, phone, email, channel), 10*time.Minute)

	return nil
}

// VerifyOTP validates the submitted OTP and marks the session as otp_verified.
func (s *OTPService) VerifyOTP(ctx context.Context, tempToken, code string) (string, error) {
	redisKey := fmt.Sprintf("invite_verify:%s", tempToken)
	val, err := s.redis.Get(ctx, redisKey).Result()
	if err != nil {
		return "", fmt.Errorf("invalid or expired verification session")
	}

	// Step 2 stores: {user_id}:{phone}:{email}:{channel}
	parts := strings.SplitN(val, ":", 4)
	if len(parts) != 4 {
		return "", fmt.Errorf("OTP has not been sent yet for this session")
	}
	userID, phone, email, channel := parts[0], parts[1], parts[2], parts[3]

	var deliveryAddress string
	if channel == "sms" {
		deliveryAddress = phone
	} else {
		deliveryAddress = email
	}

	otp, err := s.otpRepo.GetActive(ctx, deliveryAddress)
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

	// Advance Redis state: append :otp_verified so Step 4 knows OTP was completed
	s.redis.Set(ctx, redisKey,
		fmt.Sprintf("%s:%s:%s:%s:otp_verified", userID, phone, email, channel),
		10*time.Minute)

	return userID, nil
}
