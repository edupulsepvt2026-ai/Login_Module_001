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

| Table                       | Schema       | Purpose                                      |
|-----------------------------|--------------|----------------------------------------------|
| `auth.invite`               | Master DB    | Stores the magic link token and its status   |
| `auth.invite_status`        | Master DB    | Lookup: pending / accepted / expired / revoked |
| `auth.management_user`      | Master DB    | Chain admin credentials and profile          |
| `auth.otp_type`             | Master DB    | Lookup: OTP type config (TTL, max attempts)  |
| `auth.otp`                  | Master DB    | Stores hashed OTP codes                      |
| `auth.session`              | Master DB    | Access and refresh token hashes              |
| `auth.audit_log`            | Master DB    | Append-only security event trail             |
| `onboarding.chain`          | Master DB    | Chain name and details                       |
| `onboarding.branch`         | Master DB    | Branch details per chain                     |
| Redis                       | Cache        | Temporary verification session (temp_token)  |

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
  value : {user_id}:{phone}
  TTL   : 10 minutes
```

> **Rule:** Do NOT update `auth.invite` status here yet.
> Status moves to `accepted` only in Step 4 after password is set successfully.

---

### STEP 2 — Send OTP

Sends a 6-digit OTP to the phone number registered during onboarding.

```
POST /api/v1/auth/otp/send
```

**Auth Required:** No

**Request Body**

| Field        | Type   | Required | Description                            |
|--------------|--------|----------|----------------------------------------|
| `temp_token` | string | Yes      | Received from Step 1 invite/verify     |

```json
{
  "temp_token": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Success Response — 200**

```json
{
  "success": true,
  "data": {
    "message": "OTP sent to registered mobile number"
  }
}
```

**Error Responses**

| HTTP | Error                                     | Reason                               |
|------|-------------------------------------------|--------------------------------------|
| 400  | `invalid or expired verification session` | temp_token not found or expired      |
| 400  | `temp_token is required`                  | Request body missing field           |
| 500  | `failed to send OTP`                      | SMS provider failure                 |

> **Note:** OTP is valid for **5 minutes**. Maximum **3 attempts** allowed.
> After 3 wrong attempts, the chain admin must request a new OTP.

**Database Operations**

```
REDIS GET
  key : invite_verify:{temp_token}
  → validate session exists
  → extract phone number from value

READ
  auth.otp_type
    WHERE name = 'signup_sms'
  → get otp_type_id, TTL (300 seconds), max_attempts (3)

INSERT
  auth.otp
    otp_type_id      = otp_type.id
    code_hash        = SHA256(generated_6_digit_code)
    delivery_address = phone
    attempts         = 0
    is_used          = false
    expires_at       = now() + 5 minutes

  → raw OTP code is sent via SMS, never stored
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
  → extract phone number

READ
  auth.otp
    WHERE delivery_address = phone
      AND is_used          = false
      AND expires_at       > now()
    ORDER BY created_at DESC
    LIMIT 1
  → get latest active OTP

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
    metadata   = { "delivery_address": "masked_phone" }

REDIS SET  (update session — mark OTP as verified)
  key   : invite_verify:{temp_token}
  value : {user_id}:{phone}:otp_verified
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
  → extract user_id

UPDATE
  auth.management_user
    SET password_hash    = bcrypt(password, cost=12)
        is_email_verified = true
        is_phone_verified = true
        updated_at        = now()
    WHERE id = user_id

UPDATE
  auth.invite
    SET status_id   = (SELECT id FROM auth.invite_status WHERE name = 'accepted')
        accepted_at = now()
    WHERE management_user_id = user_id
      AND accepted_at IS NULL

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
  auth.audit_log (two entries)
    1. event_type = 'password_created'
       user_id    = user_id
       metadata   = { "chain_id": "..." }

    2. event_type = 'login_success'
       user_id    = user_id
       metadata   = { "chain_id": "...", "session_id": "..." }

REDIS DEL
  key : invite_verify:{temp_token}
  → clean up session immediately after success
```

> **Rule:** All DB operations in Step 4 must run inside a single transaction.
> If session creation fails, roll back the password update and invite status update.

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

| Key pattern                    | Value                              | TTL        | Set in  | Deleted in |
|--------------------------------|------------------------------------|------------|---------|------------|
| `invite_verify:{temp_token}`   | `{user_id}:{phone}`                | 10 minutes | Step 1  | —          |
| `invite_verify:{temp_token}`   | `{user_id}:{phone}:otp_verified`   | 10 minutes | Step 3  | Step 4     |

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

*Document version: 2.0 | Module: Chain Admin Onboarding | Status: Draft*
