package handler

import (
	"auth-service/internal/service"
	"auth-service/pkg/response"

	"github.com/gin-gonic/gin"
)

type OTPHandler struct {
	otpSvc *service.OTPService
}

func NewOTPHandler(otpSvc *service.OTPService) *OTPHandler {
	return &OTPHandler{otpSvc: otpSvc}
}

type sendOTPRequest struct {
	TempToken string `json:"temp_token" binding:"required"`
}

type verifyOTPRequest struct {
	TempToken string `json:"temp_token" binding:"required"`
	OTP       string `json:"otp" binding:"required,len=6"`
}

func (h *OTPHandler) Send(c *gin.Context) {
	var req sendOTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "temp_token is required")
		return
	}

	if err := h.otpSvc.SendOTP(c.Request.Context(), req.TempToken); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	response.OK(c, gin.H{"message": "OTP sent"})
}

func (h *OTPHandler) Verify(c *gin.Context) {
	var req verifyOTPRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	_, err := h.otpSvc.VerifyOTP(c.Request.Context(), req.TempToken, req.OTP)
	if err != nil {
		response.Unauthorized(c, err.Error())
		return
	}

	response.OK(c, gin.H{"message": "OTP verified", "status": "otp_verified"})
}
