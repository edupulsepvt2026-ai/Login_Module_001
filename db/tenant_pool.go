package db

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"loginmodule_99/util"
)

// TenantPoolManager manages one pgxpool per tenant (school) database.
// Pools are created lazily on first use and cached for reuse.
// Thread-safe — safe to call from concurrent request handlers.
type TenantPoolManager struct {
	master *pgxpool.Pool
	pools  map[string]*pgxpool.Pool // chain_id → pool
	mu     sync.RWMutex
	log    *util.Logger
}

// tenantCredentials holds the connection details for a tenant DB.
// Fetched from infrastructure.chain_database in the master DB.
type tenantCredentials struct {
	Host     string
	Port     int
	DBName   string
	User     string
	Password string
}

// Manager is the global tenant pool manager. Init at startup via InitTenantManager.
var Manager *TenantPoolManager

// InitTenantManager sets up the global TenantPoolManager using the master pool.
// Call once at startup after InitMaster.
func InitTenantManager(master *pgxpool.Pool, log *util.Logger) {
	Manager = &TenantPoolManager{
		master: master,
		pools:  make(map[string]*pgxpool.Pool),
		log:    log,
	}
	log.Info("tenant pool manager initialised")
}

// GetTenantPool returns the pgxpool for the given chain_id.
// On the first call for a chain, it fetches credentials from the master DB,
// creates the pool, and caches it. All subsequent calls return the cached pool.
func (tm *TenantPoolManager) GetTenantPool(ctx context.Context, chainID string) (*pgxpool.Pool, error) {
	// ── fast path: pool already cached ──────────────────────────────────
	tm.mu.RLock()
	if pool, ok := tm.pools[chainID]; ok {
		tm.mu.RUnlock()
		return pool, nil
	}
	tm.mu.RUnlock()

	// ── slow path: create pool for the first time ────────────────────────
	tm.log.Info("creating new tenant pool", "chain_id", chainID)

	creds, err := tm.fetchCredentials(ctx, chainID)
	if err != nil {
		return nil, fmt.Errorf("GetTenantPool: fetch credentials: %w", err)
	}

	pool, err := tm.createPool(ctx, creds)
	if err != nil {
		return nil, fmt.Errorf("GetTenantPool: create pool: %w", err)
	}

	// ── cache the new pool (write lock, double-check to avoid race) ──────
	tm.mu.Lock()
	defer tm.mu.Unlock()
	if existing, ok := tm.pools[chainID]; ok {
		// Another goroutine beat us to it — use theirs, close ours
		pool.Close()
		return existing, nil
	}
	tm.pools[chainID] = pool

	tm.log.Info("tenant pool cached", "chain_id", chainID)
	return pool, nil
}

// EvictPool removes a tenant pool from the cache and closes it.
// Call this when a school's DB credentials change or DB is deprovisioned.
func (tm *TenantPoolManager) EvictPool(chainID string) {
	tm.mu.Lock()
	defer tm.mu.Unlock()
	if pool, ok := tm.pools[chainID]; ok {
		pool.Close()
		delete(tm.pools, chainID)
		tm.log.Info("tenant pool evicted", "chain_id", chainID)
	}
}

// CloseAll closes all cached tenant pools. Call on application shutdown.
func (tm *TenantPoolManager) CloseAll() {
	tm.mu.Lock()
	defer tm.mu.Unlock()
	for chainID, pool := range tm.pools {
		pool.Close()
		tm.log.Info("tenant pool closed", "chain_id", chainID)
	}
	tm.pools = make(map[string]*pgxpool.Pool)
}

// Stats returns the number of active cached tenant pools.
func (tm *TenantPoolManager) Stats() int {
	tm.mu.RLock()
	defer tm.mu.RUnlock()
	return len(tm.pools)
}

// ── internal helpers ──────────────────────────────────────────────────────────

// fetchCredentials queries infrastructure.chain_database in the master DB
// to get the connection details for a tenant school's local database.
func (tm *TenantPoolManager) fetchCredentials(ctx context.Context, chainID string) (*tenantCredentials, error) {
	query := `
		SELECT
			db_host,
			db_port,
			db_name,
			db_user,
			db_password_encrypted
		FROM infrastructure.chain_database
		WHERE chain_id  = $1
		  AND is_active = true
	`

	var creds tenantCredentials
	err := tm.master.QueryRow(ctx, query, chainID).Scan(
		&creds.Host,
		&creds.Port,
		&creds.DBName,
		&creds.User,
		&creds.Password, // TODO: decrypt using KMS before use
	)
	if err != nil {
		return nil, fmt.Errorf("fetchCredentials scan: %w", err)
	}

	return &creds, nil
}

// createPool builds and pings a new pgxpool for the given tenant credentials.
func (tm *TenantPoolManager) createPool(ctx context.Context, creds *tenantCredentials) (*pgxpool.Pool, error) {
	dsn := fmt.Sprintf(
		"host=%s port=%d dbname=%s user=%s password=%s sslmode=disable connect_timeout=10",
		creds.Host, creds.Port, creds.DBName, creds.User, creds.Password,
	)

	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, fmt.Errorf("ParseConfig: %w", err)
	}

	cfg.MaxConns = 10
	cfg.MinConns = 2
	cfg.MaxConnLifetime = 30 * time.Minute
	cfg.MaxConnIdleTime = 5 * time.Minute

	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("NewWithConfig: %w", err)
	}

	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("ping tenant DB: %w", err)
	}

	return pool, nil
}
