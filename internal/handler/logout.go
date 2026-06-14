package handler

import (
	"log"
	"strings"

	"auth-service/internal/service"
	"auth-service/pkg/response"

	"github.com/gin-gonic/gin"
)

type LogoutHandler struct {
	sessionSvc *service.SessionService
}

func NewLogoutHandler(sessionSvc *service.SessionService) *LogoutHandler {
	return &LogoutHandler{sessionSvc: sessionSvc}
}

func (h *LogoutHandler) Logout(c *gin.Context) {
	authHeader := c.GetHeader("Authorization")
	if authHeader == "" || !strings.HasPrefix(authHeader, "Bearer ") {
		log.Print("logout failed missing Authorization header")
		response.UnauthorizedWithCode(c, "missing_token", "missing or invalid token")
		return
	}

	rawToken := strings.TrimPrefix(authHeader, "Bearer ")

	if err := h.sessionSvc.RevokeSession(c.Request.Context(), rawToken); err != nil {
		log.Printf("logout failed revoke session: %v", err)
		response.InternalErrorWithCode(c, "logout_failed", "failed to logout")
		return
	}

	log.Print("logout success")
	response.OK(c, gin.H{"message": "logged out"})
}
