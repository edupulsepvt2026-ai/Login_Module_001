package model

import (
	"time"

	"github.com/google/uuid"
)

type OTP struct {
	ID              uuid.UUID
	OTPTypeID       uuid.UUID
	CodeHash        string
	Attempts        int
	IsUsed          bool
	DeliveryAddress string
	ExpiresAt       time.Time
	CreatedAt       time.Time
}
