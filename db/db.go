// Package db provides a reusable connection pool for MSSQL.
package db

import (
	"database/sql"
	"fmt"
	"loginmodule_99/integration"
	"loginmodule_99/tomlloader"
	"loginmodule_99/util"
)

// Pool is the shared *sql.DB connection pool used across handlers.
// Initialize it with Init and access via Get().
var Pool *sql.DB

// Init initializes the MSSQL connection using integration.NewMSSQL and
// exposes the underlying *sql.DB as the shared Pool.
func Init(cfg tomlloader.DBSection, log *util.Logger) error {
	dbw, err := integration.NewMSSQL(cfg, log)
	if err != nil {
		return fmt.Errorf("integration.NewMSSQL: %w", err)
	}
	Pool = dbw.DB
	return nil
}

// Get returns the shared *sql.DB pool. Call Init first.
func Get() *sql.DB {
	return Pool
}

// Close closes the pool if present.
func Close() error {
	if Pool != nil {
		return Pool.Close()
	}
	return nil
}
