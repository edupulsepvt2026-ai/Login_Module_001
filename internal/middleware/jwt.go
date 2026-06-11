package middleware

import (
	"strings"

	pkgjwt "auth-service/pkg/jwt"
	"auth-service/pkg/response"

	"github.com/gin-gonic/gin"
)

func JWTMiddleware(jwtManager *pkgjwt.Manager) gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" || !strings.HasPrefix(authHeader, "Bearer ") {
			response.Unauthorized(c, "missing or invalid authorization header")
			c.Abort()
			return
		}

		rawToken := strings.TrimPrefix(authHeader, "Bearer ")

		claims, err := jwtManager.Verify(rawToken)
		if err != nil {
			response.Unauthorized(c, "invalid or expired token")
			c.Abort()
			return
		}

		c.Set("user_id", claims.UserID)
		c.Set("role", claims.Role)
		c.Set("management_type", claims.ManagementType)
		c.Set("management_id", claims.ManagementID)
		c.Set("tenant_db", claims.TenantDB)
		c.Set("chain_id", claims.ChainID)

		c.Next()
	}
}
