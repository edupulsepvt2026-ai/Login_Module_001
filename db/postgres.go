package db

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"loginmodule_99/tomlloader"
	"loginmodule_99/util"
)

// MasterPool is the shared pgxpool for the master PostgreSQL database.
// Initialized at startup via InitMaster. Used by all master-DB handlers.
var MasterPool *pgxpool.Pool

// InitMaster creates and validates the pgxpool connection pool for the master DB.
func InitMaster(cfg tomlloader.PGSection, log *util.Logger) error {
	dsn := fmt.Sprintf(
		"host=%s port=%d dbname=%s user=%s password=%s sslmode=disable connect_timeout=%d",
		cfg.Host, cfg.Port, cfg.Name, cfg.User, cfg.Password, cfg.ConnectTimeoutSecs,
	)

	poolCfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return fmt.Errorf("pgxpool.ParseConfig: %w", err)
	}

	poolCfg.MaxConns = cfg.MaxConns
	poolCfg.MinConns = cfg.MinConns
	poolCfg.MaxConnLifetime = time.Duration(cfg.MaxConnLifetimeMins) * time.Minute
	poolCfg.MaxConnIdleTime = time.Duration(cfg.MaxConnIdleMins) * time.Minute

	pool, err := pgxpool.NewWithConfig(context.Background(), poolCfg)
	if err != nil {
		return fmt.Errorf("pgxpool.NewWithConfig: %w", err)
	}

	if err := pool.Ping(context.Background()); err != nil {
		pool.Close()
		return fmt.Errorf("master db ping failed: %w", err)
	}

	stat := pool.Stat()
	log.Info("master postgres pool ready — max=%d min=%d total=%d idle=%d",
		cfg.MaxConns, cfg.MinConns, stat.TotalConns(), stat.IdleConns())

	MasterPool = pool
	return nil
}

// GetMaster returns the shared master pgxpool. Call InitMaster first.
func GetMaster() *pgxpool.Pool {
	return MasterPool
}

// CloseMaster closes the master pool gracefully.
func CloseMaster() {
	if MasterPool != nil {
		MasterPool.Close()
	}
}
