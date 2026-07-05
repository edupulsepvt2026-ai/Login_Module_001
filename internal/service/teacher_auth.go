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
	"github.com/redis/go-redis/v9"
)

// TeacherAuthService backs the teacher account activation flow:
// invite verify (Step 1), onboarding master data (Step 4), profile
// submission (Step 5). Password set (Step 6) lives in TokenService,
// same as every other role.
type TeacherAuthService struct {
	repo             *repository.TeacherAuthRepository
	tenantInviteRepo *repository.TenantInviteRepository
	tenantMgr        *db.TenantPoolManager
	redis            *redis.Client
}

func NewTeacherAuthService(
	repo *repository.TeacherAuthRepository,
	tenantInviteRepo *repository.TenantInviteRepository,
	tenantMgr *db.TenantPoolManager,
	redis *redis.Client,
) *TeacherAuthService {
	return &TeacherAuthService{
		repo:             repo,
		tenantInviteRepo: tenantInviteRepo,
		tenantMgr:        tenantMgr,
		redis:            redis,
	}
}

type TeacherInviteVerifyResult struct {
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

// VerifyInviteToken is Step 1 — validates the magic link and opens a
// 20-minute Redis session that Steps 2-6 read/write via temp_token.
func (s *TeacherAuthService) VerifyInviteToken(ctx context.Context, chainID, rawToken string) (*TeacherInviteVerifyResult, error) {
	pool, err := s.tenantMgr.GetOrLoad(ctx, chainID)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to school database")
	}

	tokenHash := crypto.SHA256(rawToken)

	invite, err := s.repo.GetByTokenHash(ctx, pool, tokenHash)
	if err != nil {
		return nil, fmt.Errorf("invalid or expired invite link")
	}

	branchID := invite.ManagementID.String()

	branch, err := s.tenantInviteRepo.GetBranchInfo(ctx, pool, branchID, chainID)
	if err != nil {
		return nil, fmt.Errorf("branch not found")
	}

	chainName, err := s.tenantInviteRepo.GetChainName(ctx, pool, chainID)
	if err != nil {
		return nil, fmt.Errorf("chain not found")
	}

	if err := s.tenantInviteRepo.MarkAccepted(ctx, pool, invite.ID.String()); err != nil {
		return nil, fmt.Errorf("failed to process invite")
	}

	tempToken := uuid.New().String()
	redisKey := fmt.Sprintf("invite_verify:%s", tempToken)
	session := &inviteSession{
		Role:          "teacher",
		Name:          invite.Name,
		Phone:         ptrStr(invite.Phone),
		Email:         ptrStr(invite.Email),
		ChainID:       chainID,
		BranchID:      branchID,
		SMSVerified:   false,
		EmailVerified: false,
	}
	if err := saveSession(ctx, s.redis, redisKey, session); err != nil {
		return nil, fmt.Errorf("failed to create verification session")
	}

	log.Printf("teacher invite verify success: chain_id=%s branch_id=%s", chainID, branchID)

	return &TeacherInviteVerifyResult{
		TempToken:   tempToken,
		Name:        invite.Name,
		Email:       maskEmail(ptrStr(invite.Email)),
		Phone:       maskPhone(ptrStr(invite.Phone)),
		ChainID:     chainID,
		ChainName:   chainName,
		BranchID:    branchID,
		BranchName:  branch.Name,
		BranchCity:  branch.City,
		BranchState: branch.State,
	}, nil
}

type OnboardingOptionsResult struct {
	Genders        []model.MasterOption
	Qualifications []model.MasterOption
	Subjects       []model.MasterOption
	Languages      []model.MasterOption
	Classes        []model.ClassOption
}

// GetOnboardingOptions is Step 4 — read-only, no session state is modified.
func (s *TeacherAuthService) GetOnboardingOptions(ctx context.Context, tempToken string) (*OnboardingOptionsResult, error) {
	redisKey := fmt.Sprintf("invite_verify:%s", tempToken)
	session, err := loadSession(ctx, s.redis, redisKey)
	if err != nil {
		return nil, err
	}

	pool, err := s.tenantMgr.GetOrLoad(ctx, session.ChainID)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to school database")
	}

	genders, err := s.repo.GetGenders(ctx, pool)
	if err != nil {
		return nil, err
	}
	qualifications, err := s.repo.GetQualifications(ctx, pool)
	if err != nil {
		return nil, err
	}
	subjects, err := s.repo.GetSubjects(ctx, pool)
	if err != nil {
		return nil, err
	}
	languages, err := s.repo.GetLanguages(ctx, pool)
	if err != nil {
		return nil, err
	}
	classes, err := s.repo.GetClassesWithSections(ctx, pool)
	if err != nil {
		return nil, err
	}

	return &OnboardingOptionsResult{
		Genders:        genders,
		Qualifications: qualifications,
		Subjects:       subjects,
		Languages:      languages,
		Classes:        classes,
	}, nil
}

type SubmitProfileInput struct {
	TempToken       string
	Address         string
	AlternateMobile string
	PincodeID       string
	GenderID        string
	QualificationID string
	SubjectIDs      []string
	LanguageIDs     []string
	ClassSections   []model.ClassSectionPair
}

type SubmitProfileResult struct {
	Status string
}

// SubmitProfile is Step 5 — validates every masters.* ID against the tenant
// DB before accepting it into the session. These FKs are app-layer only
// (no DB-level REFERENCES) so this is the one place a typo or tampered
// request would otherwise become silent data corruption downstream.
// Nothing is written to teachers.* here — that happens at Step 6.
func (s *TeacherAuthService) SubmitProfile(ctx context.Context, in SubmitProfileInput) (*SubmitProfileResult, error) {
	redisKey := fmt.Sprintf("invite_verify:%s", in.TempToken)
	session, err := loadSession(ctx, s.redis, redisKey)
	if err != nil {
		return nil, err
	}

	if !session.SMSVerified {
		return nil, fmt.Errorf("phone verification required before submitting profile")
	}
	if !session.EmailVerified {
		return nil, fmt.Errorf("email verification required before submitting profile")
	}

	if in.Address == "" {
		return nil, fmt.Errorf("address is required")
	}
	if in.PincodeID == "" {
		return nil, fmt.Errorf("pincode_id is required")
	}
	if in.GenderID == "" {
		return nil, fmt.Errorf("gender_id is required")
	}
	if len(in.SubjectIDs) == 0 {
		return nil, fmt.Errorf("at least one subject is required")
	}
	if len(in.LanguageIDs) == 0 {
		return nil, fmt.Errorf("at least one language is required")
	}
	if len(in.ClassSections) == 0 {
		return nil, fmt.Errorf("at least one class section is required")
	}

	pool, err := s.tenantMgr.GetOrLoad(ctx, session.ChainID)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to school database")
	}

	if ok, err := s.repo.ExistsPincode(ctx, pool, in.PincodeID); err != nil {
		return nil, err
	} else if !ok {
		return nil, fmt.Errorf("invalid pincode_id")
	}

	if ok, err := s.repo.ExistsGender(ctx, pool, in.GenderID); err != nil {
		return nil, err
	} else if !ok {
		return nil, fmt.Errorf("invalid gender_id")
	}

	if in.QualificationID != "" {
		if ok, err := s.repo.ExistsQualification(ctx, pool, in.QualificationID); err != nil {
			return nil, err
		} else if !ok {
			return nil, fmt.Errorf("invalid qualification_id")
		}
	}

	if count, err := s.repo.CountSubjects(ctx, pool, in.SubjectIDs); err != nil {
		return nil, err
	} else if count != len(in.SubjectIDs) {
		return nil, fmt.Errorf("invalid subject_ids")
	}

	if count, err := s.repo.CountLanguages(ctx, pool, in.LanguageIDs); err != nil {
		return nil, err
	} else if count != len(in.LanguageIDs) {
		return nil, fmt.Errorf("invalid language_ids")
	}

	if ok, err := s.repo.ValidateClassSections(ctx, pool, in.ClassSections); err != nil {
		return nil, err
	} else if !ok {
		return nil, fmt.Errorf("invalid class_sections")
	}

	session.Address = in.Address
	session.AlternateMobile = in.AlternateMobile
	session.PincodeID = in.PincodeID
	session.GenderID = in.GenderID
	session.QualificationID = in.QualificationID
	session.SubjectIDs = in.SubjectIDs
	session.LanguageIDs = in.LanguageIDs
	session.ClassSections = in.ClassSections
	session.ProfileComplete = true

	if err := saveSession(ctx, s.redis, redisKey, session); err != nil {
		return nil, fmt.Errorf("failed to update verification session")
	}

	return &SubmitProfileResult{Status: "profile_complete"}, nil
}
