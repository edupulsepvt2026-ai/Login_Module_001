package service

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

const inviteSessionTTL = 20 * time.Minute

type inviteSession struct {
	// shared fields
	UserID          string     `json:"user_id"`
	Phone           string     `json:"phone"`
	Email           string     `json:"email"`
	SMSVerified     bool       `json:"sms_verified"`
	EmailVerified   bool       `json:"email_verified"`
	SMSLastSentAt   *time.Time `json:"sms_last_sent_at,omitempty"`
	EmailLastSentAt *time.Time `json:"email_last_sent_at,omitempty"`

	// tenant admin only — empty for chain admin
	Role     string `json:"role,omitempty"`
	Name     string `json:"name,omitempty"`
	ChainID  string `json:"chain_id,omitempty"`
	BranchID string `json:"branch_id,omitempty"`
}

func loadSession(ctx context.Context, rdb *redis.Client, key string) (*inviteSession, error) {
	val, err := rdb.Get(ctx, key).Result()
	if err != nil {
		return nil, fmt.Errorf("invalid or expired verification session")
	}
	var s inviteSession
	if err := json.Unmarshal([]byte(val), &s); err != nil {
		return nil, fmt.Errorf("corrupted verification session")
	}
	return &s, nil
}

func saveSession(ctx context.Context, rdb *redis.Client, key string, s *inviteSession) error {
	b, err := json.Marshal(s)
	if err != nil {
		return fmt.Errorf("failed to encode session")
	}
	return rdb.Set(ctx, key, b, inviteSessionTTL).Err()
}
