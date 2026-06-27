package service

import (
	"context"
	"fmt"
	"log"

	"auth-service/db"
	"auth-service/internal/middleware"
	"auth-service/internal/repository"
	"auth-service/pkg/crypto"

	"github.com/redis/go-redis/v9"
)

type TokenService struct {
	userRepo       *repository.UserRepository
	tenantUserRepo *repository.TenantUserRepository
	chainMapRepo   *repository.ChainMappingRepository
	sessionSvc     *SessionService
	redis          *redis.Client
	tenantMgr      *db.TenantPoolManager
}

func NewTokenService(
	userRepo *repository.UserRepository,
	tenantUserRepo *repository.TenantUserRepository,
	chainMapRepo *repository.ChainMappingRepository,
	sessionSvc *SessionService,
	redis *redis.Client,
	tenantMgr *db.TenantPoolManager,
) *TokenService {
	return &TokenService{
		userRepo:       userRepo,
		tenantUserRepo: tenantUserRepo,
		chainMapRepo:   chainMapRepo,
		sessionSvc:     sessionSvc,
		redis:          redis,
		tenantMgr:      tenantMgr,
	}
}

func (s *TokenService) SetPasswordAndActivate(ctx context.Context, tempToken, password string) (*TokenPair, error) {
	redisKey := fmt.Sprintf("invite_verify:%s", tempToken)
	session, err := loadSession(ctx, s.redis, redisKey)
	if err != nil {
		return nil, err
	}

	if !session.SMSVerified {
		return nil, fmt.Errorf("phone verification required before setting password")
	}
	if !session.EmailVerified {
		return nil, fmt.Errorf("email verification required before setting password")
	}

	if len(password) < 8 {
		return nil, fmt.Errorf("password must be at least 8 characters")
	}

	passwordHash, err := crypto.HashPassword(password)
	if err != nil {
		return nil, fmt.Errorf("failed to process password")
	}

	// Load master user record to get chain_id, name, email, phone
	mgmtUser, err := s.userRepo.GetByID(ctx, session.UserID)
	if err != nil {
		return nil, fmt.Errorf("user not found")
	}
	chainID := mgmtUser.ChainID.String()
	log.Printf("set-password: user_id=%s chain_id=%s", session.UserID, chainID)

	// Connect to this chain's tenant DB
	tenantPool, err := s.tenantMgr.GetOrLoad(ctx, chainID)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to school database: %w", err)
	}

	// INSERT into tenant DB — this is where the chain admin's login credentials live
	if err := s.tenantUserRepo.Create(ctx, tenantPool, session.UserID, chainID,
		mgmtUser.Email, mgmtUser.Phone, mgmtUser.Name, passwordHash); err != nil {
		return nil, fmt.Errorf("failed to create user account: %w", err)
	}
	log.Printf("set-password: tenant user created user_id=%s", session.UserID)

	// INSERT into master DB — enables login routing (email → chain_id → tenant DB)
	if err := s.chainMapRepo.Create(ctx, session.UserID, chainID, mgmtUser.Email, mgmtUser.Phone); err != nil {
		return nil, fmt.Errorf("failed to create identity mapping: %w", err)
	}
	log.Printf("set-password: chain mapping created user_id=%s chain_id=%s", session.UserID, chainID)

	// Clean up the Redis session now that account is fully activated
	s.redis.Del(ctx, redisKey)

	// Ensure the tenant pool is available in the context for session persistence
	ctx = context.WithValue(ctx, middleware.TenantDBContextKey, tenantPool)
	return s.sessionSvc.CreateSession(ctx, mgmtUser)
}
