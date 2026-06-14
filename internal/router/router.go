package router

import (
	"auth-service/db"
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

func Setup(h *Handlers, jwtManager *pkgjwt.Manager, tenantMgr *db.TenantPoolManager) *gin.Engine {
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

	// tenant routes — requires tenant mid header and JWT
	// Add your tenant-specific routes here:
	// Example routes (uncomment and add handlers as needed):
	// tenant := r.Group("/tenant", middleware.TenantDBMiddleware(tenantMgr), middleware.JWTMiddleware(jwtManager))
	// {
	//    tenant.POST("/data/insert", h.Data.Insert)
	//    tenant.POST("/data/update", h.Data.Update)
	//    tenant.GET("/data/:id", h.Data.Get)
	// }

	// For now, register the tenant middleware group (even if empty)
	_ = r.Group("/tenant", middleware.TenantDBMiddleware(tenantMgr), middleware.JWTMiddleware(jwtManager))

	return r
}
