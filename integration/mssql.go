// Package integration manages external data-source connections.
// Currently supports Microsoft SQL Server via go-mssqldb.
package integration

import (
	"context"
	"database/sql"
	"fmt"
	"loginmodule_99/tomlloader"
	"loginmodule_99/util"
	"net/url"
	"time"

	_ "github.com/denisenkom/go-mssqldb" // register mssql driver
)

// DB wraps sql.DB with application-level helpers.
type DB struct {
	*sql.DB
	log *util.Logger
}

// NewMSSQL builds a connection string from config, opens the pool,
// and verifies connectivity with a ping.
func NewMSSQL(cfg tomlloader.DBSection, log *util.Logger) (*DB, error) {
	query := url.Values{}
	query.Set("database", cfg.Name)
	query.Set("connection timeout", fmt.Sprintf("%d", cfg.Timeout))
	if !cfg.Encrypt {
		query.Set("encrypt", "disable")
	}

	u := &url.URL{
		Scheme:   "sqlserver",
		User:     url.UserPassword(cfg.User, cfg.Password),
		Host:     fmt.Sprintf("%s:%d", cfg.Server, cfg.Port),
		RawQuery: query.Encode(),
	}

	log.Info("connecting to MSSQL at %s:%d db=%s", cfg.Server, cfg.Port, cfg.Name)

	sqlDB, err := sql.Open("sqlserver", u.String())
	if err != nil {
		return nil, fmt.Errorf("sql.Open: %w", err)
	}

	// Connection pool tuning – medium level as requested.
	sqlDB.SetMaxOpenConns(25)
	sqlDB.SetMaxIdleConns(10)
	sqlDB.SetConnMaxLifetime(5 * time.Minute)
	sqlDB.SetConnMaxIdleTime(2 * time.Minute)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := sqlDB.PingContext(ctx); err != nil {
		return nil, fmt.Errorf("ping mssql: %w", err)
	}

	log.Info("MSSQL connection established")
	return &DB{DB: sqlDB, log: log}, nil
}

// QueryRows is a convenience wrapper that logs the query and returns *sql.Rows.
func (db *DB) QueryRows(ctx context.Context, query string, args ...any) (*sql.Rows, error) {
	db.log.Info("QUERY: %s | args: %v", query, args)
	rows, err := db.QueryContext(ctx, query, args...)
	if err != nil {
		db.log.Error("query failed: %v", err)
		return nil, err
	}
	return rows, nil
}

// Exec wraps ExecContext with logging.
func (db *DB) Exec(ctx context.Context, query string, args ...any) (sql.Result, error) {
	db.log.Info("EXEC: %s | args: %v", query, args)
	res, err := db.ExecContext(ctx, query, args...)
	if err != nil {
		db.log.Error("exec failed: %v", err)
		return nil, err
	}
	return res, nil
}
