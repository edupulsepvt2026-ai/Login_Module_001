package service

import (
	"context"
	"fmt"
	"log"

	"auth-service/db"
	"auth-service/internal/model"
	"auth-service/internal/repository"
	"auth-service/pkg/crypto"

	"github.com/google/uuid"
)

type LoginService struct {
	chainMapRepo   *repository.ChainMappingRepository
	tenantUserRepo *repository.TenantUserRepository
	tenantMgr      *db.TenantPoolManager
	sessionSvc     *SessionService
}

func NewLoginService(
	chainMapRepo *repository.ChainMappingRepository,
	tenantUserRepo *repository.TenantUserRepository,
	tenantMgr *db.TenantPoolManager,
	sessionSvc *SessionService,
) *LoginService {
	return &LoginService{
		chainMapRepo:   chainMapRepo,
		tenantUserRepo: tenantUserRepo,
		tenantMgr:      tenantMgr,
		sessionSvc:     sessionSvc,
	}
}

func (s *LoginService) Login(ctx context.Context, email, password string) (*TokenPair, error) {
	// Step A — look up which tenant DB holds this user
	mapping, err := s.chainMapRepo.GetByEmail(ctx, email)
	if err != nil {
		return nil, fmt.Errorf("invalid email or password")
	}
	log.Printf("login: routing email=%s → chain_id=%s user_id=%s", email, mapping.ChainID, mapping.UserID)

	// Step B — connect to that chain's tenant DB
	tenantPool, err := s.tenantMgr.GetOrLoad(ctx, mapping.ChainID)
	if err != nil {
		return nil, fmt.Errorf("invalid email or password")
	}

	// Step C — fetch user record and verify password
	tenantUser, err := s.tenantUserRepo.GetByID(ctx, tenantPool, mapping.UserID)
	if err != nil || !tenantUser.IsActive {
		return nil, fmt.Errorf("invalid email or password")
	}

	if tenantUser.PasswordHash == nil || !crypto.CheckPassword(*tenantUser.PasswordHash, password) {
		return nil, fmt.Errorf("invalid email or password")
	}

	// Build a ManagementUser with the IDs needed for JWT claims and session creation
	userID, err := uuid.Parse(mapping.UserID)
	if err != nil {
		return nil, fmt.Errorf("invalid email or password")
	}
	chainID, err := uuid.Parse(mapping.ChainID)
	if err != nil {
		return nil, fmt.Errorf("invalid email or password")
	}

	mgmtUser := &model.ManagementUser{
		ID:      userID,
		ChainID: chainID,
	}

	return s.sessionSvc.CreateSession(ctx, mgmtUser)
}
