package db

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// TenantDBCredentials holds connection settings for a tenant DB.
type TenantDBCredentials struct {
	Host               string
	Port               string
	User               string
	Password           string
	DBName             string
	SSLMode            string
	MaxConns           int32
	MinConns           int32
	ConnectTimeoutSecs int32
}

// TenantPoolEntry holds a pool and its expiry time
type TenantPoolEntry struct {
	Pool      *pgxpool.Pool
	ExpiresAt time.Time
}

// TenantPoolManager manages tenant DB pools with expiry
// Keyed by mid (merchant ID / tenant ID)
type TenantPoolManager struct {
	mu              sync.RWMutex
	pools           map[string]*TenantPoolEntry
	expiryDuration  time.Duration
	credentialFetch CredentialFetcher
}

// CredentialFetcher interface for fetching tenant credentials
type CredentialFetcher interface {
	GetTenantCredentials(ctx context.Context, mid string) (TenantDBCredentials, error)
}

// NewTenantPoolManager creates a new tenant pool manager
func NewTenantPoolManager(expiryDuration time.Duration, fetcher CredentialFetcher) *TenantPoolManager {
	return &TenantPoolManager{
		pools:           make(map[string]*TenantPoolEntry),
		expiryDuration:  expiryDuration,
		credentialFetch: fetcher,
	}
}

// Get retrieves a pool for the given mid, returns error if not found or expired
func (tm *TenantPoolManager) Get(ctx context.Context, mid string) (*pgxpool.Pool, error) {
	tm.mu.RLock()
	entry, ok := tm.pools[mid]
	tm.mu.RUnlock()

	if !ok {
		return nil, fmt.Errorf("tenant pool for mid %q not found", mid)
	}

	// Check if pool is expired
	if time.Now().After(entry.ExpiresAt) {
		// Pool expired, remove it
		tm.mu.Lock()
		delete(tm.pools, mid)
		entry.Pool.Close()
		tm.mu.Unlock()
		return nil, fmt.Errorf("tenant pool for mid %q expired", mid)
	}

	return entry.Pool, nil
}

// GetOrLoad retrieves an existing pool or loads a new one based on mid
// Fetches credentials from master DB and creates new connection if needed
func (tm *TenantPoolManager) GetOrLoad(ctx context.Context, mid string) (*pgxpool.Pool, error) {
	// Try to get existing pool
	pool, err := tm.Get(ctx, mid)
	if err == nil {
		return pool, nil
	}

	// Pool not found or expired, create new one
	tm.mu.Lock()
	defer tm.mu.Unlock()

	// Double-check after acquiring write lock
	if entry, ok := tm.pools[mid]; ok && time.Now().Before(entry.ExpiresAt) {
		return entry.Pool, nil
	}

	// Fetch credentials from master DB
	creds, err := tm.credentialFetch.GetTenantCredentials(ctx, mid)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch credentials for mid %q: %w", mid, err)
	}

	// Build DSN and create new pool
	dsn := BuildDSN(creds.Host, creds.Port, creds.User, creds.Password, creds.DBName, creds.SSLMode)
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, fmt.Errorf("failed to parse tenant db config for mid %q: %w", mid, err)
	}

	if creds.MaxConns > 0 {
		cfg.MaxConns = creds.MaxConns
	}
	if creds.MinConns > 0 {
		cfg.MinConns = creds.MinConns
	}
	if creds.ConnectTimeoutSecs > 0 {
		cfg.ConnConfig.ConnectTimeout = time.Duration(creds.ConnectTimeoutSecs) * time.Second
	}

	newPool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("failed to create pool for mid %q: %w", mid, err)
	}

	// Ping to verify connection
	if err := newPool.Ping(ctx); err != nil {
		newPool.Close()
		return nil, fmt.Errorf("tenant DB ping failed for mid %q: %w", mid, err)
	}

	// Store in map with expiry
	tm.pools[mid] = &TenantPoolEntry{
		Pool:      newPool,
		ExpiresAt: time.Now().Add(tm.expiryDuration),
	}

	return newPool, nil
}

// Register manually registers a pool for a mid
func (tm *TenantPoolManager) Register(mid, dsn string) error {
	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		return fmt.Errorf("failed to connect to tenant pool for mid %q: %w", mid, err)
	}

	if err := pool.Ping(context.Background()); err != nil {
		pool.Close()
		return fmt.Errorf("tenant pool ping failed for mid %q: %w", mid, err)
	}

	tm.mu.Lock()
	defer tm.mu.Unlock()

	tm.pools[mid] = &TenantPoolEntry{
		Pool:      pool,
		ExpiresAt: time.Now().Add(tm.expiryDuration),
	}

	return nil
}

// Close closes all tenant pools
func (tm *TenantPoolManager) Close() {
	tm.mu.Lock()
	defer tm.mu.Unlock()
	for mid, entry := range tm.pools {
		entry.Pool.Close()
		delete(tm.pools, mid)
	}
}

// CleanupExpired removes expired pools (can be called periodically)
func (tm *TenantPoolManager) CleanupExpired() {
	tm.mu.Lock()
	defer tm.mu.Unlock()

	now := time.Now()
	for mid, entry := range tm.pools {
		if now.After(entry.ExpiresAt) {
			entry.Pool.Close()
			delete(tm.pools, mid)
		}
	}
}
