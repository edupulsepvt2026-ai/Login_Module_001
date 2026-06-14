# Multi-Tenant Database System - Complete Architecture

## System Overview

This document provides a detailed view of how the multi-tenant database system works, from request to database access to pool management.

## 1. High-Level Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                     HTTP Requests from Vendors                   │
│                   (with X-Tenant-MID header)                     │
└─────────────────────────┬──────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────────┐
│                      Gin HTTP Router                             │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  /tenant routes with middleware stack:                  │   │
│  │  • TenantDBMiddleware (load pool based on mid)          │   │
│  │  • JWTMiddleware (validate token)                       │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────┬──────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────────┐
│            TenantDBMiddleware Execution                          │
│  1. Extract mid from X-Tenant-MID header                         │
│  2. Call tenantMgr.GetOrLoad(context, mid)                       │
│  3. Store pool + mid in request context                          │
└─────────────────────────┬──────────────────────────────────────┘
                          │
                          ▼
        ┌─────────────────────────────────┐
        │  Is pool in memory map already? │
        └─────────────────┬───────────────┘
                          │
         ┌────────────────┴────────────────┐
         │                                 │
         ▼ YES                             ▼ NO
    ┌─────────────┐              ┌──────────────────────┐
    │ Check expiry│              │ Fetch credentials    │
    │ time        │              │ from master DB       │
    └──────┬──────┘              │ (coresetting table)  │
           │                     └─────────┬────────────┘
     ┌─────┴─────┐                        │
     │           │                        ▼
   Valid    Expired            ┌──────────────────────┐
     │           │             │ Create new pgxpool   │
     ▼           ▼             │ connection           │
  Return    Remove &      ┌────┤ Ping to verify       │
  pool      retry         │    └──────────────────────┘
                          │
                          ▼
                ┌──────────────────────┐
                │ Store in memory map: │
                │ map[mid] = {         │
                │   Pool: pgxpool,     │
                │   ExpiresAt: time    │
                │ }                    │
                └──────────┬───────────┘
                           │
                           ▼
                ┌──────────────────────┐
                │ Set in gin context:  │
                │ context[TenantDB]    │
                │ context[TenantID]    │
                └──────────┬───────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Handler Execution                             │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ func (h *MyHandler) GetData(c *gin.Context) {           │   │
│  │   tenantDB, _ := middleware.GetTenantDB(c)              │   │
│  │   tenantID, _ := middleware.GetTenantID(c)              │   │
│  │   tenantDB.QueryRow(...).Scan(...)  // Use DB           │   │
│  │   c.JSON(200, result)                                  │   │
│  │ }                                                        │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────┬──────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────────┐
│              Tenant-Specific Database                            │
│  (SQL queries executed on tenant's isolated database)            │
└──────────────────────────────────────────────────────────────────┘
```

## 2. Component Interaction Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  CLIENT ──(X-Tenant-MID: vendor_001)──> ROUTER                   │
│                                            │                       │
│                                            ├─> TenantDBMiddleware │
│                                            │                       │
│                    ┌───────────────────────┘                       │
│                    │                                               │
│                    ▼                                               │
│  TENANT POOL MANAGER (Global Map)                                 │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  Memory Map:                          Background Cleanup:   │ │
│  │  ┌──────────────────────────────────┐ ┌────────────────────┤ │
│  │  │ "vendor_001" → PoolEntry        │ │ Every 5 minutes:   │ │
│  │  │ {                                │ │ • Check all pools  │ │
│  │  │   Pool: pgxpool                 │ │ • Remove expired   │ │
│  │  │   ExpiresAt: 2024-06-12 14:30   │ │ • Close conns      │ │
│  │  │ }                                │ └────────────────────┤ │
│  │  │                                  │                      │ │
│  │  │ "vendor_002" → PoolEntry        │                      │ │
│  │  │ {                                │                      │ │
│  │  │   Pool: pgxpool                 │                      │ │
│  │  │   ExpiresAt: 2024-06-12 14:45   │                      │ │
│  │  │ }                                │                      │ │
│  │  └──────────────────────────────────┘                      │ │
│  │           │                                                │ │
│  │           ├─ (not found?) → MASTER DB (coresetting)       │ │
│  │           │                                                │ │
│  │           ▼                                                │ │
│  │  Query: SELECT value FROM coresetting                    │ │
│  │          WHERE mid = $1 AND key = $2                     │ │
│  │                                                           │ │
│  │  Result: {                                               │ │
│  │    host: 'tenant.example.com',                           │ │
│  │    port: '5432',                                         │ │
│  │    user: 'tenant_user',                                  │ │
│  │    password: 'secure_pass',                              │ │
│  │    dbname: 'tenant_db'                                   │ │
│  │  }                                                        │ │
│  │                                                           │ │
│  │  Create new pool → Add to map → Return to handler       │ │
│  └─────────────────────────────────────────────────────────┘ │
│                    │                                           │
│                    ▼                                           │
│                 HANDLER (receives pool in context)             │
│                    │                                           │
│                    ▼                                           │
│         TENANT DATABASE (vendor_001_db)                        │
│         Query results returned to handler                      │
│                    │                                           │
│                    ▼                                           │
│              Response to Client                               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## 3. Memory State Diagram

### Initial State (Service Starts)
```
TenantPoolManager {
    mu: RWMutex,
    pools: {},  // empty map
    expiryDuration: 30 minutes,
    credentialFetch: CoreSettingRepository,
}

Global Map:
```vendor_001" -> EMPTY
"vendor_002" -> EMPTY
```
```

### After First Request (mid=vendor_001)
```
TenantPoolManager {
    mu: RWMutex,
    pools: {
        "vendor_001": {
            Pool: pgxpool (connection pool),
            ExpiresAt: now + 30 minutes
        }
    },
    expiryDuration: 30 minutes,
    credentialFetch: CoreSettingRepository,
}
```

### After Multiple Vendors Request
```
TenantPoolManager {
    mu: RWMutex,
    pools: {
        "vendor_001": {
            Pool: pgxpool (connection pool),
            ExpiresAt: 2024-06-12 14:30:00
        },
        "vendor_002": {
            Pool: pgxpool (connection pool),  // Different pool!
            ExpiresAt: 2024-06-12 14:45:00
        },
        "vendor_003": {
            Pool: pgxpool (connection pool),
            ExpiresAt: 2024-06-12 14:50:00
        }
    },
    expiryDuration: 30 minutes,
    credentialFetch: CoreSettingRepository,
}
```

### After Expiry + Cleanup
```
TenantPoolManager {
    mu: RWMutex,
    pools: {
        // "vendor_001" removed (expired)
        // Pool closed, connection released
        "vendor_002": {
            Pool: pgxpool (connection pool),
            ExpiresAt: 2024-06-12 14:45:00  // Not yet expired
        },
        "vendor_003": {
            Pool: pgxpool (connection pool),
            ExpiresAt: 2024-06-12 14:50:00  // Not yet expired
        }
    },
    expiryDuration: 30 minutes,
    credentialFetch: CoreSettingRepository,
}
```

## 4. Request Timeline - First Request from vendor_001

```
Time    Action
────────────────────────────────────────────────────────────────
T+0s    Client sends request with X-Tenant-MID: vendor_001
        
T+0ms   TenantDBMiddleware receives request
        
T+1ms   middleware.GetTenantID(c) → "vendor_001"
        
T+2ms   tenantMgr.GetOrLoad(ctx, "vendor_001") called
        
T+3ms   Check map: pools["vendor_001"] → NOT FOUND
        
T+4ms   Acquire write lock (mu.Lock())
        
T+5ms   Query master DB: SELECT value FROM coresetting
        WHERE mid = 'vendor_001' AND key = 'tenant_db_host'
        WHERE mid = 'vendor_001' AND key = 'tenant_db_port'
        WHERE mid = 'vendor_001' AND key = 'tenant_db_user'
        WHERE mid = 'vendor_001' AND key = 'tenant_db_password'
        WHERE mid = 'vendor_001' AND key = 'tenant_db_name'
        
T+15ms  Credentials retrieved from master DB
        host: "tenant1.example.com"
        port: "5432"
        user: "tenant_user"
        password: "secure_pass"
        dbname: "tenant_db"
        
T+16ms  Build DSN: postgres://tenant_user:secure_pass@...
        
T+17ms  pgxpool.New(ctx, dsn) - Create connection pool
        
T+50ms  pool.Ping(ctx) - Verify connection works
        
T+55ms  Connection successful!
        
T+56ms  Store in map:
        pools["vendor_001"] = TenantPoolEntry{
            Pool: pgxpool,
            ExpiresAt: now + 30 minutes
        }
        
T+57ms  Release write lock (mu.Unlock())
        
T+58ms  Return pool to middleware
        
T+59ms  Store in context:
        c.Set("tenant_db", pool)
        c.Set("tenant_id", "vendor_001")
        
T+60ms  Handler executes with pool in context
        
T+65ms  Handler queries vendor_001 database
        
T+70ms  Results returned to handler
        
T+71ms  Handler returns JSON response
        
T+72ms  Response sent to client
```

## 5. Request Timeline - Second Request from vendor_001 (within 30 min)

```
Time    Action
────────────────────────────────────────────────────────────────
T+0s    Client sends second request with X-Tenant-MID: vendor_001
        
T+0ms   TenantDBMiddleware receives request
        
T+1ms   tenantMgr.GetOrLoad(ctx, "vendor_001") called
        
T+2ms   Acquire read lock (mu.RLock())
        
T+3ms   Check map: pools["vendor_001"] → FOUND!
        
T+4ms   Check expiry: now (14:20) < ExpiresAt (14:30)? → YES!
        
T+5ms   Release read lock (mu.RUnlock())
        
T+6ms   Return existing pool (NO new connection created!)
        
T+7ms   Store in context (same pool object)
        
T+8ms   Handler executes immediately (very fast!)
        
T+10ms  Response sent to client
        
        DIFFERENCE: First request took ~72ms, Second took ~10ms!
```

## 6. Data Flow - Pool Lookup Decision Tree

```
GetOrLoad(mid) called
    │
    ├─> Try read lock on map
    │   │
    │   ├─> Pool found && not expired?
    │   │   │
    │   │   ├─ YES → Return pool [FAST PATH ~2-5ms]
    │   │   │
    │   │   └─ NO → Continue
    │   │
    │   └─> Pool not found → Continue
    │
    ├─> Acquire write lock
    │   │
    │   ├─> Double-check (still not found/expired?)
    │   │   │
    │   │   ├─ Still exists & valid? → Return [Race prevention]
    │   │   │
    │   │   └─ Not found/expired → Continue
    │   │
    │   ├─> Fetch credentials from master DB
    │   │   │
    │   │   ├─ Success? → Continue
    │   │   │
    │   │   └─ Failed? → Return error [SLOW PATH ~20-100ms]
    │   │
    │   ├─> Create new pgxpool
    │   │   │
    │   │   ├─ Success? → Continue
    │   │   │
    │   │   └─ Failed? → Return error [SLOW PATH ~50-200ms]
    │   │
    │   ├─> Ping connection
    │   │   │
    │   │   ├─ Success? → Continue
    │   │   │
    │   │   └─ Failed? → Close & Return error [SLOW PATH]
    │   │
    │   ├─> Store in map with expiry time
    │   │
    │   ├─> Release write lock
    │   │
    │   └─> Return pool [SLOW PATH ~50-200ms]
```

## 7. Concurrent Request Handling

```
Request Timeline with Multiple Concurrent Requests:

Time    Vendor_001_Req1      Vendor_001_Req2      Vendor_002_Req1
────────────────────────────────────────────────────────────────
T+0ms   Start               Start                Start
        Get RLock                                Get RLock
        
T+1ms   Not found                               Not found
        Release RLock                          Release RLock
        Get WLock                              Get WLock (wait)
                                                (blocked by Req1)
        
T+5ms                       Get RLock
                            Still creating...
                            Release RLock
                            (wait for Req1 finish)
                            
T+10ms  Fetch creds from DB
        
T+20ms  Create pool
        
T+25ms  Ping pool
        
T+26ms  Store & unlock     [Now can proceed]
        Return pool         Get WLock (wait)
        
T+27ms                      Pool found
                            Return pool         (blocked still)
                            
T+28ms                                         Get WLock
                                               [Now can proceed]
                                               
T+40ms                                         Fetch creds
        Handler gets       Handler gets pool
        pool & queries     & queries (fast)
        
T+50ms                                        Create pool
        
T+55ms  Response to        Response to client   
        client                                 
        
T+65ms                                         Ping & store
                                               Response to client

RESULT:
- Req1: ~70ms (first request, creates pool)
- Req2: ~28ms (second request, reuses pool)
- Vendor_002_Req1: ~75ms (different vendor, creates new pool)
```

## 8. Memory and Resource Management

### Before Service Start
```
Total Memory: 0
Active Pools: 0
Connections: 0
```

### After 3 Vendors with 10 reqs each (30 total requests)
```
Global Map Structure:
┌─ "vendor_001"
│   ├─ pgxpool (default 10 connections)
│   └─ ExpiresAt
├─ "vendor_002"
│   ├─ pgxpool (default 10 connections)
│   └─ ExpiresAt
└─ "vendor_003"
    ├─ pgxpool (default 10 connections)
    └─ ExpiresAt

Total Connections: ~30 (10 per tenant)
Memory Used: ~300-400MB (depends on pool config)
Request Times: 10-30ms (all reused from map)
```

### After 30 Minutes (First Pool Expires)
```
Background Cleanup Task Runs:
├─ Check "vendor_001" ExpiresAt < now? → YES
│   ├─ pool.Close() → Release 10 connections
│   └─ delete(pools, "vendor_001")
├─ Check "vendor_002" ExpiresAt < now? → NO
└─ Check "vendor_003" ExpiresAt < now? → NO

After Cleanup:
├─ "vendor_002"
│   ├─ pgxpool (still active)
│   └─ ExpiresAt: 2024-06-12 15:00
└─ "vendor_003"
    ├─ pgxpool (still active)
    └─ ExpiresAt: 2024-06-12 15:05

Total Connections: ~20 (10+10)
Memory Used: ~200-300MB
```

## 9. Thread Safety Guarantees

```
┌─────────────────────────────────────────────────────┐
│              TenantPoolManager                      │
│  ┌──────────────────────────────────────────────┐  │
│  │  mu sync.RWMutex                              │  │
│  │  ├─ Read Operations (RLock):                 │  │
│  │  │  • Multiple goroutines can read at same   │  │
│  │  │    time (fast path, checking expiry)      │  │
│  │  │  • Cannot write while reading             │  │
│  │  │                                            │  │
│  │  └─ Write Operations (Lock):                 │  │
│  │     • Only ONE goroutine can write at time   │  │
│  │     • Blocks all reads until done            │  │
│  │     • Prevents race conditions               │  │
│  └──────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘

Scenario 1: Two goroutines try to create pool for same mid
┌─────────────────────────────────────────────────────┐
│  Goroutine A              Goroutine B               │
│  1. Get RLock             -                         │
│  2. Not found             -                         │
│  3. Release RLock         -                         │
│  4. Get WLock             Wait...                   │
│  5. Create pool           Still waiting...          │
│  6. Store & Unlock        -                         │
│  -                        7. Get WLock              │
│  -                        8. Check map (found!)     │
│  -                        9. Use existing pool      │
│  -                        10. Release WLock         │
└─────────────────────────────────────────────────────┘
RESULT: Only ONE pool created (double-check pattern)

Scenario 2: Many goroutines read same pool
┌─────────────────────────────────────────────────────┐
│  G1          G2          G3          G4             │
│  RLock       (waiting)   (waiting)   (waiting)      │
│  Use pool    RLock       (waiting)   (waiting)      │
│  RUnlock     Use pool    RLock       (waiting)      │
│  -           RUnlock     Use pool    RLock          │
│  -           -           RUnlock     Use pool       │
│  -           -           -           RUnlock        │
└─────────────────────────────────────────────────────┘
RESULT: All 4 goroutines run CONCURRENTLY (efficient)
```

## 10. Configuration Impact

### Low Expiry (5 minutes)
```
Pros:  • Minimal memory usage
       • Releases connections quickly
       • Good for temporary vendors

Cons:  • More pool recreations
       • Higher latency on recreate requests
       • More load on credential fetching

Timeline:
Request @ 10:00 → Pool created
Request @ 10:04 → Pool reused
Request @ 10:06 → Pool expired, recreated
Request @ 10:10 → Pool reused again
```

### Medium Expiry (30 minutes - RECOMMENDED)
```
Pros:  • Good balance
       • Most requests hit existing pool
       • Minimal memory usage
       • Not too many recreations

Timeline:
Request @ 10:00 → Pool created
Request @ 10:01-10:29 → Reused (FAST)
Request @ 10:31 → Expired, recreated
```

### High Expiry (120 minutes)
```
Pros:  • Fewer pool recreations
       • Excellent for active vendors
       • Lower latency overall

Cons:  • Higher memory usage
       • Stale connections possible
       • Long connection lifetimes

Timeline:
Request @ 10:00 → Pool created
Request @ 10:01-11:59 → Reused (VERY FAST)
Request @ 12:01 → Expired, recreated
```

## Summary

The multi-tenant DB system provides:

1. ✅ **Master DB**: Always-connected for credentials
2. ✅ **Dynamic Pool Loading**: First request creates, later requests reuse
3. ✅ **Automatic Expiry**: Pools removed after configured duration
4. ✅ **Thread Safety**: RWMutex prevents race conditions
5. ✅ **Background Cleanup**: Periodic removal of expired pools
6. ✅ **Fast Lookups**: O(1) map access for existing pools
7. ✅ **Isolation**: Each tenant independent from others
8. ✅ **Scalability**: Handles unlimited tenants (memory permitting)
