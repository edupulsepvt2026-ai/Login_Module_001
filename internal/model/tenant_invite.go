package model

import (
	"time"

	"github.com/google/uuid"
)

type TenantInvite struct {
	ID              uuid.UUID
	ManagementID    uuid.UUID
	StatusID        uuid.UUID
	InviteTokenHash string
	Name            string
	Email           *string
	Phone           *string
	ExpiresAt       time.Time
	AcceptedAt      *time.Time
	CreatedAt       time.Time
}

type BranchInfo struct {
	ID    string
	Name  string
	City  string
	State string
}
