package handler

import (
	"encoding/csv"
	"fmt"
	"io"
	"log"
	"path/filepath"
	"strings"

	"auth-service/internal/config"
	"auth-service/internal/middleware"
	"auth-service/internal/service"
	"auth-service/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/xuri/excelize/v2"
)

type ParentInviteHandler struct {
	svc *service.ParentInviteService
	cfg *config.Config
}

func NewParentInviteHandler(svc *service.ParentInviteService, cfg *config.Config) *ParentInviteHandler {
	return &ParentInviteHandler{svc: svc, cfg: cfg}
}

// DownloadTemplate handles GET /teacher/parents/template
func (h *ParentInviteHandler) DownloadTemplate(c *gin.Context) {
	f := excelize.NewFile()
	defer f.Close()

	sheet := "Parents"
	f.NewSheet(sheet)
	f.DeleteSheet("Sheet1")

	headers := []string{"student_name", "class", "grade", "parent_name", "parent_email", "parent_mobile", "relationship_type"}
	for i, hdr := range headers {
		cell, _ := excelize.CoordinatesToCellName(i+1, 1)
		f.SetCellValue(sheet, cell, hdr)
	}

	// grade is the section label (e.g. "A"), not masters.grade — see docs/API_V4.0_PARENT_ONBOARDING.md
	samples := []string{"Kavin Raj", "Class 6", "A", "Suresh Raj", "suresh.raj@example.com", "+919876500011", "Father"}
	for i, v := range samples {
		cell, _ := excelize.CoordinatesToCellName(i+1, 2)
		f.SetCellValue(sheet, cell, v)
	}

	buf, err := f.WriteToBuffer()
	if err != nil {
		response.InternalError(c, "failed to generate template")
		return
	}

	c.Header("Content-Disposition", "attachment; filename=\"parent_invite_template.xlsx\"")
	c.Data(200, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", buf.Bytes())
}

type inviteParentRequest struct {
	StudentName        string  `json:"student_name" binding:"required"`
	ClassID            string  `json:"class_id"      binding:"required"`
	SectionID          string  `json:"section_id"    binding:"required"`
	ParentName         string  `json:"parent_name"   binding:"required"`
	ParentEmail        *string `json:"parent_email"`
	ParentMobile       *string `json:"parent_mobile"`
	RelationshipTypeID string  `json:"relationship_type_id" binding:"required"`
}

// InviteSingle handles POST /teacher/parents/invite
func (h *ParentInviteHandler) InviteSingle(c *gin.Context) {
	if !isTeacher(c) {
		response.Forbidden(c, "only teachers can invite parents")
		return
	}

	var body inviteParentRequest
	if err := c.ShouldBindJSON(&body); err != nil {
		log.Printf("[ParentInvite] rejected: invalid request body — %s %s — %v", c.Request.Method, c.Request.URL.Path, err)
		response.BadRequest(c, err.Error())
		return
	}

	chainID, branchID, ok := tenantClaims(c)
	if !ok {
		response.Unauthorized(c, "missing tenant identity in token")
		return
	}
	userID, ok := userIDClaim(c)
	if !ok {
		response.Unauthorized(c, "missing user identity in token")
		return
	}
	pool, err := middleware.GetTenantDB(c)
	if err != nil {
		response.InternalError(c, "tenant database unavailable")
		return
	}

	result, err := h.svc.InviteSingle(c.Request.Context(), pool, userID, chainID, branchID, h.cfg.CurrentAcademicYear, service.ParentInviteInput{
		StudentName:        body.StudentName,
		ClassID:            body.ClassID,
		SectionID:          body.SectionID,
		ParentName:         body.ParentName,
		ParentEmail:        body.ParentEmail,
		ParentPhone:        body.ParentMobile,
		RelationshipTypeID: body.RelationshipTypeID,
	})
	if err != nil {
		log.Printf("[ParentInvite] rejected: invite failed — chain_id=%s branch_id=%s — %s %s — %v", chainID, branchID, c.Request.Method, c.Request.URL.Path, err)
		response.BadRequest(c, err.Error())
		return
	}

	response.Created(c, parentInviteResultJSON(result))
}

// BulkInvite handles POST /teacher/parents/bulk-invite
// Accepts multipart/form-data with field "file" (.csv or .xlsx).
// Expected columns (first row is header):
//
//	student_name, class, grade, parent_name, parent_email, parent_mobile, relationship_type
func (h *ParentInviteHandler) BulkInvite(c *gin.Context) {
	if !isTeacher(c) {
		response.Forbidden(c, "only teachers can invite parents")
		return
	}

	file, header, err := c.Request.FormFile("file")
	if err != nil {
		response.BadRequest(c, "file field is required")
		return
	}
	defer file.Close()

	ext := strings.ToLower(filepath.Ext(header.Filename))
	var inputs []service.ParentInviteRawInput

	switch ext {
	case ".csv":
		inputs, err = parseParentCSV(file)
	case ".xlsx":
		inputs, err = parseParentExcel(file)
	default:
		response.BadRequest(c, "unsupported file type — use .csv or .xlsx")
		return
	}
	if err != nil {
		response.BadRequest(c, fmt.Sprintf("failed to parse file: %v", err))
		return
	}
	if len(inputs) == 0 {
		response.BadRequest(c, "no valid rows found in file")
		return
	}

	chainID, branchID, ok := tenantClaims(c)
	if !ok {
		response.Unauthorized(c, "missing tenant identity in token")
		return
	}
	userID, ok := userIDClaim(c)
	if !ok {
		response.Unauthorized(c, "missing user identity in token")
		return
	}
	pool, err := middleware.GetTenantDB(c)
	if err != nil {
		response.InternalError(c, "tenant database unavailable")
		return
	}

	result, err := h.svc.InviteBulk(c.Request.Context(), pool, userID, chainID, branchID, h.cfg.CurrentAcademicYear, inputs)
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}

	sent := make([]gin.H, len(result.Sent))
	for i, r := range result.Sent {
		sent[i] = parentInviteResultJSON(&r)
	}

	response.OK(c, gin.H{
		"total":        len(inputs),
		"sent_count":   len(result.Sent),
		"failed_count": len(result.Failed),
		"sent":         sent,
		"failed":       result.Failed,
	})
}

func isTeacher(c *gin.Context) bool {
	role, _ := c.Get("role")
	r, ok := role.(string)
	return ok && r == "teacher"
}

func parentInviteResultJSON(r *service.ParentInviteResult) gin.H {
	out := gin.H{
		"status":     r.Status,
		"student_id": r.StudentID,
	}
	if r.InviteID != "" {
		out["invite_id"] = r.InviteID
	}
	if r.DeliveryChannel != "" {
		out["delivery_channel"] = r.DeliveryChannel
	}
	switch r.Status {
	case "linked_to_existing_parent":
		out["message"] = fmt.Sprintf("%s is already registered — new child linked", r.ParentName)
	default:
		out["message"] = fmt.Sprintf("Invite sent to %s", r.ParentName)
	}
	return out
}

func parseParentCSV(r io.Reader) ([]service.ParentInviteRawInput, error) {
	rows, err := csv.NewReader(r).ReadAll()
	if err != nil {
		return nil, err
	}
	if len(rows) < 2 {
		return nil, nil
	}
	return rowsToParentInputs(rows)
}

func parseParentExcel(r io.Reader) ([]service.ParentInviteRawInput, error) {
	f, err := excelize.OpenReader(r)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	sheets := f.GetSheetList()
	if len(sheets) == 0 {
		return nil, fmt.Errorf("no sheets found")
	}

	rows, err := f.GetRows(sheets[0])
	if err != nil {
		return nil, err
	}
	if len(rows) < 2 {
		return nil, nil
	}
	return rowsToParentInputs(rows)
}

func rowsToParentInputs(rows [][]string) ([]service.ParentInviteRawInput, error) {
	header := normaliseHeader(rows[0])
	nameIdx := colIndex(header, "student_name")
	classIdx := colIndex(header, "class")
	gradeIdx := colIndex(header, "grade")
	parentNameIdx := colIndex(header, "parent_name")
	emailIdx := colIndex(header, "parent_email")
	mobileIdx := colIndex(header, "parent_mobile")
	relIdx := colIndex(header, "relationship_type")

	if nameIdx < 0 {
		return nil, fmt.Errorf("missing required column: student_name")
	}
	if classIdx < 0 {
		return nil, fmt.Errorf("missing required column: class")
	}
	if gradeIdx < 0 {
		return nil, fmt.Errorf("missing required column: grade")
	}
	if relIdx < 0 {
		return nil, fmt.Errorf("missing required column: relationship_type")
	}

	var inputs []service.ParentInviteRawInput
	for _, row := range rows[1:] {
		name := safeCol(row, nameIdx)
		if name == "" {
			continue
		}
		inputs = append(inputs, service.ParentInviteRawInput{
			StudentName:      name,
			Class:            safeCol(row, classIdx),
			Grade:            safeCol(row, gradeIdx),
			ParentName:       safeCol(row, parentNameIdx),
			ParentEmail:      strPtrCol(row, emailIdx),
			ParentPhone:      strPtrCol(row, mobileIdx),
			RelationshipType: safeCol(row, relIdx),
		})
	}
	return inputs, nil
}
