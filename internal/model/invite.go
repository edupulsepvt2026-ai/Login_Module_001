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

type Chain struct {
	ID   uuid.UUID
	Name string
}

type Branch struct {
	ID        uuid.UUID
	Name      string
	City      string
	State     string
	BoardType string
}
