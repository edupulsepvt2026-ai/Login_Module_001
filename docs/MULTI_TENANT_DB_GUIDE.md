# Multi-Tenant Database Connection Pool System

## Overview

This system implements vendor-based multi-tenant database access with automatic connection pooling and expiry management. Each vendor/tenant is identified by a unique `mid` (Merchant ID) and gets its own database connection pool that expires after a configured duration.

## Architecture

### Components

1. **Master Database** - Always connected constant connection for core data and credentials
2. **Tenant Pool Manager** - Global map managing tenant DB pools with expiry
3. **Credential Fetcher** - Fetches tenant DB credentials from master DB `coresetting` table
4. **Tenant Middleware** - Extracts mid from request header and manages DB pool lifecycle
5. **Background Cleanup** - Periodically removes expired pools

### Flow Diagram

```
Client Request with "X-Tenant-MID" header
        ↓
TenantDBMiddleware
        ↓
Check if pool exists in map & not expired
        ├─ YES → Use existing pool
        └─ NO → Check master DB coresetting table
                        ↓
                Fetch tenant DB credentials
                        ↓
                Create new connection pool
                        ↓
                Store in map with expiry time
                        ↓
Store pool in context → Handler Access
        ↓
Handler uses pool to query tenant DB
        ↓
On expiry → Background cleanup removes pool
```

## Configuration

Add to your `.env` file:

```env
# Master DB Configuration (constant connection)
MASTER_DB_HOST=localhost
MASTER_DB_PORT=5432
MASTER_DB_NAME=master_db
MASTER_DB_USER=postgres
MASTER_DB_PASSWORD=your_password

# Tenant Pool Expiry (in minutes) - change as needed, NOT stored in DB
TENANT_POOL_EXPIRY_MINUTES=30
```

## Master Database Schema - coresetting Table

The `coresetting` table stores tenant database credentials:

```sql
CREATE TABLE coresetting (
    id SERIAL PRIMARY KEY,
    mid VARCHAR(255) NOT NULL,           -- Merchant/Tenant ID (unique identifier)
    key VARCHAR(255) NOT NULL,           -- Setting key
    value TEXT NOT NULL,                 -- Setting value
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(mid, key)
);

-- Insert sample tenant credentials
INSERT INTO coresetting (mid, key, value) VALUES
('vendor_001', 'tenant_db_host', 'tenant1.example.com'),
('vendor_001', 'tenant_db_port', '5432'),
('vendor_001', 'tenant_db_user', 'tenant1_user'),
('vendor_001', 'tenant_db_password', 'secure_password_1'),
('vendor_001', 'tenant_db_name', 'tenant1_db'),
('vendor_002', 'tenant_db_host', 'tenant2.example.com'),
('vendor_002', 'tenant_db_port', '5432'),
('vendor_002', 'tenant_db_user', 'tenant2_user'),
('vendor_002', 'tenant_db_password', 'secure_password_2'),
('vendor_002', 'tenant_db_name', 'tenant2_db');
```

## Usage in Handlers

### Basic Handler Template

```go
func (h *MyHandler) HandleRequest(c *gin.Context) {
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

    // Use tenantDB for queries
    query := "INSERT INTO my_table (col1, col2) VALUES ($1, $2)"
    var id int
    err = tenantDB.QueryRow(c.Request.Context(), query, val1, val2).Scan(&id)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": "insert failed"})
        return
    }

    c.JSON(http.StatusOK, gin.H{
        "success": true,
        "id": id,
        "mid": tenantID,
    })
}
```

## API Usage

### Example Request

```bash
curl -X POST http://localhost:8080/tenant/data/insert \
  -H "X-Tenant-MID: vendor_001" \
  -H "Authorization: Bearer <jwt_token>" \
  -H "Content-Type: application/json" \
  -d '{"column1": "value1", "column2": "value2"}'
```

### Request Headers

- `X-Tenant-MID` or `mid` - The merchant/tenant ID (REQUIRED)
- `Authorization: Bearer <token>` - JWT token (if route is protected)

## Pool Lifecycle

### 1. Pool Creation on First Request

```
First request with mid="vendor_001"
    ↓
Pool not found in map
    ↓
Fetch credentials from master DB coresetting table
    ↓
Create pgxpool connection
    ↓
Store: map["vendor_001"] = &TenantPoolEntry{
    Pool: pgxpool,
    ExpiresAt: now + 30 minutes
}
    ↓
Return pool to handler
```

### 2. Pool Reuse on Subsequent Requests

```
Second request (within 30 min) with mid="vendor_001"
    ↓
Pool found in map
    ↓
Check: now < ExpiresAt?
    ├─ YES → Return existing pool (no new connection)
    └─ NO → Remove & create new pool
```

### 3. Automatic Cleanup

- Background goroutine runs every 5 minutes
- Scans all pools and removes expired ones
- Closes unused connections to free resources

## Key Features

### 1. **Automatic Connection Management**
- First request creates connection
- Subsequent requests reuse pool
- No manual pool creation needed

### 2. **Expiry-Based Cleanup**
- Configurable expiry duration (TOML/env: `TENANT_POOL_EXPIRY_MINUTES`)
- Background cleanup prevents resource leaks
- Expired pools automatically recreated on next request

### 3. **Isolation**
- Each tenant has isolated DB pool
- One tenant's connection issues don't affect others
- Credentials fetched per-tenant from master DB

### 4. **Performance**
- Global map for O(1) lookup
- Read-write locks for thread safety
- Connection pooling reduces DB overhead
- Background cleanup prevents connection exhaustion

## Thread Safety

The TenantPoolManager uses sync.RWMutex for thread-safe access:

```go
type TenantPoolManager struct {
    mu              sync.RWMutex      // Protects pools map
    pools           map[string]*TenantPoolEntry
    expiryDuration  time.Duration
    credentialFetch CredentialFetcher
}
```

- **Read operations** (Get) use RLock - multiple goroutines can read
- **Write operations** (GetOrLoad, Register) use Lock - exclusive access
- **Double-check pattern** prevents race conditions on pool creation

## Error Handling

### Common Errors and Solutions

1. **"missing required header: X-Tenant-MID"**
   - Cause: Request doesn't include mid header
   - Solution: Add header to request

2. **"tenant pool for mid 'vendor_001' not found"**
   - Cause: Pool not initialized yet or expired
   - Solution: First request creates pool automatically; retry

3. **"failed to fetch credentials for mid 'vendor_001'"**
   - Cause: mid not found in master DB coresetting table
   - Solution: Verify coresetting table has entry for that mid

4. **"incomplete tenant credentials"**
   - Cause: Missing required credential keys in coresetting
   - Solution: Ensure all 5 keys exist: host, port, user, password, dbname

## Integration Example

### Adding Tenant-Specific Routes

In `internal/router/router.go`, routes under `/tenant` group get tenant middleware:

```go
// Routes requiring mid header and JWT
tenant := r.Group("/tenant", 
    middleware.TenantDBMiddleware(tenantMgr), 
    middleware.JWTMiddleware(jwtManager))
{
    tenant.POST("/data/insert", handlers.Data.Insert)
    tenant.POST("/data/update", handlers.Data.Update)
    tenant.GET("/data/:id", handlers.Data.Get)
}
```

### Binding in main.go

```go
// In main function
dataHandler := handler.NewTenantDataHandler()
handlers := &router.Handlers{
    // ... existing handlers ...
    Data: dataHandler,  // Add your tenant handler
}

// Pass tenantMgr to Setup
r := router.Setup(handlers, jwtManager, tenantMgr)
```

## Monitoring & Debugging

### Check Pool Status

```go
// In a debug endpoint (if needed)
func GetPoolStatus(tenantMgr *db.TenantPoolManager) map[string]interface{} {
    // Access via reflection or add public method if needed
    return map[string]interface{}{
        "status": "pools active",
        // Add custom debug info
    }
}
```

### Log Cleanup Events

Background cleanup logs:
```
cleaned up expired tenant DB pools
```

Monitor these logs to verify automatic cleanup is working.

## Security Considerations

1. **Credentials in Master DB**
   - Tenant credentials stored only in master DB
   - Never logged or exposed in responses
   - Master DB should be well-protected

2. **Expiry Duration**
   - Configurable via ENV, not hardcoded
   - Can be changed without redeployment (restart required)
   - Prevents stale connections

3. **mid Header Validation**
   - mid extracted from header
   - Used directly to fetch credentials from DB
   - Ensure proper access control on who can set this header

4. **Connection Isolation**
   - Each tenant connection is independent
   - No cross-tenant data leakage possible
   - pgxpool provides query-level isolation

## Performance Tuning

### Expiry Duration Tuning

**Short expiry (5-10 min):**
- Pro: Minimal memory usage for unused pools
- Con: More connection creation overhead

**Long expiry (60+ min):**
- Pro: Better performance, reuse connections
- Con: More memory for unused pools

**Recommended: 30 minutes** (default)

### Connection Pool Settings

If needed, add pgxpool configuration:

```go
// In BuildDSN or new connection settings
config, err := pgxpool.ParseConfig(dsn)
config.MaxConns = 10
config.MinConns = 2
pool, err := pgxpool.NewWithConfig(ctx, config)
```

## Troubleshooting

### All Requests Return "mid not found"

1. Check mid header is being sent
2. Verify mid exists in coresetting table
3. Check master DB connection is active

### Pools Not Being Cleaned Up

1. Verify background cleanup goroutine is running
2. Check logs for cleanup messages
3. Ensure tenantMgr.Close() called on shutdown

### Connection Errors

1. Verify tenant DB credentials in coresetting
2. Check network connectivity to tenant DB
3. Verify firewall rules
4. Test credential manually with psql

## Best Practices

1. **Always use context.Context** for cancellation support
2. **Handle errors properly** - provide meaningful error messages
3. **Use tx** for multi-statement operations requiring atomicity
4. **Close resources** - ensure deferred cleanup in handlers
5. **Monitor pool health** - add metrics for pool creation/reuse
6. **Document credentials** - maintain accurate coresetting table
7. **Version migrations** - manage schema changes per tenant
8. **Test with multiple mids** - verify isolation works
