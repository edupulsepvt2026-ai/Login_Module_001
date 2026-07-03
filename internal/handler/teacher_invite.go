package handler

import (
	"encoding/csv"
	"fmt"
	"io"
	"log"
	"path/filepath"
	"strings"

	"auth-service/internal/middleware"
	"auth-service/internal/service"
	"auth-service/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/xuri/excelize/v2"
)

type TeacherInviteHandler struct {
	svc *service.TeacherInviteService
}

func NewTeacherInviteHandler(svc *service.TeacherInviteService) *TeacherInviteHandler {
	return &TeacherInviteHandler{svc: svc}
}

// DownloadTemplate handles GET /tenant/teachers/template
// Returns a pre-formatted Excel file the tenant admin can fill and upload.
func (h *TeacherInviteHandler) DownloadTemplate(c *gin.Context) {
	f := excelize.NewFile()
	defer f.Close()

	sheet := "Teachers"
	f.NewSheet(sheet)
	f.DeleteSheet("Sheet1")

	headers := []string{"name", "email", "phone"}
	for i, h := range headers {
		cell, _ := excelize.CoordinatesToCellName(i+1, 1)
		f.SetCellValue(sheet, cell, h)
	}

	// Sample row so the user knows the expected format
	samples := []string{"Anand Krishnan", "anand.k@school.edu.in", "+919876500001"}
	for i, v := range samples {
		cell, _ := excelize.CoordinatesToCellName(i+1, 2)
		f.SetCellValue(sheet, cell, v)
	}

	buf, err := f.WriteToBuffer()
	if err != nil {
		response.InternalError(c, "failed to generate template")
		return
	}

	c.Header("Content-Disposition", "attachment; filename=\"teacher_invite_template.xlsx\"")
	c.Data(200, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", buf.Bytes())
}

// InviteSingle handles POST /tenant/teachers/invite
func (h *TeacherInviteHandler) InviteSingle(c *gin.Context) {
	var body struct {
		Name  string  `json:"name"  binding:"required"`
		Email *string `json:"email"`
		Phone *string `json:"phone"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		log.Printf("[TeacherInvite] rejected: invalid request body — %s %s — %v", c.Request.Method, c.Request.URL.Path, err)
		response.BadRequest(c, err.Error())
		return
	}

	chainID, branchID, ok := tenantClaims(c)
	if !ok {
		log.Printf("[TeacherInvite] rejected: missing tenant identity in token — %s %s", c.Request.Method, c.Request.URL.Path)
		response.Unauthorized(c, "missing tenant identity in token")
		return
	}
	userID, ok := userIDClaim(c)
	if !ok {
		log.Printf("[TeacherInvite] rejected: missing user identity in token — %s %s", c.Request.Method, c.Request.URL.Path)
		response.Unauthorized(c, "missing user identity in token")
		return
	}
	pool, err := middleware.GetTenantDB(c)
	if err != nil {
		log.Printf("[TeacherInvite] rejected: tenant database unavailable — %s %s — %v", c.Request.Method, c.Request.URL.Path, err)
		response.InternalError(c, "tenant database unavailable")
		return
	}

	result, err := h.svc.InviteSingle(c.Request.Context(), pool, userID, chainID, branchID, service.TeacherInviteInput{
		Name:  body.Name,
		Email: body.Email,
		Phone: body.Phone,
	})
	if err != nil {
		log.Printf("[TeacherInvite] rejected: invite failed — chain_id=%s branch_id=%s — %s %s — %v", chainID, branchID, c.Request.Method, c.Request.URL.Path, err)
		response.BadRequest(c, err.Error())
		return
	}

	response.Created(c, gin.H{
		"invite_id":        result.InviteID,
		"name":             result.Name,
		"delivery_channel": result.DeliveryChannel,
		"message":          fmt.Sprintf("Invite sent to %s", result.Name),
	})
}

// BulkInvite handles POST /tenant/teachers/bulk-invite
// Accepts multipart/form-data with field "file" (.csv or .xlsx).
// Expected columns (first row is header): name, email, phone
func (h *TeacherInviteHandler) BulkInvite(c *gin.Context) {
	file, header, err := c.Request.FormFile("file")
	if err != nil {
		log.Printf("[TeacherInvite] rejected: file field missing — %s %s — %v", c.Request.Method, c.Request.URL.Path, err)
		response.BadRequest(c, "file field is required")
		return
	}
	defer file.Close()

	ext := strings.ToLower(filepath.Ext(header.Filename))
	var inputs []service.TeacherInviteInput

	switch ext {
	case ".csv":
		inputs, err = parseTeacherCSV(file)
	case ".xlsx":
		inputs, err = parseTeacherExcel(file)
	default:
		log.Printf("[TeacherInvite] rejected: unsupported file type %q — %s %s", ext, c.Request.Method, c.Request.URL.Path)
		response.BadRequest(c, "unsupported file type — use .csv or .xlsx")
		return
	}
	if err != nil {
		log.Printf("[TeacherInvite] rejected: failed to parse file %q — %s %s — %v", header.Filename, c.Request.Method, c.Request.URL.Path, err)
		response.BadRequest(c, fmt.Sprintf("failed to parse file: %v", err))
		return
	}
	if len(inputs) == 0 {
		log.Printf("[TeacherInvite] rejected: no valid rows found in file %q — %s %s", header.Filename, c.Request.Method, c.Request.URL.Path)
		response.BadRequest(c, "no valid rows found in file")
		return
	}

	chainID, branchID, ok := tenantClaims(c)
	if !ok {
		log.Printf("[TeacherInvite] rejected: missing tenant identity in token — %s %s", c.Request.Method, c.Request.URL.Path)
		response.Unauthorized(c, "missing tenant identity in token")
		return
	}
	userID, ok := userIDClaim(c)
	if !ok {
		log.Printf("[TeacherInvite] rejected: missing user identity in token — %s %s", c.Request.Method, c.Request.URL.Path)
		response.Unauthorized(c, "missing user identity in token")
		return
	}
	pool, err := middleware.GetTenantDB(c)
	if err != nil {
		log.Printf("[TeacherInvite] rejected: tenant database unavailable — %s %s — %v", c.Request.Method, c.Request.URL.Path, err)
		response.InternalError(c, "tenant database unavailable")
		return
	}

	result, err := h.svc.InviteBulk(c.Request.Context(), pool, userID, chainID, branchID, inputs)
	if err != nil {
		log.Printf("[TeacherInvite] rejected: bulk invite failed — chain_id=%s branch_id=%s — %s %s — %v", chainID, branchID, c.Request.Method, c.Request.URL.Path, err)
		response.InternalError(c, err.Error())
		return
	}
	log.Printf("[TeacherInvite] bulk invite processed: chain_id=%s branch_id=%s total=%d sent=%d failed=%d — %s %s", chainID, branchID, len(inputs), len(result.Sent), len(result.Failed), c.Request.Method, c.Request.URL.Path)

	response.OK(c, gin.H{
		"total":        len(inputs),
		"sent_count":   len(result.Sent),
		"failed_count": len(result.Failed),
		"sent":         result.Sent,
		"failed":       result.Failed,
	})
}

// tenantClaims extracts chain_id and management_id (branch_id) from JWT claims.
func tenantClaims(c *gin.Context) (chainID, branchID string, ok bool) {
	cid, _ := c.Get("chain_id")
	chainID, ok1 := cid.(string)
	mid, _ := c.Get("management_id")
	branchID, ok2 := mid.(string)
	ok = ok1 && ok2 && chainID != "" && branchID != ""
	return
}

// userIDClaim extracts user_id (the caller's own user id) from JWT claims.
func userIDClaim(c *gin.Context) (userID string, ok bool) {
	uid, _ := c.Get("user_id")
	userID, ok = uid.(string)
	ok = ok && userID != ""
	return
}

// parseTeacherCSV parses a CSV file with header row: name, email, phone
func parseTeacherCSV(r io.Reader) ([]service.TeacherInviteInput, error) {
	reader := csv.NewReader(r)
	rows, err := reader.ReadAll()
	if err != nil {
		return nil, err
	}
	if len(rows) < 2 {
		return nil, nil
	}

	header := normaliseHeader(rows[0])
	nameIdx, emailIdx, phoneIdx := colIndex(header, "name"), colIndex(header, "email"), colIndex(header, "phone")
	if nameIdx < 0 {
		return nil, fmt.Errorf("missing required column: name")
	}

	var inputs []service.TeacherInviteInput
	for _, row := range rows[1:] {
		name := safeCol(row, nameIdx)
		if name == "" {
			continue
		}
		inputs = append(inputs, service.TeacherInviteInput{
			Name:  name,
			Email: strPtrCol(row, emailIdx),
			Phone: strPtrCol(row, phoneIdx),
		})
	}
	return inputs, nil
}

// parseTeacherExcel parses an .xlsx file with header row: name, email, phone (first sheet)
func parseTeacherExcel(r io.Reader) ([]service.TeacherInviteInput, error) {
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

	header := normaliseHeader(rows[0])
	nameIdx, emailIdx, phoneIdx := colIndex(header, "name"), colIndex(header, "email"), colIndex(header, "phone")
	if nameIdx < 0 {
		return nil, fmt.Errorf("missing required column: name")
	}

	var inputs []service.TeacherInviteInput
	for _, row := range rows[1:] {
		name := safeCol(row, nameIdx)
		if name == "" {
			continue
		}
		inputs = append(inputs, service.TeacherInviteInput{
			Name:  name,
			Email: strPtrCol(row, emailIdx),
			Phone: strPtrCol(row, phoneIdx),
		})
	}
	return inputs, nil
}

func normaliseHeader(row []string) []string {
	out := make([]string, len(row))
	for i, v := range row {
		out[i] = strings.ToLower(strings.TrimSpace(v))
	}
	return out
}

func colIndex(header []string, name string) int {
	for i, h := range header {
		if h == name {
			return i
		}
	}
	return -1
}

func safeCol(row []string, idx int) string {
	if idx < 0 || idx >= len(row) {
		return ""
	}
	return strings.TrimSpace(row[idx])
}

func strPtrCol(row []string, idx int) *string {
	v := safeCol(row, idx)
	if v == "" {
		return nil
	}
	return &v
}
