package handler

import (
	"log"

	"auth-service/internal/repository"
	"auth-service/internal/service"
	"auth-service/pkg/crypto"
	"auth-service/pkg/response"

	"github.com/gin-gonic/gin"
)

type AuthHandler struct {
	sessionSvc *service.SessionService
	userRepo   *repository.UserRepository
}

func NewAuthHandler(sessionSvc *service.SessionService, userRepo *repository.UserRepository) *AuthHandler {
	return &AuthHandler{sessionSvc: sessionSvc, userRepo: userRepo}
}

type loginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

func (h *AuthHandler) Login(c *gin.Context) {
	var req loginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		log.Printf("login bad request: %v", err)
		response.BadRequestWithCode(c, "invalid_request", "email and password are required")
		return
	}

	user, err := h.userRepo.GetByEmail(c.Request.Context(), req.Email)
	if err != nil {
		log.Printf("login failed invalid credentials email=%s err=%v", req.Email, err)
		response.UnauthorizedWithCode(c, "invalid_credentials", "invalid email or password")
		return
	}

	if user.PasswordHash == nil || !crypto.CheckPassword(*user.PasswordHash, req.Password) {
		log.Printf("login failed invalid credentials email=%s", req.Email)
		response.UnauthorizedWithCode(c, "invalid_credentials", "invalid email or password")
		return
	}

	tokens, err := h.sessionSvc.CreateSession(c.Request.Context(), user)
	if err != nil {
		log.Printf("login failed create session email=%s err=%v", req.Email, err)
		response.InternalErrorWithCode(c, "session_creation_failed", "failed to create session")
		return
	}

	log.Printf("login success email=%s user_id=%s", req.Email, user.ID.String())
	response.OK(c, gin.H{
		"access_token":  tokens.AccessToken,
		"refresh_token": tokens.RefreshToken,
		"expires_in":    tokens.ExpiresIn,
	})
}
