package handler

import (
	"log"

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
	log.Printf("verify-token request: token=%s", req.Token)

	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "token is required")
		return
	}
	if c.Request.Method == "OPTIONS" {
		c.JSON(200, gin.H{})
		return
	}

	result, err := h.inviteSvc.VerifyToken(c.Request.Context(), req.Token)
	if err != nil {
		response.Unauthorized(c, err.Error())
		return
	}

	branches := make([]gin.H, len(result.Branches))
	for i, b := range result.Branches {
		branches[i] = gin.H{
			"id":         b.ID,
			"name":       b.Name,
			"city":       b.City,
			"state":      b.State,
			"board_type": b.BoardType,
		}
	}

	response.OK(c, gin.H{
		"temp_token": result.TempToken,
		"user": gin.H{
			"name":  result.UserName,
			"email": result.Email,
			"phone": result.Phone,
		},
		"chain": gin.H{
			"id":   result.ChainID,
			"name": result.ChainName,
		},
		"branches": branches,
	})
}

func (h *InviteHandler) SetPassword(c *gin.Context) {
	var req setPasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		log.Printf("set-password bind error: %v", err)
		response.BadRequest(c, err.Error())
		return
	}

	log.Printf("set-password request: temp_token=%s password_len=%d", req.TempToken, len(req.Password))

	tokens, err := h.tokenSvc.SetPasswordAndActivate(c.Request.Context(), req.TempToken, req.Password)
	if err != nil {
		log.Printf("set-password failed: %v", err)
		response.BadRequest(c, err.Error())
		return
	}

	response.OK(c, gin.H{
		"access_token":  tokens.AccessToken,
		"refresh_token": tokens.RefreshToken,
		"expires_in":    tokens.ExpiresIn,
	})
}
