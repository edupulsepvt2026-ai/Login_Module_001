package service

import (
	"context"
	"fmt"
	"time"

	"auth-service/db"
	"auth-service/internal/middleware"
	"auth-service/internal/model"
	"auth-service/internal/repository"
	"auth-service/pkg/crypto"
	pkgjwt "auth-service/pkg/jwt"
)

type SessionService struct {
	sessionRepo    *repository.SessionRepository
	userRepo       *repository.UserRepository
	chainMapRepo   *repository.ChainMappingRepository
	tenantUserRepo *repository.TenantUserRepository
	tenantMgr      *db.TenantPoolManager
	jwtManager     *pkgjwt.Manager
}

func NewSessionService(
	sessionRepo *repository.SessionRepository,
	userRepo *repository.UserRepository,
	chainMapRepo *repository.ChainMappingRepository,
	tenantUserRepo *repository.TenantUserRepository,
	tenantMgr *db.TenantPoolManager,
	jwtManager *pkgjwt.Manager,
) *SessionService {
	return &SessionService{
		sessionRepo:    sessionRepo,
		userRepo:       userRepo,
		chainMapRepo:   chainMapRepo,
		tenantUserRepo: tenantUserRepo,
		tenantMgr:      tenantMgr,
		jwtManager:     jwtManager,
	}
}

type TokenPair struct {
	AccessToken  string
	RefreshToken string
	ExpiresIn    int
}

func (s *SessionService) CreateSession(ctx context.Context, user *model.ManagementUser) (*TokenPair, error) {
	accessToken, err := s.jwtManager.SignAccessToken(pkgjwt.Claims{
		UserID:         user.ID.String(),
		Role:           "chain_admin",
		ManagementType: "chain",
		ManagementID:   user.ChainID.String(),
		ChainID:        user.ChainID.String(),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to sign access token: %w", err)
	}

	refreshToken, err := crypto.GenerateToken(32)
	if err != nil {
		return nil, fmt.Errorf("failed to generate refresh token: %w", err)
	}

	accessHash := crypto.SHA256(accessToken)
	refreshHash := crypto.SHA256(refreshToken)
	accessExp := time.Now().Add(15 * time.Minute)
	refreshExp := time.Now().Add(7 * 24 * time.Hour)

	_, err = s.sessionRepo.Create(ctx, user.ID.String(), accessHash, refreshHash, accessExp, refreshExp)
	if err != nil {
		return nil, fmt.Errorf("failed to create session: %w", err)
	}

	return &TokenPair{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    900,
	}, nil
}

func (s *SessionService) CreateSessionForTenantUser(ctx context.Context, userID, chainID, branchID string) (*TokenPair, error) {
	accessToken, err := s.jwtManager.SignAccessToken(pkgjwt.Claims{
		UserID:         userID,
		Role:           "tenant_admin",
		ManagementType: "tenant",
		ManagementID:   branchID,
		ChainID:        chainID,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to sign access token: %w", err)
	}

	refreshToken, err := crypto.GenerateToken(32)
	if err != nil {
		return nil, fmt.Errorf("failed to generate refresh token: %w", err)
	}

	accessHash := crypto.SHA256(accessToken)
	refreshHash := crypto.SHA256(refreshToken)
	accessExp := time.Now().Add(15 * time.Minute)
	refreshExp := time.Now().Add(7 * 24 * time.Hour)

	_, err = s.sessionRepo.Create(ctx, userID, accessHash, refreshHash, accessExp, refreshExp)
	if err != nil {
		return nil, fmt.Errorf("failed to create session: %w", err)
	}

	return &TokenPair{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    900,
	}, nil
}

func (s *SessionService) RefreshSession(ctx context.Context, rawRefreshToken string) (*TokenPair, error) {
	refreshHash := crypto.SHA256(rawRefreshToken)

	session, err := s.sessionRepo.GetByRefreshHash(ctx, refreshHash)
	if err != nil {
		return nil, fmt.Errorf("invalid or expired refresh token")
	}

	userID := session.UserID.String()

	mapping, err := s.chainMapRepo.GetByUserID(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("user not found")
	}

	if err := s.sessionRepo.Revoke(ctx, session.ID.String()); err != nil {
		return nil, fmt.Errorf("failed to rotate session")
	}

	if mapping.Role == "tenant_admin" {
		tenantPool, err := s.tenantMgr.GetOrLoad(ctx, mapping.ChainID)
		if err != nil {
			return nil, fmt.Errorf("failed to connect to school database")
		}
		tenantUser, err := s.tenantUserRepo.GetByID(ctx, tenantPool, userID)
		if err != nil {
			return nil, fmt.Errorf("user not found")
		}
		ctx = context.WithValue(ctx, middleware.TenantDBContextKey, tenantPool)
		return s.CreateSessionForTenantUser(ctx, userID, mapping.ChainID, tenantUser.ManagementID.String())
	}

	user, err := s.userRepo.GetByID(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("user not found")
	}
	return s.CreateSession(ctx, user)
}

func (s *SessionService) RevokeSession(ctx context.Context, accessToken string) error {
	accessHash := crypto.SHA256(accessToken)
	return s.sessionRepo.RevokeByAccessHash(ctx, accessHash)
}
