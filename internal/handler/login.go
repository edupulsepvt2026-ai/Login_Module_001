package handler

import (
	"auth-service/internal/service"
	"auth-service/pkg/response"

	"github.com/gin-gonic/gin"
)

type LoginHandler struct {
	sessionSvc *service.SessionService
	userRepo   interface {
		GetByEmail(ctx interface{}, email string) (interface{}, error)
	}
}

type AuthHandler struct {
	sessionSvc *service.SessionService
}

func NewAuthHandler(sessionSvc *service.SessionService) *AuthHandler {
	return &AuthHandler{sessionSvc: sessionSvc}
}

type loginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required"`
}

func (h *AuthHandler) Login(c *gin.Context) {
	var req loginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	// TODO: fetch user by email, verify password, call sessionSvc.CreateSession
	response.OK(c, gin.H{"message": "login endpoint — implementation pending"})
}
