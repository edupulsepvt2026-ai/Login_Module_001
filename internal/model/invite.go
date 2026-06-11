package model

import (
	"time"

	"github.com/google/uuid"
)

type Invite struct {
	ID               uuid.UUID
	ManagementUserID uuid.UUID
	StatusID         uuid.UUID
	InviteTokenHash  string
	ResendCount      int
	ExpiresAt        time.Time
	AcceptedAt       *time.Time
	CreatedAt        time.Time
}
