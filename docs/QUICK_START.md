# Multi-Tenant DB System - Quick Start Guide

## Step 1: Database Setup

1. Apply the migration to your master database:
```bash
psql -U postgres -d master_db -f db_migrations/03_coresetting_schema.sql
```

2. Insert your tenant credentials in the coresetting table:
```sql
INSERT INTO coresetting (mid, key, value) VALUES
('your_vendor_id', 'tenant_db_host', 'tenant.example.com'),
('your_vendor_id', 'tenant_db_port', '5432'),
('your_vendor_id', 'tenant_db_user', 'tenant_user'),
('your_vendor_id', 'tenant_db_password', 'secure_pass'),
('your_vendor_id', 'tenant_db_name', 'tenant_database');
```

## Step 2: Environment Configuration

1. Copy `.env.example` to `.env`:
```bash
cp .env.example .env
```

2. Update with your actual database credentials:
```env
MASTER_DB_HOST=your_master_host
MASTER_DB_NAME=master_db
TENANT_POOL_EXPIRY_MINUTES=30
```

## Step 3: Verify Current Implementation

The following components are now in place:

### Files Modified:
- ✅ `db/tenant.go` - Tenant pool manager with expiry
- ✅ `internal/config/config.go` - Added TenantPoolExpiryMinutes
- ✅ `internal/middleware/tenant.go` - Middleware to extract mid and manage pools
- ✅ `internal/repository/coresetting.go` - Fetch credentials from master DB
- ✅ `internal/router/router.go` - Added tenant route group with middleware
- ✅ `cmd/server/main.go` - Initialize everything + background cleanup

### Files Created:
- ✅ `internal/handler/tenant_data_example.go` - Example handlers
- ✅ `db_migrations/03_coresetting_schema.sql` - Schema + sample data
- ✅ `.env.example` - Configuration template
- ✅ `docs/MULTI_TENANT_DB_GUIDE.md` - Complete documentation

## Step 4: Test the System

### Test Request 1: Insert Data

```bash
curl -X POST http://localhost:8080/tenant/data/insert \
  -H "X-Tenant-MID: vendor_001" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}'
```

### Test Request 2: Update Data

```bash
curl -X POST http://localhost:8080/tenant/data/update/1 \
  -H "X-Tenant-MID: vendor_001" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}'
```

### Test Request 3: Get Data

```bash
curl -X GET http://localhost:8080/tenant/data/1 \
  -H "X-Tenant-MID: vendor_001" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN"
```

### Test Request 4: Different Vendor (New Pool Created)

```bash
curl -X POST http://localhost:8080/tenant/data/insert \
  -H "X-Tenant-MID: vendor_002" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}'
```

## Step 5: Integrating Your Handlers

### Example: Add Your Own Handler

1. Create your handler:
```go
// internal/handler/my_handler.go
type MyHandler struct {
    service *service.MyService
}

func (h *MyHandler) GetUserData(c *gin.Context) {
    // Get tenant DB
    tenantDB, err := middleware.GetTenantDB(c)
    if err != nil {
        c.JSON(400, gin.H{"error": err.Error()})
        return
    }
    
    // Get tenant ID
    tenantID, err := middleware.GetTenantID(c)
    if err != nil {
        c.JSON(400, gin.H{"error": err.Error()})
        return
    }
    
    // Use tenantDB for queries
    query := "SELECT * FROM users WHERE id = $1"
    var user User
    err = tenantDB.QueryRow(c.Request.Context(), query, userID).Scan(&user.ID, &user.Name)
    if err != nil {
        c.JSON(500, gin.H{"error": "query failed"})
        return
    }
    
    c.JSON(200, user)
}
```

2. Add to handlers struct in `internal/router/router.go`:
```go
type Handlers struct {
    Invite  *handler.InviteHandler
    OTP     *handler.OTPHandler
    Auth    *handler.AuthHandler
    Refresh *handler.RefreshHandler
    Logout  *handler.LogoutHandler
    MyData  *handler.MyHandler  // Add this
}
```

3. Initialize in `cmd/server/main.go`:
```go
myHandler := handler.NewMyHandler(myService)
handlers := &router.Handlers{
    // ... existing ...
    MyData: myHandler,
}
```

4. Add routes in `internal/router/router.go`:
```go
tenant := r.Group("/tenant", 
    middleware.TenantDBMiddleware(tenantMgr), 
    middleware.JWTMiddleware(jwtManager))
{
    tenant.GET("/user/:id", h.MyData.GetUserData)  // Add your route
}
```

## Step 6: Pool Lifecycle Verification

### First Request with vendor_001
- Creates new pool connection to vendor_001's database
- Stores in global map with expiry = now + 30 min
- Returns pool to handler

### Subsequent Requests (within 30 min, same vendor)
- Pool found in map
- Returns immediately (no new connection)
- Very fast response

### Requests After 30 Minutes
- Background cleanup removes expired pool
- Next request creates new pool automatically

### Different Vendor (vendor_002)
- New pool created for vendor_002
- Stored separately in map
- Isolated connection pool for this vendor

## Step 7: Monitoring

### Monitor Pool Creation

Add logging to see when pools are created/reused:
```go
// In middleware or handler
log.Printf("Using tenant pool for mid: %s, expires at: %v", mid, expiryTime)
```

### Monitor Background Cleanup

Watch logs for:
```
cleaned up expired tenant DB pools
```

This appears every 5 minutes when cleanup runs.

## Common Operations

### Add New Vendor to System

1. Insert credentials in master DB:
```sql
INSERT INTO coresetting (mid, key, value) VALUES
('new_vendor', 'tenant_db_host', 'new.example.com'),
('new_vendor', 'tenant_db_port', '5432'),
('new_vendor', 'tenant_db_user', 'new_user'),
('new_vendor', 'tenant_db_password', 'new_pass'),
('new_vendor', 'tenant_db_name', 'new_db');
```

2. Make request with new mid header:
```bash
curl -X GET http://localhost:8080/tenant/data/1 \
  -H "X-Tenant-MID: new_vendor" \
  -H "Authorization: Bearer TOKEN"
```

Pool created automatically!

### Change Pool Expiry Duration

1. Update `.env`:
```env
TENANT_POOL_EXPIRY_MINUTES=60
```

2. Restart service

### Force Pool Cleanup

Pools are automatically cleaned every 5 minutes. To test manually, make a request after waiting for expiry time.

## Troubleshooting

### "missing required header: X-Tenant-MID"
- Add header to request: `-H "X-Tenant-MID: vendor_001"`

### "tenant pool for mid not found"
- First request creates pool (may take 1-2 seconds)
- Retry request
- Check coresetting table has the mid

### Connection refused error
- Verify tenant DB host/port in coresetting
- Check network connectivity
- Verify firewall rules

### Pool not cleaning up
- Check logs for cleanup messages
- Verify background goroutine is running
- Default cleanup every 5 minutes

## Architecture Summary

```
┌─────────────────────────────────────────────┐
│         Client Request with MID             │
├─────────────────────────────────────────────┤
│         TenantDBMiddleware                  │
│  • Extract mid from header                  │
│  • Call tenantMgr.GetOrLoad(mid)            │
├─────────────────────────────────────────────┤
│      TenantPoolManager                      │
│  • Check if pool in map?                    │
│  ├─ YES & not expired → return              │
│  └─ NO → fetch from coresetting → create    │
├─────────────────────────────────────────────┤
│    Global Pool Map (with expiry)            │
│  "vendor_001" → pool1 (expires 14:30)       │
│  "vendor_002" → pool2 (expires 14:45)       │
├─────────────────────────────────────────────┤
│         Handler (w/ pool in context)        │
│  • tenantDB := middleware.GetTenantDB(c)    │
│  • tenantDB.QueryRow(...).Scan(...)         │
├─────────────────────────────────────────────┤
│     Background Cleanup (every 5 min)        │
│  • Remove expired pools                     │
│  • Close connections                        │
└─────────────────────────────────────────────┘
```

## Next Steps

1. ✅ Run the migration on master DB
2. ✅ Configure your tenant databases in coresetting
3. ✅ Update `.env` with your settings
4. ✅ Build and run: `go run cmd/server/main.go`
5. ✅ Test with curl requests
6. ✅ Integrate your application handlers
7. ✅ Monitor logs for cleanup events

## Questions?

Refer to `docs/MULTI_TENANT_DB_GUIDE.md` for detailed documentation.
