package db

import (
	"context"
	"fmt"
	"sync"

	"github.com/jackc/pgx/v5/pgxpool"
)

// TenantPool manages one pgxpool per tenant DB.
// Keyed by tenant_db name (matches the JWT claim).
type TenantPool struct {
	mu    sync.RWMutex
	pools map[string]*pgxpool.Pool
}

var Tenant = &TenantPool{
	pools: make(map[string]*pgxpool.Pool),
}

func (t *TenantPool) Get(tenantDB string) (*pgxpool.Pool, error) {
	t.mu.RLock()
	pool, ok := t.pools[tenantDB]
	t.mu.RUnlock()

	if ok {
		return pool, nil
	}
	return nil, fmt.Errorf("tenant DB %q not registered", tenantDB)
}

func (t *TenantPool) Register(tenantDB, dsn string) error {
	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		return fmt.Errorf("failed to connect to tenant DB %q: %w", tenantDB, err)
	}

	if err := pool.Ping(context.Background()); err != nil {
		return fmt.Errorf("tenant DB %q ping failed: %w", tenantDB, err)
	}

	t.mu.Lock()
	t.pools[tenantDB] = pool
	t.mu.Unlock()

	return nil
}

func (t *TenantPool) Close() {
	t.mu.Lock()
	defer t.mu.Unlock()
	for _, pool := range t.pools {
		pool.Close()
	}
}
