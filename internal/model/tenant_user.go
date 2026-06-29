package model

import "github.com/google/uuid"

type TenantUser struct {
	ID           uuid.UUID
	ChainID      uuid.UUID
	ManagementID uuid.UUID
	Role         string
	Email        *string
	Phone        *string
	Name         string
	PasswordHash *string
	IsActive     bool
}
