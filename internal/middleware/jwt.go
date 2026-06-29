package middleware

import (
	"log"
	"strings"

	pkgjwt "auth-service/pkg/jwt"
	"auth-service/pkg/response"

	"github.com/gin-gonic/gin"
)

func JWTMiddleware(jwtManager *pkgjwt.Manager) gin.HandlerFunc {
	return func(c *gin.Context) {
		log.Printf("[JWT] %s %s", c.Request.Method, c.Request.URL.Path)

		authHeader := c.GetHeader("Authorization")
		if authHeader == "" || !strings.HasPrefix(authHeader, "Bearer ") {
			log.Printf("[JWT] rejected: missing or invalid Authorization header — %s %s", c.Request.Method, c.Request.URL.Path)
			response.Unauthorized(c, "missing or invalid authorization header")
			c.Abort()
			return
		}

		rawToken := strings.TrimPrefix(authHeader, "Bearer ")

		claims, err := jwtManager.Verify(rawToken)
		if err != nil {
			log.Printf("[JWT] rejected: token verification failed — %s %s — %v", c.Request.Method, c.Request.URL.Path, err)
			response.Unauthorized(c, "invalid or expired token")
			c.Abort()
			return
		}

		log.Printf("[JWT] accepted: user_id=%s role=%s chain_id=%s — %s %s", claims.UserID, claims.Role, claims.ChainID, c.Request.Method, c.Request.URL.Path)

		c.Set("user_id", claims.UserID)
		c.Set("role", claims.Role)
		c.Set("management_type", claims.ManagementType)
		c.Set("management_id", claims.ManagementID)
		c.Set("tenant_db", claims.TenantDB)
		c.Set("chain_id", claims.ChainID)

		c.Next()
	}
}
