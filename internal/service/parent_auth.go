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

// ParentAuthService backs the parent account activation flow — Step 1
// (invite verify) so far. Steps 2/3 (OTP send/verify) are the existing
// OTPService, reused unmodified — they only need the Redis session this
// step creates to already have Phone/Email populated.
type ParentAuthService struct {
	repo             *repository.ParentAuthRepository
	tenantInviteRepo *repository.TenantInviteRepository
	tenantMgr        *db.TenantPoolManager
	redis            *redis.Client
}

func NewParentAuthService(
	repo *repository.ParentAuthRepository,
	tenantInviteRepo *repository.TenantInviteRepository,
	tenantMgr *db.TenantPoolManager,
	redis *redis.Client,
) *ParentAuthService {
	return &ParentAuthService{
		repo:             repo,
		tenantInviteRepo: tenantInviteRepo,
		tenantMgr:        tenantMgr,
		redis:            redis,
	}
}

type ParentInviteStudentResult struct {
	ID           string
	Name         string
	Class        string
	Section      string
	Relationship string
}

type ParentInviteVerifyResult struct {
	TempToken   string
	ParentName  string
	ParentEmail string
	ParentPhone string
	ChainID     string
	ChainName   string
	BranchID    string
	BranchName  string
	BranchCity  string
	BranchState string
	Student     ParentInviteStudentResult
}

// VerifyInviteToken is Step 1 — validates the magic link and opens a
// 20-minute Redis session that Steps 2/3 (OTP) read/write via temp_token.
func (s *ParentAuthService) VerifyInviteToken(ctx context.Context, chainID, rawToken string) (*ParentInviteVerifyResult, error) {
	pool, err := s.tenantMgr.GetOrLoad(ctx, chainID)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to school database")
	}

	tokenHash := crypto.SHA256(rawToken)

	invite, err := s.repo.GetInviteWithStudent(ctx, pool, tokenHash)
	if err != nil {
		return nil, fmt.Errorf("invalid or expired invite link")
	}

	branch, err := s.tenantInviteRepo.GetBranchInfo(ctx, pool, invite.BranchID, chainID)
	if err != nil {
		return nil, fmt.Errorf("branch not found")
	}

	chainName, err := s.tenantInviteRepo.GetChainName(ctx, pool, chainID)
	if err != nil {
		return nil, fmt.Errorf("chain not found")
	}

	if err := s.tenantInviteRepo.MarkAccepted(ctx, pool, invite.InviteID); err != nil {
		return nil, fmt.Errorf("failed to process invite")
	}

	tempToken := uuid.New().String()
	redisKey := fmt.Sprintf("invite_verify:%s", tempToken)
	session := &inviteSession{
		Role:          "parent",
		Name:          invite.ParentName,
		Phone:         ptrStr(invite.ParentPhone),
		Email:         ptrStr(invite.ParentEmail),
		ChainID:       chainID,
		BranchID:      invite.BranchID,
		StudentID:     invite.StudentID,
		SMSVerified:   false,
		EmailVerified: false,
	}
	if err := saveSession(ctx, s.redis, redisKey, session); err != nil {
		return nil, fmt.Errorf("failed to create verification session")
	}

	log.Printf("parent invite verify success: chain_id=%s branch_id=%s student_id=%s", chainID, invite.BranchID, invite.StudentID)

	return &ParentInviteVerifyResult{
		TempToken:   tempToken,
		ParentName:  invite.ParentName,
		ParentEmail: maskEmail(ptrStr(invite.ParentEmail)),
		ParentPhone: maskPhone(ptrStr(invite.ParentPhone)),
		ChainID:     chainID,
		ChainName:   chainName,
		BranchID:    invite.BranchID,
		BranchName:  branch.Name,
		BranchCity:  branch.City,
		BranchState: branch.State,
		Student: ParentInviteStudentResult{
			ID:           invite.StudentID,
			Name:         invite.StudentName,
			Class:        ptrStr(invite.ClassName),
			Section:      ptrStr(invite.SectionName),
			Relationship: ptrStr(invite.RelationshipName),
		},
	}, nil
}
