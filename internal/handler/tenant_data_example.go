package handler

import (
	"net/http"

	"auth-service/internal/middleware"

	"github.com/gin-gonic/gin"
)

// Example handler showing how to access tenant DB pool
type TenantDataHandler struct {
	// Add your services here if needed
}

// NewTenantDataHandler creates a new tenant data handler
func NewTenantDataHandler() *TenantDataHandler {
	return &TenantDataHandler{}
}

// InsertData example handler for inserting data into tenant DB
func (h *TenantDataHandler) InsertData(c *gin.Context) {
	// Get tenant ID from context
	tenantID, err := middleware.GetTenantID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get tenant DB pool from context
	tenantDB, err := middleware.GetTenantDB(c)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Use tenant DB to insert data
	// Example: INSERT INTO tenant_table VALUES (...)
	query := `
		INSERT INTO your_table (column1, column2, created_at) 
		VALUES ($1, $2, NOW())
		RETURNING id
	`

	var id int
	err = tenantDB.QueryRow(c.Request.Context(), query, "value1", "value2").Scan(&id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "failed to insert data",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"id":      id,
		"mid":     tenantID,
	})
}

// UpdateData example handler for updating data in tenant DB
func (h *TenantDataHandler) UpdateData(c *gin.Context) {
	// Get tenant ID from context
	tenantID, err := middleware.GetTenantID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get tenant DB pool from context
	tenantDB, err := middleware.GetTenantDB(c)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Parse ID from request
	id := c.Param("id")

	// Use tenant DB to update data
	query := `
		UPDATE your_table 
		SET column1 = $1, column2 = $2, updated_at = NOW()
		WHERE id = $3
		RETURNING id
	`

	err = tenantDB.QueryRow(c.Request.Context(), query, "new_value1", "new_value2", id).Scan(&id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "failed to update data",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"id":      id,
		"mid":     tenantID,
	})
}

// GetData example handler for reading data from tenant DB
func (h *TenantDataHandler) GetData(c *gin.Context) {
	// Get tenant ID from context
	tenantID, err := middleware.GetTenantID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get tenant DB pool from context
	tenantDB, err := middleware.GetTenantDB(c)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	id := c.Param("id")

	// Use tenant DB to query data
	query := `
		SELECT id, column1, column2, created_at 
		FROM your_table 
		WHERE id = $1
	`

	var data struct {
		ID        int
		Column1   string
		Column2   string
		CreatedAt string
	}

	err = tenantDB.QueryRow(c.Request.Context(), query, id).Scan(
		&data.ID, &data.Column1, &data.Column2, &data.CreatedAt,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "failed to fetch data",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": data,
		"mid":  tenantID,
	})
}
