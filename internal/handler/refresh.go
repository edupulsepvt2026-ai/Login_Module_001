package handler

import (
	"auth-service/internal/service"
	"auth-service/pkg/response"

	"github.com/gin-gonic/gin"
)

type RefreshHandler struct {
	sessionSvc *service.SessionService
}

func NewRefreshHandler(sessionSvc *service.SessionService) *RefreshHandler {
	return &RefreshHandler{sessionSvc: sessionSvc}
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

func (h *RefreshHandler) Refresh(c *gin.Context) {
	var req refreshRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "refresh_token is required")
		return
	}

	tokens, err := h.sessionSvc.RefreshSession(c.Request.Context(), req.RefreshToken)
	if err != nil {
		response.Unauthorized(c, err.Error())
		return
	}

	response.OK(c, gin.H{
		"access_token":  tokens.AccessToken,
		"refresh_token": tokens.RefreshToken,
		"expires_in":    tokens.ExpiresIn,
	})
}
