package handler

import (
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
		response.Unauthorized(c, "missing token")
		return
	}

	rawToken := strings.TrimPrefix(authHeader, "Bearer ")

	if err := h.sessionSvc.RevokeSession(c.Request.Context(), rawToken); err != nil {
		response.InternalError(c, "failed to logout")
		return
	}

	response.OK(c, gin.H{"message": "logged out"})
}
