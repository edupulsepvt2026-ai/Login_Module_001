package middleware

import (
	"context"
	"fmt"

	"auth-service/db"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	// Context keys
	TenantIDContextKey = "tenant_id"
	TenantDBContextKey = "tenant_db"
	TenantMIDHeaderKey = "X-Tenant-MID" // or "mid" depending on your API spec
)

// TenantDBMiddleware extracts tenant mid from header and loads tenant DB pool
func TenantDBMiddleware(tenantMgr *db.TenantPoolManager) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Extract mid from header
		mid := c.GetHeader(TenantMIDHeaderKey)
		if mid == "" {
			// Try alternate header name
			mid = c.GetHeader("mid")
		}

		if mid == "" {
			c.JSON(400, gin.H{
				"error": fmt.Sprintf("missing required header: %s or mid", TenantMIDHeaderKey),
			})
			c.Abort()
			return
		}

		// Get or load tenant DB pool
		ctx := c.Request.Context()
		tenantPool, err := tenantMgr.GetOrLoad(ctx, mid)
		if err != nil {
			c.JSON(500, gin.H{
				"error": fmt.Sprintf("failed to load tenant database for mid %q: %v", mid, err),
			})
			c.Abort()
			return
		}

		// Store in context for handler access
		c.Set(TenantIDContextKey, mid)
		c.Set(TenantDBContextKey, tenantPool)

		// Also add to request context for direct context.Context usage
		newCtx := context.WithValue(ctx, TenantIDContextKey, mid)
		newCtx = context.WithValue(newCtx, TenantDBContextKey, tenantPool)
		c.Request = c.Request.WithContext(newCtx)

		c.Next()
	}
}

// GetTenantDB retrieves tenant DB pool from gin context
func GetTenantDB(c *gin.Context) (*pgxpool.Pool, error) {
	pool, ok := c.Get(TenantDBContextKey)
	if !ok {
		return nil, fmt.Errorf("tenant database not found in context")
	}

	tenantPool, ok := pool.(*pgxpool.Pool)
	if !ok {
		return nil, fmt.Errorf("tenant database context value is invalid type")
	}

	return tenantPool, nil
}

// GetTenantID retrieves tenant mid from gin context
func GetTenantID(c *gin.Context) (string, error) {
	mid, ok := c.Get(TenantIDContextKey)
	if !ok {
		return "", fmt.Errorf("tenant ID not found in context")
	}

	tenantID, ok := mid.(string)
	if !ok {
		return "", fmt.Errorf("tenant ID context value is invalid type")
	}

	return tenantID, nil
}

// GetTenantDBFromContext retrieves tenant DB pool from context.Context
func GetTenantDBFromContext(ctx context.Context) (*pgxpool.Pool, error) {
	pool, ok := ctx.Value(TenantDBContextKey).(*pgxpool.Pool)
	if !ok {
		return nil, fmt.Errorf("tenant database not found in context")
	}
	return pool, nil
}

// GetTenantIDFromContext retrieves tenant mid from context.Context
func GetTenantIDFromContext(ctx context.Context) (string, error) {
	mid, ok := ctx.Value(TenantIDContextKey).(string)
	if !ok {
		return "", fmt.Errorf("tenant ID not found in context")
	}
	return mid, nil
}
