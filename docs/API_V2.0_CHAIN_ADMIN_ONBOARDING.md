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
STEP 1  →  Chain admin clicks link         →  POST /invite/verify
STEP 2a →  OTP sent to phone (sms)         →  POST /otp/send   { channel: "sms" }
STEP 3a →  Chain admin verifies SMS OTP    →  POST /otp/verify  { channel: "sms" }
STEP 2b →  OTP sent to email               →  POST /otp/send   { channel: "email" }
STEP 3b →  Chain admin verifies email OTP  →  POST /otp/verify  { channel: "email" }
STEP 4  →  Chain admin sets password       →  POST /invite/set-password
      │
      ▼
Account activated — JWT issued — Redirected to chain admin portal
```

> **Note:** Both SMS and email must be verified independently before Step 4.
> The order of Steps 2a/3a and 2b/3b does not matter — either channel can be verified first.
> The `temp_token` returned in Step 1 is required for all subsequent steps.
> It expires in **20 minutes**. If expired, the chain admin must click the email link again.

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
                       value = JSON (see Redis Key Structure below)
                       TTL   = 20 minutes
                     Returns temp_token to frontend

Step 2, 3, 4     →  Frontend sends temp_token in every request
                     Backend loads JSON session from Redis using that key
                     Finds the correct user_id, phone, email, and verification state
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

UPDATE  (mark invite consumed immediately)
  auth.invite
    SET status_id  = (SELECT id FROM auth.invite_status WHERE name = 'accepted')
        accepted_at = now()
    WHERE id = invite.id

REDIS SET
  key   : invite_verify:{temp_token}
  value : JSON (see Redis Key Structure below)
  TTL   : 20 minutes
  → full session JSON stored so Steps 2–4 can deliver OTPs and track verification state
```

> **Rule:** `auth.invite` status is set to `accepted` immediately in Step 1 once the token is validated.
> This prevents the same link from being reused if the tab is refreshed or the link is shared.

---

### STEP 2 — Send OTP

Sends a 6-digit OTP to the chain admin's phone or email depending on the `channel` field.
Both channels use the same endpoint — the service routes to the correct delivery address and OTP type.
This endpoint doubles as the **resend** endpoint — calling it again for the same channel resends a fresh OTP.

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

| HTTP | Error                                                          | Reason                                        |
|------|----------------------------------------------------------------|-----------------------------------------------|
| 400  | `invalid or expired verification session`                      | temp_token not found or TTL (20 min) expired  |
| 400  | `temp_token is required`                                       | Request body missing field                    |
| 400  | `channel must be sms or email`                                 | Invalid channel value                         |
| 400  | `phone not registered for this account`                        | channel=sms but phone is null                 |
| 400  | `email not registered for this account`                        | channel=email but email is null               |
| 400  | `please wait N seconds before requesting a new OTP`            | Resend cooldown — must wait 60 seconds        |
| 400  | `OTP type configuration missing`                               | `signup_sms` / `signup_email` not in DB       |
| 500  | `failed to send OTP`                                           | Omnichannel service failure                   |

> **Note:** OTP is valid for **5 minutes**. Maximum **3 attempts** allowed.
> After 3 wrong attempts, call this endpoint again to get a fresh OTP.
> **Resend cooldown:** 60 seconds between sends per channel. Both channels are independent.

**Database Operations**

```
REDIS GET
  key : invite_verify:{temp_token}
  → load JSON session
  → extract: user_id, phone, email, sms_verified, email_verified,
             sms_last_sent_at, email_last_sent_at

  if channel = "sms"  → delivery_address = phone
  if channel = "email" → delivery_address = email

COOLDOWN CHECK
  if (channel = "sms"   AND sms_last_sent_at   is set AND now - sms_last_sent_at   < 60s) → 400
  if (channel = "email" AND email_last_sent_at is set AND now - email_last_sent_at < 60s) → 400

READ
  auth.otp_type
    WHERE name = 'signup_sms'    (channel = "sms")
       OR name = 'signup_email'  (channel = "email")
  → get otp_type_id

UPDATE  (invalidate any previously active OTP for this delivery address)
  auth.otp
    SET is_used = true
    WHERE delivery_address = delivery_address
      AND is_used = false
      AND expires_at > now()

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

REDIS SET  (persist updated session with send timestamp)
  key   : invite_verify:{temp_token}
  value : JSON — same fields, updated sms_last_sent_at OR email_last_sent_at = now()
  TTL   : 20 minutes  (reset TTL)
```

---

### STEP 3 — Verify OTP

Validates the OTP entered by the chain admin for a specific channel.
Call once for `"sms"` and once for `"email"` — each verification is independent.

```
POST /api/v1/auth/otp/verify
```

**Auth Required:** No

**Request Body**

| Field        | Type   | Required | Description                                         |
|--------------|--------|----------|-----------------------------------------------------|
| `temp_token` | string | Yes      | Received from Step 1                                |
| `channel`    | string | Yes      | Which channel to verify — `"sms"` or `"email"`      |
| `otp`        | string | Yes      | 6-digit OTP received on the respective channel      |

```json
{ "temp_token": "550e8400-e29b-41d4-a716-446655440000", "channel": "sms",   "otp": "482910" }
```
```json
{ "temp_token": "550e8400-e29b-41d4-a716-446655440000", "channel": "email", "otp": "371284" }
```

**Success Response — 200**

```json
{
  "success": true,
  "data": {
    "message": "OTP verified",
    "status": "otp_verified"
  }
}
```

**Error Responses**

| HTTP | Error                                     | Reason                               |
|------|-------------------------------------------|--------------------------------------|
| 401  | `incorrect OTP`                           | Wrong code entered                   |
| 401  | `OTP not found or expired`                | OTP TTL (5 minutes) passed           |
| 401  | `too many incorrect attempts`             | 3 wrong attempts reached — resend    |
| 400  | `invalid or expired verification session` | temp_token not found or TTL expired  |
| 400  | `channel must be sms or email`            | Invalid channel value                |
| 400  | `otp must be 6 digits`                    | Invalid format                       |

**Database Operations**

```
REDIS GET
  key : invite_verify:{temp_token}
  → load JSON session
  → extract: user_id, phone, email, sms_verified, email_verified

  delivery_address = phone   (if channel = "sms")
  delivery_address = email   (if channel = "email")

READ
  auth.otp
    WHERE delivery_address = delivery_address
      AND is_used          = false
      AND expires_at       > now()
    ORDER BY created_at DESC
    LIMIT 1
  → get latest active OTP for that delivery address

  if otp.attempts >= 3
    → 401 too many incorrect attempts (call /otp/send again to reset)

  if SHA256(submitted_otp) != otp.code_hash
    → UPDATE auth.otp SET attempts = attempts + 1
    → 401 incorrect OTP

UPDATE (on success)
  auth.otp
    SET is_used = true
    WHERE id = otp.id

REDIS SET  (mark channel as verified in JSON session)
  key   : invite_verify:{temp_token}
  value : JSON — same fields, updated:
            sms_verified   = true   (if channel = "sms")
            email_verified = true   (if channel = "email")
  TTL   : 20 minutes  (reset TTL)
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
    "expires_in": 900
  }
}
```

| Field           | Description                                              |
|-----------------|----------------------------------------------------------|
| `access_token`  | JWT — valid for 15 minutes. Send in every request header |
| `refresh_token` | Opaque token — valid for 7 days. Rotate on every refresh |
| `expires_in`    | Access token expiry in seconds (900 = 15 min)            |

**Error Responses**

| HTTP | Error                                                    | Reason                                     |
|------|----------------------------------------------------------|--------------------------------------------|
| 400  | `phone verification required before setting password`    | SMS OTP not verified yet                   |
| 400  | `email verification required before setting password`    | Email OTP not verified yet                 |
| 400  | `invalid or expired verification session`                | temp_token expired (20 min) or not found   |
| 400  | `password must be at least 8 characters`                 | Password too short                         |

**Database Operations**

```
REDIS GET
  key : invite_verify:{temp_token}
  → load JSON session
  → check sms_verified = true   → if false: 400 phone verification required
  → check email_verified = true → if false: 400 email verification required
  → extract user_id from session

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

> **Rule:** If `auth.user` (tenant DB) or `auth.chain_user_mapping` (master DB) insert fails, the account is incomplete.
> Without the routing entry the user can never log in.
> Note: `auth.invite` status was already set to `accepted` in Step 1 — it is not touched here.
> Redis session key is deleted immediately after successful account activation.

---

## Token Lifecycle

```
Invite token  →  Single use, 48 hour TTL, SHA256 hash in auth.invite. Marked 'accepted' on Step 1.
temp_token    →  Single session, 20 minute TTL, JSON in Redis. Deleted after Step 4.
OTP           →  6 digits, 5 minute TTL, max 3 attempts, SHA256 in auth.otp
access_token  →  JWT, 15 minute TTL, SHA256 hash in auth.session (tenant DB)
refresh_token →  Opaque, 7 day TTL, SHA256 hash in auth.session, rotated on each use
```

---

## Redis Key Structure

Key: `invite_verify:{temp_token}` — JSON value, TTL 20 minutes (reset on each write).

```json
{
  "user_id":           "uuid",
  "phone":             "+919876543210",
  "email":             "rajesh@velammal.edu.in",
  "sms_verified":      false,
  "email_verified":    false,
  "sms_last_sent_at":  "2026-06-17T10:00:00Z",
  "email_last_sent_at": null
}
```

| Step          | Fields updated                                         | TTL        |
|---------------|--------------------------------------------------------|------------|
| Step 1        | All fields set, both `_verified` = false               | 20 minutes |
| Step 2 (sms)  | `sms_last_sent_at` = now                               | 20 minutes (reset) |
| Step 2 (email)| `email_last_sent_at` = now                             | 20 minutes (reset) |
| Step 3 (sms)  | `sms_verified` = true                                  | 20 minutes (reset) |
| Step 3 (email)| `email_verified` = true                                | 20 minutes (reset) |
| Step 4        | *(key deleted after password set)*                     | —          |

`sms_last_sent_at` and `email_last_sent_at` enforce the 60-second resend cooldown per channel.

---

## Important Rules for Frontend

1. Store `temp_token` in memory only (not localStorage) — it is short-lived.
2. After Step 4 or Step 5 succeeds, both `access_token` and `refresh_token` are returned in the response body. Store them securely.
3. Send `access_token` in every authenticated request:
   ```
   Authorization: Bearer <access_token>
   ```
4. When an API returns `401`, call `POST /auth/refresh` with `{ "refresh_token": "..." }` to get a new token pair.
5. After a successful refresh, replace both stored tokens with the new ones from the response.
6. If `/auth/refresh` also returns `401`, session is fully expired — redirect to login.

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
    "refresh_token": "dGhpcyBpcyBhIHJlZnJlc2ggdG9rZW4...",
    "expires_in": 900
  }
}
```

> Both `access_token` and `refresh_token` are returned in the response body.

**Error Responses**

| HTTP | Code                  | Error                             | Reason                                        |
|------|-----------------------|-----------------------------------|-----------------------------------------------|
| 401  | `invalid_credentials` | `invalid email or password`       | User not found or password mismatch           |
| 400  | `invalid_request`     | `email and password are required` | Missing or invalid fields                     |

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
  auth.session  (TENANT DB)
    user_id                  = user_id
    access_token_hash        = SHA256(access_token)
    refresh_token_hash       = SHA256(refresh_token)
    access_token_expires_at  = now() + 15 minutes
    refresh_token_expires_at = now() + 7 days
    ip_address               = request IP
    user_agent               = request User-Agent
```

> **Why two databases at login?** The master DB routing query is a single indexed lookup on `auth.chain_user_mapping.email`.
> It costs one fast round-trip and returns the exact tenant DB to use. Without it, the service has no way to know
> which of the N tenant databases holds this user's record. The tenant pool manager caches open connections,
> so Step B is a pool lookup (not a new TCP connection) on all requests after the first login.

---

### STEP 6 — Refresh Token

Issues a new access and refresh token pair using the current refresh token.
Called by the frontend when the access token expires.

```
POST /api/v1/auth/refresh
```

**Database:** Tenant DB  
**Auth Required:** No

**Request Body**

| Field           | Type   | Required | Description                            |
|-----------------|--------|----------|----------------------------------------|
| `refresh_token` | string | Yes      | Opaque refresh token from login/refresh response |

```json
{ "refresh_token": "opaque_refresh_token_here" }
```

**Success Response — 200**

```json
{
  "success": true,
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "bmV3X3JlZnJlc2hfdG9rZW4...",
    "expires_in": 900
  }
}
```

> Old refresh token is revoked; both new tokens are returned. Frontend must store the new `refresh_token` for the next rotation.

**Error Responses**

| HTTP | Error                              | Reason                                           |
|------|------------------------------------|--------------------------------------------------|
| 400  | `refresh_token is required`        | Request body missing field                       |
| 401  | `invalid or expired refresh token` | Token not found, revoked, or 7 day TTL passed    |

**Database Operations**

```
READ  (Tenant DB)
  auth.session
    WHERE refresh_token_hash = SHA256(request_body.refresh_token)
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
    "message": "logged out"
  }
}
```

**Error Responses**

| HTTP | Code             | Error                        | Reason                            |
|------|------------------|------------------------------|-----------------------------------|
| 401  | `missing_token`  | `missing or invalid token`   | Authorization header not present  |
| 500  | `logout_failed`  | `failed to logout`           | Session revocation failed         |

**Database Operations**

```
UPDATE  (Tenant DB)
  auth.session
    SET revoked_at = now()
    WHERE access_token_hash = SHA256(access_token from header)
```

---

## Phase 3 — Tenant Admin Onboarding

> **Status: NOT YET IMPLEMENTED**  
> The endpoints below (Steps 8–9) are planned but not yet registered in the router.
> They are included here as a design reference for the upcoming implementation.

> **Who does this:** chain_admin, after logging into the portal.
> **What it does:** Invite tenant_admins (branch admins) for each branch under their chain.
>
> chain_admin onboards tenant_admins by entering details one branch at a time through the form.

---

### STEP 8 — Get Branches

Returns all branches under the chain admin's chain.
Used to populate the branch dropdown for individual entry.

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

### STEP 9 — Submit Tenant Admin

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

NOTE: auth.user is NOT created at this step.
The tenant admin user row is created only after they accept the invite,
verify OTP (email + mobile), and set their password.
```

---

### STEP 10 — Send Invite Email (External Service)

This is not a direct API endpoint. It is an internal call to the external email service
made by the backend during Step 9.

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
Invite token  →  Single use, 48 hour TTL, SHA256 hash in auth.invite. Marked 'accepted' at Step 1.
temp_token    →  Single session, 20 minute TTL, JSON in Redis. Deleted after Step 4.
OTP           →  6 digits, 5 minute TTL, max 3 attempts, SHA256 in auth.otp
access_token  →  JWT, 15 minute TTL, SHA256 in auth.session (tenant DB)
refresh_token →  Opaque, 7 day TTL, returned in response body, SHA256 in auth.session, rotated on each use
```

---

## Updated Redis Key Structure

Key: `invite_verify:{temp_token}` — JSON, TTL 20 minutes.

| Event           | Field updated in JSON session    |
|-----------------|----------------------------------|
| Step 1          | All fields initialised           |
| Send OTP (sms)  | `sms_last_sent_at` = now         |
| Send OTP (email)| `email_last_sent_at` = now       |
| Verify OTP (sms)| `sms_verified` = true            |
| Verify OTP (email)| `email_verified` = true        |
| Step 4 success  | Key deleted                      |

---

## Complete API Summary

| Step | Method | Endpoint                              | Auth | Status      | Description                                      |
|------|--------|---------------------------------------|------|-------------|--------------------------------------------------|
| 1    | POST   | `/auth/invite/verify`                 | No   | ✅ Live     | Verify magic link token                          |
| 2a   | POST   | `/auth/otp/send`                      | No   | ✅ Live     | Send OTP — `channel: "sms"` (also handles resend)|
| 3a   | POST   | `/auth/otp/verify`                    | No   | ✅ Live     | Verify SMS OTP — `channel: "sms"`               |
| 2b   | POST   | `/auth/otp/send`                      | No   | ✅ Live     | Send OTP — `channel: "email"` (also handles resend)|
| 3b   | POST   | `/auth/otp/verify`                    | No   | ✅ Live     | Verify email OTP — `channel: "email"`           |
| 4    | POST   | `/auth/invite/set-password`           | No   | ✅ Live     | Set password, activate account (both channels must be verified) |
| 5    | POST   | `/auth/login`                         | No   | ✅ Live     | Login with email + password                      |
| 6    | POST   | `/auth/refresh`                       | No   | ✅ Live     | Refresh token pair (body: `{ refresh_token }`)   |
| 7    | POST   | `/auth/logout`                        | Yes  | ✅ Live     | Logout, revoke session                           |
| 8    | GET    | `/chain-admin/branches`               | Yes  | 🔲 Planned  | Get all branches                                 |
| 9    | POST   | `/chain-admin/tenant-admins`          | Yes  | 🔲 Planned  | Submit tenant admin for a branch                 |

---

*Document version: 2.2 | Module: Chain Admin Onboarding | Status: Phase 1 (Steps 1–7) Live — Phase 2 (Steps 8–9) Planned*
