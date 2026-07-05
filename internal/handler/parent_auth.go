package handler

import (
	"log"

	"auth-service/internal/service"
	"auth-service/pkg/response"

	"github.com/gin-gonic/gin"
)

type ParentAuthHandler struct {
	svc *service.ParentAuthService
}

func NewParentAuthHandler(svc *service.ParentAuthService) *ParentAuthHandler {
	return &ParentAuthHandler{svc: svc}
}

type parentVerifyTokenRequest struct {
	Token   string `json:"token"    binding:"required"`
	ChainID string `json:"chain_id" binding:"required"`
}

// VerifyInviteToken handles POST /parent-auth/invite/verify (Step 1)
func (h *ParentAuthHandler) VerifyInviteToken(c *gin.Context) {
	var req parentVerifyTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		log.Printf("parent invite verify bind error: %v", err)
		response.BadRequest(c, err.Error())
		return
	}

	log.Printf("parent invite verify: chain_id=%s", req.ChainID)

	result, err := h.svc.VerifyInviteToken(c.Request.Context(), req.ChainID, req.Token)
	if err != nil {
		log.Printf("parent invite verify failed: chain_id=%s err=%v", req.ChainID, err)
		response.Unauthorized(c, err.Error())
		return
	}

	response.OK(c, gin.H{
		"temp_token": result.TempToken,
		"parent": gin.H{
			"name":  result.ParentName,
			"email": result.ParentEmail,
			"phone": result.ParentPhone,
		},
		"student": gin.H{
			"id":           result.Student.ID,
			"name":         result.Student.Name,
			"class":        result.Student.Class,
			"section":      result.Student.Section,
			"relationship": result.Student.Relationship,
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
