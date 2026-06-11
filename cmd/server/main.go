package main

import (
	"fmt"
	"log"

	"auth-service/db"
	"auth-service/internal/config"
	"auth-service/internal/handler"
	"auth-service/internal/repository"
	"auth-service/internal/router"
	"auth-service/internal/service"
	pkgjwt "auth-service/pkg/jwt"

	"github.com/redis/go-redis/v9"
)

func main() {
	cfg := config.Load()

	// DB
	dsn := db.BuildDSN(cfg.MasterDBHost, cfg.MasterDBPort, cfg.MasterDBUser, cfg.MasterDBPassword, cfg.MasterDBName)
	masterDB := db.ConnectMaster(dsn)
	defer masterDB.Close()

	// Redis
	rdb := redis.NewClient(&redis.Options{
		Addr:     cfg.RedisAddr,
		Password: cfg.RedisPassword,
	})

	// JWT
	jwtManager := pkgjwt.NewManager(cfg.JWTSecret, cfg.JWTAccessExpirySeconds, cfg.JWTRefreshExpirySeconds)

	// Repositories
	inviteRepo := repository.NewInviteRepository(masterDB)
	otpRepo := repository.NewOTPRepository(masterDB)
	sessionRepo := repository.NewSessionRepository(masterDB)
	userRepo := repository.NewUserRepository(masterDB)

	// Services
	sessionSvc := service.NewSessionService(sessionRepo, userRepo, jwtManager)
	inviteSvc := service.NewInviteService(inviteRepo, userRepo, rdb)
	otpSvc := service.NewOTPService(otpRepo, rdb)
	tokenSvc := service.NewTokenService(userRepo, sessionSvc, rdb)

	// Handlers
	handlers := &router.Handlers{
		Invite:  handler.NewInviteHandler(inviteSvc, tokenSvc),
		OTP:     handler.NewOTPHandler(otpSvc),
		Auth:    handler.NewAuthHandler(sessionSvc),
		Refresh: handler.NewRefreshHandler(sessionSvc),
		Logout:  handler.NewLogoutHandler(sessionSvc),
	}

	// Router
	r := router.Setup(handlers, jwtManager)

	addr := fmt.Sprintf(":%s", cfg.Port)
	log.Printf("auth-service starting on %s", addr)
	if err := r.Run(addr); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}
