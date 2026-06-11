package router

import (
	"auth-service/internal/handler"
	"auth-service/internal/middleware"
	pkgjwt "auth-service/pkg/jwt"

	"github.com/gin-gonic/gin"
)

type Handlers struct {
	Invite  *handler.InviteHandler
	OTP     *handler.OTPHandler
	Auth    *handler.AuthHandler
	Refresh *handler.RefreshHandler
	Logout  *handler.LogoutHandler
}

func Setup(h *Handlers, jwtManager *pkgjwt.Manager) *gin.Engine {
	r := gin.Default()

	// public routes — no JWT required
	public := r.Group("/auth")
	{
		public.POST("/invite/verify", h.Invite.VerifyToken)
		public.POST("/invite/set-password", h.Invite.SetPassword)
		public.POST("/otp/send", h.OTP.Send)
		public.POST("/otp/verify", h.OTP.Verify)
		public.POST("/login", h.Auth.Login)
		public.POST("/refresh", h.Refresh.Refresh)
	}

	// protected routes — JWT required
	protected := r.Group("/auth", middleware.JWTMiddleware(jwtManager))
	{
		protected.POST("/logout", h.Logout.Logout)
	}

	return r
}
