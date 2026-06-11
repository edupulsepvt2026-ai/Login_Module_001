package model

import (
	"time"

	"github.com/google/uuid"
)

type Session struct {
	ID                        uuid.UUID
	UserID                    uuid.UUID
	AccessTokenHash           string
	RefreshTokenHash          string
	AccessTokenExpiresAt      time.Time
	RefreshTokenExpiresAt     time.Time
	RefreshTokenLastRotatedAt *time.Time
	IPAddress                 *string
	UserAgent                 *string
	DeviceFingerprint         *string
	RevokedAt                 *time.Time
	CreatedAt                 time.Time
}
