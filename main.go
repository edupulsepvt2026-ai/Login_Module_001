package main

import (
	"fmt"
	"log"
	"time"

	"auth-service/db"
	"auth-service/internal/config"
	"auth-service/internal/handler"
	"auth-service/internal/middleware"
	"auth-service/internal/repository"
	"auth-service/internal/service"
	pkgjwt "auth-service/pkg/jwt"
	"auth-service/pkg/notify"

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
	sessionRepo := repository.NewSessionRepository(masterDB)
	userRepo := repository.NewUserRepository(masterDB)

	// Notify
	notifier := notify.NewClient(cfg.OmnichannelURL)

	// Services
	sessionSvc := service.NewSessionService(sessionRepo, userRepo, jwtManager)
	inviteSvc := service.NewInviteService(inviteRepo, userRepo, rdb)
	otpSvc := service.NewOTPService(otpRepo, rdb, notifier)
	tokenSvc := service.NewTokenService(userRepo, sessionSvc, rdb)

	// Handlers
	inviteHandler := handler.NewInviteHandler(inviteSvc, tokenSvc)
	otpHandler := handler.NewOTPHandler(otpSvc)
	authHandler := handler.NewAuthHandler(sessionSvc, userRepo)
	refreshHandler := handler.NewRefreshHandler(sessionSvc)
	logoutHandler := handler.NewLogoutHandler(sessionSvc)

	r := gin.Default()

	public := r.Group("/auth")
	{
		public.POST("/invite/verify", inviteHandler.VerifyToken)
		public.POST("/invite/set-password", inviteHandler.SetPassword)
		public.POST("/otp/send", otpHandler.Send)
		public.POST("/otp/verify", otpHandler.Verify)
		public.POST("/login", authHandler.Login)
		public.POST("/refresh", refreshHandler.Refresh)
	}

	protected := r.Group("/auth", middleware.JWTMiddleware(jwtManager))
	{
		protected.POST("/logout", logoutHandler.Logout)
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
