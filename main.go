package main

import (
	"fmt"
	"log"
	"strings"
	"time"

	"auth-service/db"
	"auth-service/internal/config"
	"auth-service/internal/handler"
	"auth-service/internal/middleware"
	"auth-service/internal/repository"
	"auth-service/internal/service"
	pkgjwt "auth-service/pkg/jwt"
	"auth-service/pkg/notify"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
)

func main() {
	cfg := config.Load()

	// Master DB - constant connection for credentials and core data
	dsn := db.BuildDSN(cfg.MasterDBHost, cfg.MasterDBPort, cfg.MasterDBUser, cfg.MasterDBPassword, cfg.MasterDBName, "require")
	masterDB := db.ConnectMaster(dsn)
	defer masterDB.Close()

	// Redis
	rdb := redis.NewClient(&redis.Options{
		Addr:     cfg.RedisAddr,
		Password: cfg.RedisPassword,
	})

	// JWT
	jwtManager := pkgjwt.NewManager(cfg.JWTSecret, cfg.JWTAccessExpirySeconds, cfg.JWTRefreshExpirySeconds)

	// Tenant DB Pool Manager with expiry
	expiryDuration := time.Duration(cfg.TenantPoolExpiryMinutes) * time.Minute
	coreSettingRepo := repository.NewCoreSettingRepository(masterDB)
	tenantMgr := db.NewTenantPoolManager(expiryDuration, coreSettingRepo)
	defer tenantMgr.Close()

	go cleanupExpiredTenantPools(tenantMgr, 5*time.Minute)

	// Repositories
	inviteRepo := repository.NewInviteRepository(masterDB)
	otpRepo := repository.NewOTPRepository(masterDB)
	sessionRepo := repository.NewSessionRepository()
	userRepo := repository.NewUserRepository(masterDB)
	tenantUserRepo := repository.NewTenantUserRepository()
	chainMapRepo := repository.NewChainMappingRepository(masterDB)
	chainAdminRepo := repository.NewChainAdminRepository()
	tenantInviteRepo := repository.NewTenantInviteRepository()
	teacherInviteRepo := repository.NewTeacherInviteRepository()
	teacherAuthRepo := repository.NewTeacherAuthRepository()
	parentInviteRepo := repository.NewParentInviteRepository()

	// Notify
	notifier := notify.NewClient(cfg.OmnichannelURL)

	// Services
	sessionSvc := service.NewSessionService(sessionRepo, userRepo, chainMapRepo, tenantUserRepo, tenantMgr, jwtManager)
	inviteSvc := service.NewInviteService(inviteRepo, userRepo, rdb)
	otpSvc := service.NewOTPService(otpRepo, rdb, notifier)
	tokenSvc := service.NewTokenService(userRepo, tenantUserRepo, chainMapRepo, teacherAuthRepo, sessionSvc, rdb, tenantMgr)
	loginSvc := service.NewLoginService(chainMapRepo, tenantUserRepo, tenantMgr, sessionSvc)
	chainAdminSvc := service.NewChainAdminService(chainAdminRepo, notifier, cfg.InviteBaseURL)
	tenantInviteSvc := service.NewTenantInviteService(tenantInviteRepo, tenantMgr, rdb)
	teacherInviteSvc := service.NewTeacherInviteService(teacherInviteRepo, notifier, cfg.TeacherInviteBaseURL)
	teacherAuthSvc := service.NewTeacherAuthService(teacherAuthRepo, tenantInviteRepo, tenantMgr, rdb)
	parentInviteSvc := service.NewParentInviteService(parentInviteRepo, notifier, cfg.ParentInviteBaseURL)

	// Handlers
	inviteHandler := handler.NewInviteHandler(inviteSvc, tokenSvc)
	otpHandler := handler.NewOTPHandler(otpSvc)
	authHandler := handler.NewAuthHandler(loginSvc)
	refreshHandler := handler.NewRefreshHandler(sessionSvc)
	logoutHandler := handler.NewLogoutHandler(sessionSvc)
	chainAdminHandler := handler.NewChainAdminHandler(chainAdminSvc)
	tenantInviteHandler := handler.NewTenantInviteHandler(tenantInviteSvc)
	teacherInviteHandler := handler.NewTeacherInviteHandler(teacherInviteSvc)
	teacherAuthHandler := handler.NewTeacherAuthHandler(teacherAuthSvc)
	parentInviteHandler := handler.NewParentInviteHandler(parentInviteSvc, cfg)

	r := gin.Default()

	origins := strings.Split(cfg.CORSAllowedOrigins, ",")
	r.Use(cors.New(cors.Config{
		AllowOrigins:     origins,
		AllowMethods:     []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Authorization", "chain_id", "X-Tenant-MID"},
		AllowCredentials: true,
		MaxAge:           12 * time.Hour,
	}))

	tenantPublic := r.Group("/tenant-auth")
	{
		tenantPublic.POST("/invite/verify", tenantInviteHandler.VerifyInviteToken)
	}

	teacherPublic := r.Group("/teacher-auth")
	{
		teacherPublic.POST("/invite/verify", teacherAuthHandler.VerifyInviteToken)
		teacherPublic.GET("/onboarding-options", teacherAuthHandler.GetOnboardingOptions)
		teacherPublic.POST("/profile", teacherAuthHandler.SubmitProfile)
	}

	public := r.Group("/auth")
	{
		public.POST("/invite/verify", inviteHandler.VerifyToken)
		public.POST("/invite/set-password", inviteHandler.SetPassword)
		public.POST("/otp/send", otpHandler.Send)
		public.POST("/otp/verify", otpHandler.Verify)
		public.POST("/login", authHandler.Login)
		public.POST("/refresh", middleware.TenantDBMiddleware(tenantMgr), refreshHandler.Refresh)
	}

	protected := r.Group("/auth", middleware.JWTMiddleware(jwtManager), middleware.TenantDBMiddleware(tenantMgr))
	{
		protected.POST("/logout", logoutHandler.Logout)
	}

	chainAdmin := r.Group("/chain-admin", middleware.JWTMiddleware(jwtManager), middleware.TenantDBMiddleware(tenantMgr))
	{
		chainAdmin.GET("/branches", chainAdminHandler.GetBranches)
		chainAdmin.POST("/tenant-admins", chainAdminHandler.InviteTenantAdmin)
	}

	tenantProtected := r.Group("/tenant", middleware.JWTMiddleware(jwtManager), middleware.TenantDBMiddleware(tenantMgr))
	{
		tenantProtected.GET("/teachers/template", teacherInviteHandler.DownloadTemplate)
		tenantProtected.POST("/teachers/invite", teacherInviteHandler.InviteSingle)
		tenantProtected.POST("/teachers/bulk-invite", teacherInviteHandler.BulkInvite)
	}

	teacherProtected := r.Group("/teacher", middleware.JWTMiddleware(jwtManager), middleware.TenantDBMiddleware(tenantMgr))
	{
		teacherProtected.GET("/parents/template", parentInviteHandler.DownloadTemplate)
		teacherProtected.POST("/parents/invite", parentInviteHandler.InviteSingle)
		teacherProtected.POST("/parents/bulk-invite", parentInviteHandler.BulkInvite)
	}

	addr := fmt.Sprintf(":%s", cfg.Port)
	log.Printf("auth-service starting on %s", addr)
	if err := r.Run(addr); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}

// cleanupExpiredTenantPools periodically removes expired tenant DB pools
func cleanupExpiredTenantPools(tenantMgr *db.TenantPoolManager, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for range ticker.C {
		tenantMgr.CleanupExpired()
		log.Println("cleaned up expired tenant DB pools")
	}
}
