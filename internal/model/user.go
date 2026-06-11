package model

import (
	"time"

	"github.com/google/uuid"
)

type ManagementUser struct {
	ID                  uuid.UUID
	ChainID             uuid.UUID
	Email               *string
	Phone               *string
	Username            *string
	Name                string
	PasswordHash        *string
	IsActive            bool
	IsEmailVerified     bool
	IsPhoneVerified     bool
	FailedLoginAttempts int
	LockedUntil         *time.Time
	LastLoginAt         *time.Time
	CreatedAt           time.Time
	UpdatedAt           time.Time
}
