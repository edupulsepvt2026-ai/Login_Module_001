package handler

import (
	"auth-service/internal/service"
	"auth-service/pkg/response"

	"github.com/gin-gonic/gin"
)

type InviteHandler struct {
	inviteSvc *service.InviteService
	tokenSvc  *service.TokenService
}

func NewInviteHandler(inviteSvc *service.InviteService, tokenSvc *service.TokenService) *InviteHandler {
	return &InviteHandler{inviteSvc: inviteSvc, tokenSvc: tokenSvc}
}

type verifyTokenRequest struct {
	Token string `json:"token" binding:"required"`
}

type setPasswordRequest struct {
	TempToken string `json:"temp_token" binding:"required"`
	Password  string `json:"password" binding:"required,min=8"`
}

func (h *InviteHandler) VerifyToken(c *gin.Context) {
	var req verifyTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "token is required")
		return
	}

	result, err := h.inviteSvc.VerifyToken(c.Request.Context(), req.Token)
	if err != nil {
		response.Unauthorized(c, err.Error())
		return
	}

	response.OK(c, gin.H{
		"temp_token": result.TempToken,
		"phone":      result.Phone,
	})
}

func (h *InviteHandler) SetPassword(c *gin.Context) {
	var req setPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	tokens, err := h.tokenSvc.SetPasswordAndActivate(c.Request.Context(), req.TempToken, req.Password)
	if err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	response.OK(c, gin.H{
		"access_token":  tokens.AccessToken,
		"refresh_token": tokens.RefreshToken,
		"expires_in":    tokens.ExpiresIn,
	})
}
