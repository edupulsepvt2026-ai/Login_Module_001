package handler

import (
	"errors"

	"auth-service/internal/middleware"
	"auth-service/internal/service"
	"auth-service/pkg/response"

	"github.com/gin-gonic/gin"
)

type ChainAdminHandler struct {
	chainAdminSvc *service.ChainAdminService
}

func NewChainAdminHandler(chainAdminSvc *service.ChainAdminService) *ChainAdminHandler {
	return &ChainAdminHandler{chainAdminSvc: chainAdminSvc}
}

// GetBranches handles GET /chain-admin/branches
// Returns all active branches under the chain admin's chain, with has_tenant_admin flag.
func (h *ChainAdminHandler) GetBranches(c *gin.Context) {
	chainID, _ := c.Get("chain_id")
	chainIDStr, ok := chainID.(string)
	if !ok || chainIDStr == "" {
		response.Unauthorized(c, "missing chain identity in token")
		return
	}

	pool, err := middleware.GetTenantDB(c)
	if err != nil {
		response.InternalError(c, "tenant database unavailable")
		return
	}

	result, err := h.chainAdminSvc.GetBranches(c.Request.Context(), pool, chainIDStr)
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}

	branches := make([]gin.H, len(result.Branches))
	for i, b := range result.Branches {
		branches[i] = gin.H{
			"id":               b.TenantID,
			"name":             b.Name,
			"city":             b.City,
			"state":            b.State,
			"has_tenant_admin": b.HasTenantAdmin,
		}
	}

	response.OK(c, gin.H{
		"chain_id":   result.ChainID,
		"chain_name": result.ChainName,
		"branches":   branches,
	})
}

// InviteTenantAdmin handles POST /chain-admin/tenant-admins
// Validates the branch, creates a user + invite record, and sends the invite link.
func (h *ChainAdminHandler) InviteTenantAdmin(c *gin.Context) {
	var body struct {
		BranchID string  `json:"branch_id" binding:"required"`
		Name     string  `json:"name"      binding:"required"`
		Email    *string `json:"email"`
		Mobile   *string `json:"mobile"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	if emptyPtr(body.Email) && emptyPtr(body.Mobile) {
		response.BadRequest(c, "email or mobile is required")
		return
	}

	userID, _ := c.Get("user_id")
	userIDStr, _ := userID.(string)

	chainID, _ := c.Get("chain_id")
	chainIDStr, ok := chainID.(string)
	if !ok || chainIDStr == "" {
		response.Unauthorized(c, "missing chain identity in token")
		return
	}

	pool, err := middleware.GetTenantDB(c)
	if err != nil {
		response.InternalError(c, "tenant database unavailable")
		return
	}

	req := service.InviteTenantAdminRequest{
		BranchID: body.BranchID,
		Name:     body.Name,
		Email:    body.Email,
		Mobile:   body.Mobile,
	}

	result, err := h.chainAdminSvc.InviteTenantAdmin(c.Request.Context(), pool, chainIDStr, userIDStr, req)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrBranchNotInChain):
			response.Forbidden(c, err.Error())
		case errors.Is(err, service.ErrTenantAdminExists):
			response.Conflict(c, err.Error())
		default:
			response.InternalError(c, err.Error())
		}
		return
	}

	response.Created(c, gin.H{
		"message":          result.Message,
		"invite_id":        result.InviteID,
		"delivery_channel": result.DeliveryChannel,
	})
}

// emptyPtr returns true if the pointer is nil or points to an empty string.
func emptyPtr(s *string) bool {
	return s == nil || *s == ""
}
