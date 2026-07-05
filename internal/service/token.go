package service

import (
	"context"
	"fmt"
	"log"

	"auth-service/db"
	"auth-service/internal/middleware"
	"auth-service/internal/repository"
	"auth-service/pkg/crypto"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
)

type TokenService struct {
	userRepo        *repository.UserRepository
	tenantUserRepo  *repository.TenantUserRepository
	chainMapRepo    *repository.ChainMappingRepository
	teacherAuthRepo *repository.TeacherAuthRepository
	sessionSvc      *SessionService
	redis           *redis.Client
	tenantMgr       *db.TenantPoolManager
}

func NewTokenService(
	userRepo *repository.UserRepository,
	tenantUserRepo *repository.TenantUserRepository,
	chainMapRepo *repository.ChainMappingRepository,
	teacherAuthRepo *repository.TeacherAuthRepository,
	sessionSvc *SessionService,
	redis *redis.Client,
	tenantMgr *db.TenantPoolManager,
) *TokenService {
	return &TokenService{
		userRepo:        userRepo,
		tenantUserRepo:  tenantUserRepo,
		chainMapRepo:    chainMapRepo,
		teacherAuthRepo: teacherAuthRepo,
		sessionSvc:      sessionSvc,
		redis:           redis,
		tenantMgr:       tenantMgr,
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
	if session.Role == "teacher" && !session.ProfileComplete {
		return nil, fmt.Errorf("profile details required before setting password")
	}

	if len(password) < 8 {
		return nil, fmt.Errorf("password must be at least 8 characters")
	}

	passwordHash, err := crypto.HashPassword(password)
	if err != nil {
		return nil, fmt.Errorf("failed to process password")
	}

	if session.Role == "tenant_admin" {
		return s.activateTenantAdmin(ctx, redisKey, session, passwordHash)
	}
	if session.Role == "teacher" {
		return s.activateTeacher(ctx, redisKey, session, passwordHash)
	}
	return s.activateChainAdmin(ctx, redisKey, session, passwordHash)
}

func (s *TokenService) activateChainAdmin(ctx context.Context, redisKey string, session *inviteSession, passwordHash string) (*TokenPair, error) {
	mgmtUser, err := s.userRepo.GetByID(ctx, session.UserID)
	if err != nil {
		return nil, fmt.Errorf("user not found")
	}
	chainID := mgmtUser.ChainID.String()
	log.Printf("set-password (chain_admin): user_id=%s chain_id=%s", session.UserID, chainID)

	tenantPool, err := s.tenantMgr.GetOrLoad(ctx, chainID)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to school database: %w", err)
	}

	if err := s.tenantUserRepo.Create(ctx, tenantPool, session.UserID, chainID,
		mgmtUser.Email, mgmtUser.Phone, mgmtUser.Name, passwordHash); err != nil {
		return nil, fmt.Errorf("failed to create user account: %w", err)
	}

	if err := s.chainMapRepo.Create(ctx, session.UserID, "chain_admin", chainID, mgmtUser.Email, mgmtUser.Phone); err != nil {
		return nil, fmt.Errorf("failed to create identity mapping: %w", err)
	}
	log.Printf("set-password (chain_admin): activated user_id=%s", session.UserID)

	s.redis.Del(ctx, redisKey)

	ctx = context.WithValue(ctx, middleware.TenantDBContextKey, tenantPool)
	return s.sessionSvc.CreateSession(ctx, mgmtUser)
}

func (s *TokenService) activateTenantAdmin(ctx context.Context, redisKey string, session *inviteSession, passwordHash string) (*TokenPair, error) {
	chainID := session.ChainID
	branchID := session.BranchID

	tenantPool, err := s.tenantMgr.GetOrLoad(ctx, chainID)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to school database: %w", err)
	}

	newUserID := uuid.New().String()

	var emailPtr, phonePtr *string
	if session.Email != "" {
		e := session.Email
		emailPtr = &e
	}
	if session.Phone != "" {
		p := session.Phone
		phonePtr = &p
	}

	if err := s.tenantUserRepo.CreateTenantAdmin(ctx, tenantPool, newUserID, branchID,
		emailPtr, phonePtr, session.Name, passwordHash); err != nil {
		return nil, fmt.Errorf("failed to create tenant admin account: %w", err)
	}

	if err := s.chainMapRepo.Create(ctx, newUserID, "tenant_admin", chainID, emailPtr, phonePtr); err != nil {
		return nil, fmt.Errorf("failed to create identity mapping: %w", err)
	}
	log.Printf("set-password (tenant_admin): activated user_id=%s chain_id=%s branch_id=%s", newUserID, chainID, branchID)

	s.redis.Del(ctx, redisKey)

	ctx = context.WithValue(ctx, middleware.TenantDBContextKey, tenantPool)
	return s.sessionSvc.CreateSessionForTenantUser(ctx, newUserID, chainID, branchID, "tenant_admin")
}

// activateTeacher creates auth.user + all teachers.* rows in a single
// transaction (see TeacherAuthRepository.CreateTeacherAccount), then adds the
// chain_user_mapping row that lets /auth/login route teacher logins the same
// way as tenant_admin — see docs/API_V3.0_TEACHER_ONBOARDING.md § Phase 3.
func (s *TokenService) activateTeacher(ctx context.Context, redisKey string, session *inviteSession, passwordHash string) (*TokenPair, error) {
	chainID := session.ChainID
	branchID := session.BranchID

	tenantPool, err := s.tenantMgr.GetOrLoad(ctx, chainID)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to school database: %w", err)
	}

	var emailPtr, phonePtr, qualificationPtr, alternateMobilePtr *string
	if session.Email != "" {
		e := session.Email
		emailPtr = &e
	}
	if session.Phone != "" {
		p := session.Phone
		phonePtr = &p
	}
	if session.QualificationID != "" {
		q := session.QualificationID
		qualificationPtr = &q
	}
	if session.AlternateMobile != "" {
		a := session.AlternateMobile
		alternateMobilePtr = &a
	}

	newUserID, err := s.teacherAuthRepo.CreateTeacherAccount(ctx, tenantPool, repository.TeacherAccountInput{
		BranchID:        branchID,
		Name:            session.Name,
		Email:           emailPtr,
		Phone:           phonePtr,
		PasswordHash:    passwordHash,
		Address:         session.Address,
		AlternateMobile: alternateMobilePtr,
		PincodeID:       session.PincodeID,
		GenderID:        session.GenderID,
		QualificationID: qualificationPtr,
		SubjectIDs:      session.SubjectIDs,
		LanguageIDs:     session.LanguageIDs,
		ClassSections:   session.ClassSections,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to create teacher account: %w", err)
	}

	if err := s.chainMapRepo.Create(ctx, newUserID, "teacher", chainID, emailPtr, phonePtr); err != nil {
		return nil, fmt.Errorf("failed to create identity mapping: %w", err)
	}
	log.Printf("set-password (teacher): activated user_id=%s chain_id=%s branch_id=%s", newUserID, chainID, branchID)

	s.redis.Del(ctx, redisKey)

	ctx = context.WithValue(ctx, middleware.TenantDBContextKey, tenantPool)
	return s.sessionSvc.CreateSessionForTenantUser(ctx, newUserID, chainID, branchID, "teacher")
}
