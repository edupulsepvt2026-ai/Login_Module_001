package handler

import (
	"log"

	"auth-service/internal/service"
	"auth-service/pkg/response"

	"github.com/gin-gonic/gin"
)

type AuthHandler struct {
	loginSvc *service.LoginService
}

func NewAuthHandler(loginSvc *service.LoginService) *AuthHandler {
	return &AuthHandler{loginSvc: loginSvc}
}

type loginRequest struct {
	Email    string `json:"email"    binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

func (h *AuthHandler) Login(c *gin.Context) {
	var req loginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		log.Printf("login bad request: %v", err)
		response.BadRequestWithCode(c, "invalid_request", "email and password are required")
		return
	}

	tokens, err := h.loginSvc.Login(c.Request.Context(), req.Email, req.Password)
	if err != nil {
		log.Printf("login failed email=%s err=%v", req.Email, err)
		response.UnauthorizedWithCode(c, "invalid_credentials", err.Error())
		return
	}

	log.Printf("login success email=%s", req.Email)
	response.OK(c, gin.H{
		"access_token":  tokens.AccessToken,
		"refresh_token": tokens.RefreshToken,
		"expires_in":    tokens.ExpiresIn,
	})
}
