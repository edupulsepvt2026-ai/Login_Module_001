package service

import (
	"context"
	"fmt"
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

// SendOTP sends a 6-digit OTP to the delivery address for the given channel.
// It does not change the verification state — only VerifyOTP marks a channel as verified.
func (s *OTPService) SendOTP(ctx context.Context, tempToken, channel string) error {
	if channel != "sms" && channel != "email" {
		return fmt.Errorf("channel must be sms or email")
	}

	redisKey := fmt.Sprintf("invite_verify:%s", tempToken)
	session, err := loadSession(ctx, s.redis, redisKey)
	if err != nil {
		return err
	}

	var deliveryAddress, otpTypeName string
	if channel == "sms" {
		if session.Phone == "" {
			return fmt.Errorf("phone not registered for this account")
		}
		deliveryAddress = session.Phone
		otpTypeName = "signup_sms"
	} else {
		if session.Email == "" {
			return fmt.Errorf("email not registered for this account")
		}
		deliveryAddress = session.Email
		otpTypeName = "signup_email"
	}

	var lastSentAt *time.Time
	if channel == "sms" {
		lastSentAt = session.SMSLastSentAt
	} else {
		lastSentAt = session.EmailLastSentAt
	}
	if lastSentAt != nil && time.Since(*lastSentAt) < 60*time.Second {
		remaining := 60 - int(time.Since(*lastSentAt).Seconds())
		return fmt.Errorf("please wait %d seconds before requesting a new OTP", remaining)
	}

	otpTypeID, err := s.otpRepo.GetTypeIDByName(ctx, otpTypeName)
	if err != nil {
		return fmt.Errorf("OTP type configuration missing: %w", err)
	}

	if err := s.otpRepo.InvalidatePrevious(ctx, deliveryAddress); err != nil {
		return fmt.Errorf("failed to invalidate previous OTP")
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
		err = s.notifier.SendSMS(ctx, deliveryAddress, message)
	} else {
		err = s.notifier.SendEmail(ctx, deliveryAddress, "Your EduPulse OTP", message)
	}
	if err != nil {
		return fmt.Errorf("failed to send OTP: %w", err)
	}

	now := time.Now()
	if channel == "sms" {
		session.SMSLastSentAt = &now
	} else {
		session.EmailLastSentAt = &now
	}
	if err := saveSession(ctx, s.redis, redisKey, session); err != nil {
		return fmt.Errorf("failed to update session")
	}

	return nil
}

// VerifyOTP validates the submitted OTP and marks sms_verified or email_verified in the session.
func (s *OTPService) VerifyOTP(ctx context.Context, tempToken, channel, code string) (string, error) {
	if channel != "sms" && channel != "email" {
		return "", fmt.Errorf("channel must be sms or email")
	}

	redisKey := fmt.Sprintf("invite_verify:%s", tempToken)
	session, err := loadSession(ctx, s.redis, redisKey)
	if err != nil {
		return "", err
	}

	var deliveryAddress string
	if channel == "sms" {
		deliveryAddress = session.Phone
	} else {
		deliveryAddress = session.Email
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

	if channel == "sms" {
		session.SMSVerified = true
	} else {
		session.EmailVerified = true
	}

	if err := saveSession(ctx, s.redis, redisKey, session); err != nil {
		return "", fmt.Errorf("failed to update verification session")
	}

	return session.UserID, nil
}
