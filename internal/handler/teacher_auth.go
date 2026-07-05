package handler

import (
	"log"

	"auth-service/internal/model"
	"auth-service/internal/service"
	"auth-service/pkg/response"

	"github.com/gin-gonic/gin"
)

type TeacherAuthHandler struct {
	svc *service.TeacherAuthService
}

func NewTeacherAuthHandler(svc *service.TeacherAuthService) *TeacherAuthHandler {
	return &TeacherAuthHandler{svc: svc}
}

type teacherVerifyTokenRequest struct {
	Token   string `json:"token"    binding:"required"`
	ChainID string `json:"chain_id" binding:"required"`
}

// VerifyInviteToken handles POST /teacher-auth/invite/verify (Step 1)
func (h *TeacherAuthHandler) VerifyInviteToken(c *gin.Context) {
	var req teacherVerifyTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		log.Printf("teacher invite verify bind error: %v", err)
		response.BadRequest(c, err.Error())
		return
	}

	log.Printf("teacher invite verify: chain_id=%s", req.ChainID)

	result, err := h.svc.VerifyInviteToken(c.Request.Context(), req.ChainID, req.Token)
	if err != nil {
		log.Printf("teacher invite verify failed: chain_id=%s err=%v", req.ChainID, err)
		response.Unauthorized(c, err.Error())
		return
	}

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

// GetOnboardingOptions handles GET /teacher-auth/onboarding-options (Step 4)
func (h *TeacherAuthHandler) GetOnboardingOptions(c *gin.Context) {
	tempToken := c.Query("temp_token")
	if tempToken == "" {
		response.BadRequest(c, "temp_token is required")
		return
	}

	result, err := h.svc.GetOnboardingOptions(c.Request.Context(), tempToken)
	if err != nil {
		log.Printf("onboarding-options failed: err=%v", err)
		response.BadRequest(c, err.Error())
		return
	}

	response.OK(c, gin.H{
		"genders":        optionsToJSON(result.Genders),
		"qualifications": optionsToJSON(result.Qualifications),
		"subjects":       optionsToJSON(result.Subjects),
		"languages":      optionsToJSON(result.Languages),
		"classes":        classesToJSON(result.Classes),
	})
}

type submitProfileRequest struct {
	TempToken       string                   `json:"temp_token" binding:"required"`
	Address         string                   `json:"address"`
	AlternateMobile string                   `json:"alternate_mobile"`
	PincodeID       string                   `json:"pincode_id"`
	GenderID        string                   `json:"gender_id"`
	QualificationID string                   `json:"qualification_id"`
	SubjectIDs      []string                 `json:"subject_ids"`
	LanguageIDs     []string                 `json:"language_ids"`
	ClassSections   []model.ClassSectionPair `json:"class_sections"`
}

// SubmitProfile handles POST /teacher-auth/profile (Step 5)
func (h *TeacherAuthHandler) SubmitProfile(c *gin.Context) {
	var req submitProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		log.Printf("submit profile bind error: %v", err)
		response.BadRequest(c, err.Error())
		return
	}

	result, err := h.svc.SubmitProfile(c.Request.Context(), service.SubmitProfileInput{
		TempToken:       req.TempToken,
		Address:         req.Address,
		AlternateMobile: req.AlternateMobile,
		PincodeID:       req.PincodeID,
		GenderID:        req.GenderID,
		QualificationID: req.QualificationID,
		SubjectIDs:      req.SubjectIDs,
		LanguageIDs:     req.LanguageIDs,
		ClassSections:   req.ClassSections,
	})
	if err != nil {
		log.Printf("submit profile failed: err=%v", err)
		response.BadRequest(c, err.Error())
		return
	}

	response.OK(c, gin.H{
		"message": "profile saved",
		"status":  result.Status,
	})
}

func optionsToJSON(options []model.MasterOption) []gin.H {
	out := make([]gin.H, len(options))
	for i, o := range options {
		out[i] = gin.H{"id": o.ID, "name": o.Name}
	}
	return out
}

func classesToJSON(classes []model.ClassOption) []gin.H {
	out := make([]gin.H, len(classes))
	for i, cl := range classes {
		out[i] = gin.H{
			"id":       cl.ID,
			"name":     cl.Name,
			"sections": optionsToJSON(cl.Sections),
		}
	}
	return out
}
