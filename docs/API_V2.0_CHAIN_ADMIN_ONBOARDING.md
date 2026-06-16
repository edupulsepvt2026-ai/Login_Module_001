# API V2.0 — Chain Admin Onboarding
**Product:** Campus Crew  
**Module:** Auth Service  
**Scope:** Chain Admin account activation after payment  
**Base URL:** `/api/v1/auth`

---

## Overview

Once a school owner (chain admin) completes payment on the EduPulse onboarding portal,
the system automatically sends an invite email with a magic link.

The chain admin **cannot self-register**. Account creation only happens through this invite flow.

### Flow Summary

```
Payment confirmed
      │
      ▼
System sends invite email with magic link
      │
      ▼
STEP 1  →  Chain admin clicks link   →  POST /invite/verify
STEP 2  →  OTP sent to phone         →  POST /otp/send
STEP 3  →  Chain admin enters OTP    →  POST /otp/verify
STEP 4  →  Chain admin sets password →  POST /invite/set-password
      │
      ▼
Account activated — JWT issued — Redirected to chain admin portal
```

> **Note:** All four steps must be completed in order.
> The `temp_token` returned in Step 1 is required for Steps 2, 3, and 4.
> It expires in **10 minutes**. If expired, the chain admin must click the email link again.

---

## Why temp_token?

At Step 1 the chain admin has no account yet — no JWT, no login, no session.
But Steps 2, 3, and 4 need to know **who is going through this flow**.

The backend cannot rely on the frontend sending `user_id` or `email` directly because:
- Anyone could send any `user_id` and trigger an OTP for someone else
- Anyone could send any `email` and attempt to set a password for someone else

`temp_token` solves this by acting as a **short-lived session bridge** across all 4 steps.

```
Step 1 completes  →  Backend generates temp_token (random UUID)
                     Stores in Redis:
                       key   = invite_verify:{temp_token}
                       value = {user_id}:{phone}
                       TTL   = 10 minutes
                     Returns temp_token to frontend

Step 2, 3, 4     →  Frontend sends temp_token in every request
                     Backend looks up Redis with that key
                     Finds the correct user_id and phone
                     Proceeds with that user — no guessing, no spoofing
```

Only the legitimate chain admin has the `temp_token` because it was generated
right after their valid invite token was verified. It proves continuity across
steps without exposing any real user identity in the request.

> **Frontend rule:** Store `temp_token` in memory only (React state / a variable).
> Never in `localStorage` or `sessionStorage`. It should die when the tab closes.

---

## Database Reference

All operations in this flow touch the **Master DB** (`edupulse_master`).  
Tenant DB is not involved at this stage.

### Tables involved

| Table                            | Schema       | Purpose                                           |
|----------------------------------|--------------|---------------------------------------------------|
| `auth.invite`                    | Master DB    | Stores the magic link token and its status        |
| `auth.invite_status`             | Master DB    | Lookup: pending / accepted / expired / revoked    |
| `auth.management_user`           | Master DB    | Chain admin profile (name, email, phone)          |
| `auth.chain_user_mapping`        | Master DB    | Identity routing index — maps email/phone to tenant DB |
| `infrastructure.chain_database`  | Master DB    | Tenant DB connection credentials per chain        |
| `auth.otp_type`                  | Master DB    | Lookup: OTP type config (TTL, max attempts)       |
| `auth.otp`                       | Master DB    | Stores hashed OTP codes                           |
| `auth.user`                      | Tenant DB    | Full user record — password hash lives here       |
| `auth.session`                   | Tenant DB    | Access and refresh token hashes                   |
| `auth.audit_log`                 | Tenant DB    | Append-only security event trail                  |
| `onboarding.chain`               | Master DB    | Chain name and details                            |
| `onboarding.branch`              | Master DB    | Branch details per chain                          |
| Redis                            | Cache        | Temporary verification session (temp_token)       |

---

## Endpoints

---

### STEP 1 — Verify Invite Token

Validates the magic link token from the email. Returns account preview and a temp token
to carry through the remaining steps.

```
POST /api/v1/auth/invite/verify
```

**Auth Required:** No

**Request Body**

| Field   | Type   | Required | Description                              |
|---------|--------|----------|------------------------------------------|
| `token` | string | Yes      | Raw token extracted from the email link  |

```json
{
  "token": "raw_token_from_email_link"
}
```

**Success Response — 200**

```json
{
  "success": true,
  "data": {
    "temp_token": "550e8400-e29b-41d4-a716-446655440000",

    "user": {
      "name": "Rajesh Kumar",
      "email": "r*****@vellamal.edu.in",
      "phone": "******4567"
    },

    "chain": {
      "id": "chain-uuid",
      "name": "Velammal Educational Trust"
    },

    "branches": [
      {
        "id": "branch-uuid-1",
        "name": "Velammal - Madurai",
        "city": "Madurai",
        "state": "Tamil Nadu",
        "board_type": "CBSE"
      },
      {
        "id": "branch-uuid-2",
        "name": "Velammal - Coimbatore",
        "city": "Coimbatore",
        "state": "Tamil Nadu",
        "board_type": "CBSE"
      }
    ]
  }
}
```

> **Why return chain and branch info here?**  
> The frontend should display the school name and branches on the OTP screen so the
> chain admin can confirm they are activating the correct account before proceeding.

**Error Responses**

| HTTP | Error                               | Reason                                      |
|------|-------------------------------------|---------------------------------------------|
| 401  | `invalid or expired invite link`    | Token not found or hash mismatch            |
| 401  | `invite link has already been used` | Token was already accepted or in progress   |
| 401  | `invite link has expired`           | Token TTL (48 hours) has passed             |
| 400  | `token is required`                 | Request body missing token field            |

**Database Operations**

```
READ
  auth.invite
    WHERE invite_token_hash = SHA256(token)
      AND status             = 'pending'
    → validate token exists, not used, not expired

  auth.management_user
    WHERE id = invite.management_user_id
    → fetch name, email, phone for response

  onboarding.chain
    WHERE id = management_user.chain_id
    → fetch chain name

  onboarding.branch
    WHERE chain_id = chain.id
    → fetch all branches under this chain

INSERT
  auth.audit_log
    event_type = 'invite_accepted'
    user_id    = management_user.id
    metadata   = { "chain_id": "...", "ip": "..." }

REDIS SET
  key   : invite_verify:{temp_token}
  value : {user_id}:{phone}:{email}
  TTL   : 10 minutes
  → both phone and email stored so Step 2 can deliver to either channel
```

> **Rule:** Do NOT update `auth.invite` status here yet.
> Status moves to `accepted` only in Step 4 after password is set successfully.

---

### STEP 2 — Send OTP

Sends a 6-digit OTP to the chain admin's phone or email depending on the `channel` field.
Both channels use the same endpoint — the service routes to the correct delivery address and OTP type.

```
POST /api/v1/auth/otp/send
```

**Auth Required:** No

**Request Body**

| Field        | Type   | Required | Description                                        |
|--------------|--------|----------|----------------------------------------------------|
| `temp_token` | string | Yes      | Received from Step 1 invite/verify                 |
| `channel`    | string | Yes      | Delivery channel — `"sms"` or `"email"`            |

```json
{ "temp_token": "550e8400-e29b-41d4-a716-446655440000", "channel": "sms" }
```
```json
{ "temp_token": "550e8400-e29b-41d4-a716-446655440000", "channel": "email" }
```

**Success Response — 200**

```json
{ "success": true, "data": { "message": "OTP sent to registered mobile number" } }
```
```json
{ "success": true, "data": { "message": "OTP sent to registered email address" } }
```

**Error Responses**

| HTTP | Error                                     | Reason                               |
|------|-------------------------------------------|--------------------------------------|
| 400  | `invalid or expired verification session` | temp_token not found or expired      |
| 400  | `temp_token is required`                  | Request body missing field           |
| 400  | `channel must be sms or email`            | Invalid channel value                |
| 400  | `phone not registered for this account`   | channel=sms but phone is null        |
| 400  | `email not registered for this account`   | channel=email but email is null      |
| 500  | `failed to send OTP`                      | Omnichannel service failure          |

> **Note:** OTP is valid for **5 minutes**. Maximum **3 attempts** allowed.
> After 3 wrong attempts, the chain admin must request a new OTP.

**Database Operations**

```
REDIS GET
  key : invite_verify:{temp_token}
  → validate session exists
  → extract fields: user_id, phone, email
    (value format: {user_id}:{phone}:{email})

  if channel = "sms"  → delivery_address = phone
  if channel = "email" → delivery_address = email

READ
  auth.otp_type
    WHERE name = 'signup_sms'    (channel = "sms")
       OR name = 'signup_email'  (channel = "email")
  → get otp_type_id, TTL (300 seconds), max_attempts (3)

INSERT
  auth.otp
    otp_type_id      = otp_type.id
    code_hash        = SHA256(generated_6_digit_code)
    delivery_address = phone  OR  email  (based on channel)
    attempts         = 0
    is_used          = false
    expires_at       = now() + 5 minutes

  → channel = "sms"   : raw OTP sent via omnichannel service (kind: "sms")
  → channel = "email" : raw OTP sent via omnichannel service (kind: "email")
  → raw OTP is never stored

REDIS SET  (update session — record which channel was used)
  key   : invite_verify:{temp_token}
  value : {user_id}:{phone}:{email}:{channel}
  TTL   : 10 minutes  (reset TTL)
```

---

### STEP 3 — Verify OTP

Validates the OTP entered by the chain admin.

```
POST /api/v1/auth/otp/verify
```

**Auth Required:** No

**Request Body**

| Field        | Type   | Required | Description                              |
|--------------|--------|----------|------------------------------------------|
| `temp_token` | string | Yes      | Received from Step 1                     |
| `otp`        | string | Yes      | 6-digit OTP received on phone            |

```json
{
  "temp_token": "550e8400-e29b-41d4-a716-446655440000",
  "otp": "482910"
}
```

**Success Response — 200**

```json
{
  "success": true,
  "data": {
    "message": "OTP verified successfully",
    "status": "otp_verified"
  }
}
```

**Error Responses**

| HTTP | Error                                     | Reason                               |
|------|-------------------------------------------|--------------------------------------|
| 401  | `incorrect OTP`                           | Wrong code entered                   |
| 401  | `OTP not found or expired`                | OTP TTL (5 minutes) passed           |
| 401  | `too many incorrect attempts`             | 3 wrong attempts reached             |
| 400  | `invalid or expired verification session` | temp_token not found or expired      |
| 400  | `otp must be 6 digits`                    | Invalid format                       |

**Database Operations**

```
REDIS GET
  key : invite_verify:{temp_token}
  → validate session exists
  → extract fields: user_id, phone, email, channel
    (value format after Step 2: {user_id}:{phone}:{email}:{channel})

  delivery_address = phone   (if channel = "sms")
  delivery_address = email   (if channel = "email")

READ
  auth.otp
    WHERE delivery_address = delivery_address  -- phone or email
      AND is_used          = false
      AND expires_at       > now()
    ORDER BY created_at DESC
    LIMIT 1
  → get latest active OTP for that delivery address

  if otp.attempts >= 3
    → return error: too many incorrect attempts

  if SHA256(submitted_otp) != otp.code_hash
    → UPDATE auth.otp SET attempts = attempts + 1
    → return error: incorrect OTP

UPDATE (on success)
  auth.otp
    SET is_used = true
    WHERE id = otp.id

INSERT
  auth.audit_log
    event_type = 'otp_verified'
    user_id    = management_user.id
    metadata   = { "channel": "sms|email", "delivery_address": "masked" }

REDIS SET  (update session — mark OTP as verified)
  key   : invite_verify:{temp_token}
  value : {user_id}:{phone}:{email}:{channel}:otp_verified
  TTL   : 10 minutes  (reset TTL)
```

> **Rule:** Use constant-time comparison when checking `SHA256(otp) == code_hash`.
> Do not use regular string equality — it is vulnerable to timing attacks.

---

### STEP 4 — Set Password

Sets the chain admin's password and activates the account.
Issues JWT access and refresh tokens on success.

```
POST /api/v1/auth/invite/set-password
```

**Auth Required:** No

**Request Body**

| Field        | Type   | Required | Description                              |
|--------------|--------|----------|------------------------------------------|
| `temp_token` | string | Yes      | Received from Step 1                     |
| `password`   | string | Yes      | Min 8 characters                         |

```json
{
  "temp_token": "550e8400-e29b-41d4-a716-446655440000",
  "password": "SecurePass@123"
}
```

**Password Rules**
- Minimum 8 characters
- At least 1 uppercase letter
- At least 1 number
- At least 1 special character

**Success Response — 200**

```json
{
  "success": true,
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "dGhpcyBpcyBhIHJlZnJlc2ggdG9rZW4...",
    "expires_in": 900,
    "user": {
      "id": "user-uuid",
      "name": "Rajesh Kumar",
      "email": "rajesh@vellamal.edu.in",
      "role": "chain_admin",
      "chain_id": "chain-uuid",
      "chain_name": "Velammal Educational Trust"
    }
  }
}
```

| Field           | Description                                              |
|-----------------|----------------------------------------------------------|
| `access_token`  | JWT — valid for 15 minutes. Send in every request header |
| `refresh_token` | Opaque token — valid for 7 days. Rotate on every refresh |
| `expires_in`    | Access token expiry in seconds (900 = 15 min)            |

**Error Responses**

| HTTP | Error                                               | Reason                               |
|------|-----------------------------------------------------|--------------------------------------|
| 400  | `OTP verification required before setting password` | Step 3 was not completed             |
| 400  | `invalid or expired verification session`           | temp_token expired or not found      |
| 400  | `password must be at least 8 characters`            | Password too short                   |
| 400  | `password does not meet requirements`               | Missing uppercase / number / special |

**Database Operations**

```
REDIS GET
  key : invite_verify:{temp_token}
  → validate session exists
  → confirm value ends with :otp_verified
  → extract user_id, phone, chain_id (all stored at Step 1)

── Transaction BEGIN ──────────────────────────────────────────

INSERT  (TENANT DB — user record with credentials)
  auth.user
    id                = user_id  (UUID from invite session)
    email             = user's email
    phone             = user's phone
    password_hash     = bcrypt(password, cost=12)
    role              = 'chain_admin'
    chain_id          = chain_id from invite session
    is_email_verified = true
    is_phone_verified = true
    is_active         = true
    created_at        = now()
    updated_at        = now()

UPDATE  (MASTER DB — mark invite consumed)
  auth.invite
    SET status_id   = (SELECT id FROM auth.invite_status WHERE name = 'accepted')
        accepted_at = now()
    WHERE management_user_id = user_id
      AND accepted_at IS NULL

INSERT  (MASTER DB — identity routing index)
  auth.chain_user_mapping
    user_id     = user_id  (the auth.user.id just inserted in tenant DB)
    role        = 'chain_admin'
    chain_id    = chain_id from invite session
    chain_db_id = (SELECT id FROM infrastructure.chain_database
                   WHERE chain_id = chain_id AND is_active = true)
    email       = user's email
    phone       = user's phone
    is_active   = true
    created_at  = now()

  → This row is the single source of truth used at every subsequent login.
    Login resolves: email → chain_db_id → DB credentials → tenant DB.

INSERT  (TENANT DB — create authenticated session)
  auth.session
    user_id                  = user_id
    access_token_hash        = SHA256(access_token)
    refresh_token_hash       = SHA256(refresh_token)
    access_token_expires_at  = now() + 15 minutes
    refresh_token_expires_at = now() + 7 days
    ip_address               = request IP
    user_agent               = request User-Agent

INSERT  (TENANT DB — audit trail, two entries)
  auth.audit_log
    1. event_type = 'password_created'
       user_id    = user_id
       metadata   = { "chain_id": "..." }

    2. event_type = 'login_success'
       user_id    = user_id
       metadata   = { "chain_id": "...", "session_id": "..." }

── Transaction COMMIT ─────────────────────────────────────────

REDIS DEL
  key : invite_verify:{temp_token}
  → clean up verification session immediately after commit
```

> **Rule:** All DB operations in Step 4 run inside a **distributed transaction** spanning both Master DB and Tenant DB.
> If any step fails — auth.user insert, chain_user_mapping insert, or session creation — roll back all writes.
> If chain_user_mapping insert fails, the account must not be created: without the routing entry the user can never log in.

---

## Token Lifecycle

```
Invite token  →  Single use, 48 hour TTL, stored as SHA256 hash in auth.invite
temp_token    →  Single session, 10 minute TTL, stored in Redis only
OTP           →  6 digits, 5 minute TTL, max 3 attempts, stored as SHA256 in auth.otp
access_token  →  JWT, 15 minute TTL, hash stored in auth.session
refresh_token →  Opaque, 7 day TTL, hash stored in auth.session, rotated on each use
```

---

## Redis Key Structure

The same key is overwritten at each step to advance its state:

| Step    | Value written to `invite_verify:{temp_token}`          | TTL        |
|---------|--------------------------------------------------------|------------|
| Step 1  | `{user_id}:{phone}:{email}`                            | 10 minutes |
| Step 2  | `{user_id}:{phone}:{email}:{channel}`                  | 10 minutes (TTL reset) |
| Step 3  | `{user_id}:{phone}:{email}:{channel}:otp_verified`     | 10 minutes (TTL reset) |
| Step 4  | *(key deleted after success)*                          | —          |

`{channel}` is either `sms` or `email` — set by the client in Step 2 and carried forward so Step 3 and Step 4 know which delivery address was verified.

---

## Important Rules for Frontend

1. Store `temp_token` in memory only (not localStorage) — it is short-lived.
2. After Step 4 succeeds, store `access_token` and `refresh_token` securely.
3. Send `access_token` in every authenticated request:
   ```
   Authorization: Bearer <access_token>
   ```
4. When an API returns `401`, use `refresh_token` to get a new `access_token` via `/auth/refresh`.
5. If `refresh_token` also returns `401`, session is fully expired — redirect to login.

---

## Important Rules for Backend

1. Never store raw token, raw OTP, or raw refresh token — always store SHA256 hash.
2. Validate `temp_token` exists in Redis before processing Steps 2, 3, 4.
3. Do NOT change `auth.invite` status until Step 4 completes successfully.
4. Delete `temp_token` from Redis immediately after Step 4 succeeds.
5. Use constant-time comparison (`crypto/subtle`) when matching any hash.
6. Mask email and phone in Step 1 response — show only last 4 digits of phone.
7. Step 4 DB operations must be wrapped in a single transaction.

---

---

## Phase 2 — Login & Session Management

> **Note:** After Step 4 (set-password) completes, the user is automatically logged in
> and redirected to the chain admin portal. The login API below is only hit when:
> - User explicitly logs out and comes back
> - Refresh token expires after 7 days
> - User opens the portal on a new browser or device

---

### STEP 5 — Login

Authenticates the chain admin with email and password.
Returns access token in response body and refresh token as an httpOnly cookie.

```
POST /api/v1/auth/login
```

**Database:** Tenant DB  
**Auth Required:** No

**Request Body**

| Field      | Type   | Required | Description            |
|------------|--------|----------|------------------------|
| `email`    | string | Yes      | Registered email       |
| `password` | string | Yes      | Account password       |

```json
{
  "email": "rajesh@vellamal.edu.in",
  "password": "SecurePass@123"
}
```

**Success Response — 200**

```json
{
  "success": true,
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "expires_in": 900,
    "user": {
      "id": "user-uuid",
      "name": "Rajesh Kumar",
      "email": "rajesh@vellamal.edu.in",
      "role": "chain_admin",
      "chain_id": "chain-uuid",
      "chain_name": "Velammal Educational Trust"
    }
  }
}
```

> **Token storage:**
> - `access_token` — returned in response body, frontend stores in localStorage
> - `refresh_token` — sent as httpOnly cookie by backend, frontend never touches it
>   ```
>   Set-Cookie: refresh_token=xxx; HttpOnly; Secure; SameSite=Strict; Path=/api/v1/auth/refresh
>   ```

**Error Responses**

| HTTP | Error                          | Reason                                        |
|------|--------------------------------|-----------------------------------------------|
| 401  | `invalid email or password`    | User not found or password mismatch           |
| 403  | `account is not active`        | Account deactivated                           |
| 423  | `account is locked`            | 5 failed attempts — locked for 30 minutes    |
| 400  | `email and password required`  | Missing fields                                |

**Database Operations**

```
── Step A — Identity Routing (MASTER DB) ──────────────────────

READ
  SELECT m.user_id,
         m.chain_id,
         m.role,
         cd.db_host,
         cd.db_port,
         cd.db_name,
         cd.db_user,
         cd.db_password_encrypted,
         cd.ssl_mode
  FROM   auth.chain_user_mapping m
  INNER JOIN infrastructure.chain_database cd ON cd.id = m.chain_db_id
  WHERE  m.email     = submitted_email   -- or m.phone = submitted_phone
    AND  m.is_active = true
    AND  cd.is_active = true

  if not found → 401 invalid email or password
    (never reveal whether the email exists)

── Step B — Tenant DB Connection ──────────────────────────────

  Decrypt cd.db_password_encrypted via KMS
  Build DSN: host=cd.db_host port=cd.db_port dbname=cd.db_name
             user=cd.db_user password=decrypted sslmode=cd.ssl_mode
  Acquire connection from TenantPoolManager
    (creates pool on first login, reuses on subsequent logins)

── Step C — Password Verification (TENANT DB) ─────────────────

READ
  auth.user
    WHERE id        = m.user_id   -- use user_id from mapping, not email scan
      AND is_active = true

  if locked_until IS NOT NULL AND locked_until > now()
    → 423 account is locked, return locked_until timestamp

  if bcrypt(submitted_password) != password_hash
    → UPDATE auth.user SET failed_login_attempts = failed_login_attempts + 1
    if failed_login_attempts >= 5
      → UPDATE auth.user SET locked_until = now() + 30 minutes
    → 401 invalid email or password

── Step D — Session Creation (TENANT DB) ──────────────────────

UPDATE  (on success)
  auth.user
    SET failed_login_attempts = 0
        locked_until          = NULL
        last_login_at         = now()
    WHERE id = user_id

INSERT
  auth.session
    user_id                  = user_id
    access_token_hash        = SHA256(access_token)
    refresh_token_hash       = SHA256(refresh_token)
    access_token_expires_at  = now() + 15 minutes
    refresh_token_expires_at = now() + 7 days
    ip_address               = request IP
    user_agent               = request User-Agent

INSERT
  auth.audit_log
    event_type = 'login_success' or 'login_failure'
    user_id    = user_id
    metadata   = { "ip": "...", "user_agent": "...", "chain_id": "..." }
```

> **Why two databases at login?** The master DB routing query is a single indexed lookup on `auth.chain_user_mapping.email`.
> It costs one fast round-trip and returns the exact tenant DB to use. Without it, the service has no way to know
> which of the N tenant databases holds this user's record. The tenant pool manager caches open connections,
> so Step B is a pool lookup (not a new TCP connection) on all requests after the first login.

---

### STEP 6 — Refresh Token

Issues a new access token using the refresh token from the httpOnly cookie.
Called automatically by the frontend when the access token expires.

```
POST /api/v1/auth/refresh
```

**Database:** Tenant DB  
**Auth Required:** No (uses httpOnly cookie)

**Request**

No request body needed. Browser automatically sends the httpOnly cookie.

```
Cookie: refresh_token=opaque_refresh_token_here
```

**Success Response — 200**

```json
{
  "success": true,
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "expires_in": 900
  }
}
```

> Backend also sets a new httpOnly cookie with the rotated refresh token.

**Error Responses**

| HTTP | Error                       | Reason                                           |
|------|-----------------------------|--------------------------------------------------|
| 401  | `invalid refresh token`     | Token not found, revoked, or hash mismatch       |
| 401  | `refresh token expired`     | 7 day TTL passed — user must login again         |

**Database Operations**

```
READ  (Tenant DB)
  auth.session
    WHERE refresh_token_hash = SHA256(cookie_refresh_token)
      AND revoked_at         IS NULL
      AND refresh_token_expires_at > now()
  → if not found → 401

UPDATE  (rotate — invalidate old session)
  auth.session
    SET revoked_at                    = now()
        refresh_token_last_rotated_at = now()
    WHERE id = session_id

INSERT  (create new session)
  auth.session
    user_id                  = same user_id
    access_token_hash        = SHA256(new_access_token)
    refresh_token_hash       = SHA256(new_refresh_token)
    access_token_expires_at  = now() + 15 minutes
    refresh_token_expires_at = now() + 7 days
```

> **Rule:** Old session is revoked and a new session is created on every refresh.
> This is called refresh token rotation — if a stolen token is reused, it is detected.

---

### STEP 7 — Logout

Revokes the current session. Clears the httpOnly cookie.

```
POST /api/v1/auth/logout
```

**Database:** Tenant DB  
**Auth Required:** Yes — `Authorization: Bearer <access_token>`

**Request**

No request body. Access token in header, refresh token from httpOnly cookie.

**Success Response — 200**

```json
{
  "success": true,
  "data": {
    "message": "logged out successfully"
  }
}
```

> Backend sends this header in the **response** to instruct the browser to delete the cookie from its storage.
> The backend itself never stores cookies — the real revocation happens in the DB (`revoked_at`).
> ```
> Set-Cookie: refresh_token=; HttpOnly; Secure; Expires=Thu, 01 Jan 1970 00:00:00 GMT
> ```

**Error Responses**

| HTTP | Error              | Reason                            |
|------|--------------------|-----------------------------------|
| 401  | `missing token`    | Authorization header not present  |
| 401  | `invalid token`    | JWT verification failed           |

**Database Operations**

```
UPDATE  (Tenant DB)
  auth.session
    SET revoked_at = now()
    WHERE access_token_hash = SHA256(access_token from header)

INSERT
  auth.audit_log
    event_type = 'logout'
    user_id    = user_id from JWT claims
    metadata   = { "ip": "...", "user_agent": "..." }
```

---

## Phase 3 — Tenant Admin Onboarding

> **Who does this:** chain_admin, after logging into the portal.
> **What it does:** Invite tenant_admins (branch admins) for each branch under their chain.
>
> chain_admin can onboard tenant_admins in two ways:
> - **Individual** — type details for one tenant_admin at a time
> - **Bulk** — download an Excel template, fill it, upload it back

---

### STEP 8 — Get Branches

Returns all branches under the chain admin's chain.
Used to pre-fill the Excel template and to populate the branch dropdown for individual entry.

```
GET /api/v1/chain-admin/branches
```

**Database:** Tenant DB  
**Auth Required:** Yes — `Authorization: Bearer <access_token>`

**Request**

No request body. `chain_id` is extracted from the JWT claims.

**Success Response — 200**

```json
{
  "success": true,
  "data": {
    "chain_id": "chain-uuid",
    "chain_name": "Velammal Educational Trust",
    "branches": [
      {
        "id": "branch-uuid-1",
        "name": "Velammal - Madurai",
        "city": "Madurai",
        "state": "Tamil Nadu",
        "board_type": "CBSE",
        "has_tenant_admin": false
      },
      {
        "id": "branch-uuid-2",
        "name": "Velammal - Coimbatore",
        "city": "Coimbatore",
        "state": "Tamil Nadu",
        "board_type": "CBSE",
        "has_tenant_admin": true
      }
    ]
  }
}
```

> `has_tenant_admin` — frontend uses this to show which branches are already covered.

**Database Operations**

```
READ  (Tenant DB)
  management.management_table
    WHERE chain_id = chain_id from JWT claims
      AND is_active = true
  → returns all branches

  For each branch, check:
  auth.user
    WHERE management_id = branch.tenant_id
      AND role          = 'tenant_admin'
      AND is_active     = true
  → sets has_tenant_admin flag
```

---

### STEP 9 — Download Excel Template

Downloads an Excel file pre-filled with branch_id and branch_name.
chain_admin fills in name, email, and mobile for each branch and uploads it back.

```
GET /api/v1/chain-admin/tenant-admins/template
```

**Database:** Tenant DB  
**Auth Required:** Yes — `Authorization: Bearer <access_token>`

**Response**

```
Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
Content-Disposition: attachment; filename="tenant_admin_template.xlsx"
```

**Excel structure**

| branch_id    | branch_name           | name         | email                  | mobile     |
|--------------|-----------------------|--------------|------------------------|------------|
| branch-uuid-1 | Velammal - Madurai   | *(fill this)* | *(fill this)*         | *(fill this)* |
| branch-uuid-2 | Velammal - Coimbatore | *(fill this)* | *(fill this)*        | *(fill this)* |

> - `branch_id` and `branch_name` are pre-filled and locked (read-only cells)
> - `name`, `email`, `mobile` are left empty for the chain_admin to fill
> - At least `email` or `mobile` is required per row — both is preferred
> - If email is not available, mobile is used as fallback for sending the invite

**Database Operations**

```
READ  (Tenant DB)
  management.management_table
    WHERE chain_id = chain_id from JWT claims
      AND is_active = true
  → generates one Excel row per branch
```

---

### STEP 10 — Submit Individual Tenant Admin

Submits details for a single tenant admin for one branch.
Validates the data, creates the invite record, and sends the invite email or SMS.

```
POST /api/v1/chain-admin/tenant-admins
```

**Database:** Tenant DB  
**Auth Required:** Yes — `Authorization: Bearer <access_token>`

**Request Body**

| Field       | Type   | Required     | Description                                      |
|-------------|--------|--------------|--------------------------------------------------|
| `branch_id` | string | Yes          | Must belong to the chain_admin's chain           |
| `name`      | string | Yes          | Tenant admin's full name                         |
| `email`     | string | Conditional  | Required if mobile not provided                  |
| `mobile`    | string | Conditional  | Required if email not provided. Fallback channel |

```json
{
  "branch_id": "branch-uuid-1",
  "name": "Priya Rajan",
  "email": "priya@vellamal-madurai.edu.in",
  "mobile": "+919876543210"
}
```

**Success Response — 201**

```json
{
  "success": true,
  "data": {
    "message": "Invite sent to Priya Rajan",
    "invite_id": "invite-uuid",
    "delivery_channel": "email"
  }
}
```

**Error Responses**

| HTTP | Error                                  | Reason                                        |
|------|----------------------------------------|-----------------------------------------------|
| 400  | `branch_id is required`                | Missing field                                 |
| 400  | `name is required`                     | Missing field                                 |
| 400  | `email or mobile is required`          | Neither contact method provided               |
| 403  | `branch does not belong to your chain` | chain_admin trying to add to another chain    |
| 409  | `tenant admin already exists`          | Branch already has an active tenant admin     |
| 500  | `failed to send invite`                | External email/SMS service failure            |

**Database Operations**

```
READ  (Tenant DB)
  management.management_table
    WHERE tenant_id = branch_id
      AND chain_id  = chain_id from JWT claims
  → verify branch belongs to this chain_admin

  auth.user
    WHERE management_id = branch_id
      AND role          = 'tenant_admin'
      AND is_active     = true
  → if exists → 409 tenant admin already exists

INSERT
  auth.user
    role_id            = (SELECT id FROM auth.role WHERE name = 'tenant_admin')
    management_type_id = (SELECT id FROM auth.management_type WHERE name = 'tenant')
    management_id      = branch_id
    name               = submitted name
    email              = submitted email (nullable)
    phone              = submitted mobile (nullable)
    is_active          = true
    onboarding_channel = 'invite'

INSERT
  auth.invite
    invited_by_user_id = chain_admin user_id from JWT
    management_type_id = 'tenant'
    management_id      = branch_id
    target_role_id     = tenant_admin role id
    status_id          = 'pending'
    invite_token_hash  = SHA256(generated_raw_token)
    expires_at         = now() + 48 hours
    name               = submitted name
    email              = submitted email
    phone              = submitted mobile

EXTERNAL SERVICE CALL
  → Send invite email (if email provided)
  → Send invite SMS  (if mobile provided and no email)
  → Payload: { recipient_name, invite_link, channel }

INSERT
  auth.audit_log
    event_type = 'invite_sent'
    user_id    = chain_admin user_id
    metadata   = { "target_role": "tenant_admin", "branch_id": "..." }
```

---

### STEP 11 — Bulk Upload via Excel

Accepts the filled Excel template and processes all rows in one request.
Validates each row, skips invalid ones, creates invite records, and sends invites.

```
POST /api/v1/chain-admin/tenant-admins/bulk
```

**Database:** Tenant DB  
**Auth Required:** Yes — `Authorization: Bearer <access_token>`

**Request**

```
Content-Type: multipart/form-data
```

| Field  | Type | Required | Description                            |
|--------|------|----------|----------------------------------------|
| `file` | file | Yes      | Filled Excel file (.xlsx only)         |

**Success Response — 200**

```json
{
  "success": true,
  "data": {
    "total_rows": 5,
    "success_count": 4,
    "failed_count": 1,
    "results": [
      {
        "branch_id": "branch-uuid-1",
        "branch_name": "Velammal - Madurai",
        "status": "invited",
        "delivery_channel": "email"
      },
      {
        "branch_id": "branch-uuid-2",
        "branch_name": "Velammal - Coimbatore",
        "status": "failed",
        "reason": "email or mobile is required"
      }
    ]
  }
}
```

**Error Responses**

| HTTP | Error                        | Reason                                      |
|------|------------------------------|---------------------------------------------|
| 400  | `file is required`           | No file attached                            |
| 400  | `invalid file format`        | File is not .xlsx                           |
| 400  | `file is empty`              | No rows found in the sheet                  |
| 400  | `invalid template format`    | Required columns missing or renamed         |

> **Partial success is allowed.** If 4 out of 5 rows are valid, 4 invites are sent
> and 1 failure is reported. The entire upload is not rejected for one bad row.

**Database Operations**

```
For each valid row — same operations as STEP 10 (individual submit):
  → Validate branch belongs to chain
  → Check tenant_admin doesn't already exist
  → INSERT auth.user
  → INSERT auth.invite
  → Call external email/SMS service
  → INSERT auth.audit_log

Invalid rows:
  → Skipped, reason recorded in response
  → No DB writes for invalid rows
```

---

### STEP 12 — Send Invite Email (External Service)

This is not a direct API endpoint. It is an internal call to the external email service
made by the backend during Steps 10 and 11.

**External service call**

```
POST {EMAIL_SERVICE_URL}/send
Headers:
  Authorization: Bearer {EMAIL_SERVICE_API_KEY}
  Content-Type: application/json

Body:
{
  "to": "priya@vellamal-madurai.edu.in",
  "template": "tenant_admin_invite",
  "variables": {
    "recipient_name": "Priya Rajan",
    "invite_link": "https://campuscrew.app/invite?token=raw_token",
    "expires_in": "48 hours",
    "chain_name": "Velammal Educational Trust",
    "branch_name": "Velammal - Madurai"
  }
}
```

**SMS fallback** (when no email is provided)

```
POST {SMS_SERVICE_URL}/send
Body:
{
  "to": "+919876543210",
  "message": "You have been invited to Campus Crew as branch admin for Velammal - Madurai. Click to activate: https://campuscrew.app/invite?token=raw_token"
}
```

> **Rule:** Raw invite token is sent in the email/SMS link only.
> Only SHA256(raw_token) is stored in `auth.invite.invite_token_hash`.
> The external service never stores or logs the raw token.

---

## Updated Token Lifecycle

```
Invite token  →  Single use, 48 hour TTL, SHA256 hash in auth.invite
temp_token    →  Single session, 10 minute TTL, Redis only
OTP           →  6 digits, 5 minute TTL, max 3 attempts, SHA256 in auth.otp
access_token  →  JWT, 15 min TTL, stored in localStorage, SHA256 in auth.session
refresh_token →  Opaque, 7 day TTL, httpOnly cookie, SHA256 in auth.session
```

---

## Updated Redis Key Structure

| Key pattern                    | Value                              | TTL        | Set in  | Deleted in |
|--------------------------------|------------------------------------|------------|---------|------------|
| `invite_verify:{temp_token}`   | `{user_id}:{phone}`                | 10 minutes | Step 1  | —          |
| `invite_verify:{temp_token}`   | `{user_id}:{phone}:otp_verified`   | 10 minutes | Step 3  | Step 4     |

---

## Complete API Summary

| Step | Method | Endpoint                              | Auth | Description                        |
|------|--------|---------------------------------------|------|------------------------------------|
| 1    | POST   | `/auth/invite/verify`                 | No   | Verify magic link token            |
| 2    | POST   | `/auth/otp/send`                      | No   | Send OTP to phone                  |
| 3    | POST   | `/auth/otp/verify`                    | No   | Verify OTP                         |
| 4    | POST   | `/auth/invite/set-password`           | No   | Set password, activate account     |
| 5    | POST   | `/auth/login`                         | No   | Login with email + password        |
| 6    | POST   | `/auth/refresh`                       | No   | Refresh access token               |
| 7    | POST   | `/auth/logout`                        | Yes  | Logout, revoke session             |
| 8    | GET    | `/chain-admin/branches`               | Yes  | Get all branches                   |
| 9    | GET    | `/chain-admin/tenant-admins/template` | Yes  | Download Excel template            |
| 10   | POST   | `/chain-admin/tenant-admins`          | Yes  | Submit individual tenant admin     |
| 11   | POST   | `/chain-admin/tenant-admins/bulk`     | Yes  | Bulk upload via Excel              |

---

*Document version: 2.0 | Module: Chain Admin Onboarding | Status: Draft*
