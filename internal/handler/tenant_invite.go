package handler

import (
	"log"

	"auth-service/internal/service"
	"auth-service/pkg/response"

	"github.com/gin-gonic/gin"
)

type TenantInviteHandler struct {
	svc *service.TenantInviteService
}

func NewTenantInviteHandler(svc *service.TenantInviteService) *TenantInviteHandler {
	return &TenantInviteHandler{svc: svc}
}

type tenantVerifyTokenRequest struct {
	Token   string `json:"token"    binding:"required"`
	ChainID string `json:"chain_id" binding:"required"`
}

func (h *TenantInviteHandler) VerifyInviteToken(c *gin.Context) {
	var req tenantVerifyTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		log.Printf("tenant invite verify bind error: %v", err)
		response.BadRequest(c, err.Error())
		return
	}

	log.Printf("tenant invite verify: chain_id=%s", req.ChainID)

	result, err := h.svc.VerifyInviteToken(c.Request.Context(), req.ChainID, req.Token)
	if err != nil {
		log.Printf("tenant invite verify failed: chain_id=%s err=%v", req.ChainID, err)
		response.Unauthorized(c, err.Error())
		return
	}

	log.Printf("tenant invite verify success: chain_id=%s branch_id=%s", req.ChainID, result.BranchID)

	response.OK(c, gin.H{
		"temp_token": result.TempToken,
		"user": gin.H{
			"name":  result.Name,
			"email": result.Email,
			"phone": result.Phone,
		},
		"branch": gin.H{
			"id":    result.BranchID,
			"name":  result.BranchName,
			"city":  result.BranchCity,
			"state": result.BranchState,
		},
		"chain": gin.H{
			"id":   result.ChainID,
			"name": result.ChainName,
		},
	})
}
