package service

import (
	"context"
	"fmt"
	"log"

	"auth-service/db"
	"auth-service/internal/repository"
	"auth-service/pkg/crypto"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
)

type TenantInviteService struct {
	repo      *repository.TenantInviteRepository
	tenantMgr *db.TenantPoolManager
	redis     *redis.Client
}

func NewTenantInviteService(
	repo *repository.TenantInviteRepository,
	tenantMgr *db.TenantPoolManager,
	redis *redis.Client,
) *TenantInviteService {
	return &TenantInviteService{repo: repo, tenantMgr: tenantMgr, redis: redis}
}

type TenantInviteVerifyResult struct {
	TempToken   string
	Name        string
	Email       string
	Phone       string
	ChainID     string
	ChainName   string
	BranchID    string
	BranchName  string
	BranchCity  string
	BranchState string
}

func (s *TenantInviteService) VerifyInviteToken(ctx context.Context, chainID, rawToken string) (*TenantInviteVerifyResult, error) {
	pool, err := s.tenantMgr.GetOrLoad(ctx, chainID)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to school database")
	}

	tokenHash := crypto.SHA256(rawToken)

	invite, err := s.repo.GetByTokenHash(ctx, pool, tokenHash)
	if err != nil {
		return nil, fmt.Errorf("invalid or expired invite link")
	}

	tenantID := invite.ManagementID.String()
	log.Printf("tenant invite verify: chain_id=%s tenant_id=%s", chainID, tenantID)
	branch, err := s.repo.GetBranchInfo(ctx, pool, tenantID, chainID)
	if err != nil {
		return nil, fmt.Errorf("branch not found")
	}

	chainName, err := s.repo.GetChainName(ctx, pool, chainID)
	if err != nil {
		return nil, fmt.Errorf("chain not found")
	}

	if err := s.repo.MarkAccepted(ctx, pool, invite.ID.String()); err != nil {
		return nil, fmt.Errorf("failed to process invite")
	}

	tempToken := uuid.New().String()
	redisKey := fmt.Sprintf("invite_verify:%s", tempToken)
	session := &inviteSession{
		Role:          "tenant_admin",
		UserID:        "",
		Name:          invite.Name,
		Phone:         ptrStr(invite.Phone),
		Email:         ptrStr(invite.Email),
		ChainID:       chainID,
		BranchID:      tenantID,
		SMSVerified:   false,
		EmailVerified: false,
	}
	if err := saveSession(ctx, s.redis, redisKey, session); err != nil {
		return nil, fmt.Errorf("failed to create verification session")
	}

	return &TenantInviteVerifyResult{
		TempToken:   tempToken,
		Name:        invite.Name,
		Email:       maskEmail(ptrStr(invite.Email)),
		Phone:       maskPhone(ptrStr(invite.Phone)),
		ChainID:     chainID,
		ChainName:   chainName,
		BranchID:    tenantID,
		BranchName:  branch.Name,
		BranchCity:  branch.City,
		BranchState: branch.State,
	}, nil
}
