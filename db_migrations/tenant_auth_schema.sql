-- ================================================================
-- EDUPULSE TENANT DB — AUTH SCHEMA
-- Database : edupulse-tenant (PostgreSQL 16)
-- Schema   : auth
--
-- Design: unified user model with management_type scoping
--
-- All users (chain_admin, tenant_admin, teacher, parent) live in
-- a single auth.user table. Scope is stored inline as two columns:
--   management_type_id → FK to auth.management_type ('chain'|'tenant')
--   management_id      → the actual chain_id or tenant_id UUID
--
-- chain_admin  : management_type = 'chain',  management_id = chain UUID
-- tenant_admin : management_type = 'tenant', management_id = tenant UUID
-- teacher      : management_type = 'tenant', management_id = tenant UUID
-- parent       : management_type = 'tenant', management_id = tenant UUID
--
-- The same two columns replace tenant_id / chain_id everywhere:
-- auth.invite and auth.audit_log follow the same pattern.
--
-- Tables:
--   Lookup  : management_type, otp_type, invite_status,
--             audit_event_type, role, permission, role_permission
--   Core    : user, otp, session, password_history, invite, audit_log
-- ================================================================

CREATE SCHEMA IF NOT EXISTS auth;

CREATE OR REPLACE FUNCTION auth.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


-- ================================================================
-- LOOKUP TABLES
-- ================================================================

-- ── Management Type ─────────────────────────────────────────────
-- Two rows only: 'chain' and 'tenant'.
-- Used across user, invite, and audit_log to identify whether
-- management_id refers to a chain UUID or a tenant/branch UUID.
CREATE TABLE auth.management_type (
    id   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(20) NOT NULL UNIQUE,

    CONSTRAINT chk_management_type_name CHECK (name IN ('chain', 'tenant'))
);

INSERT INTO auth.management_type (name) VALUES ('chain'), ('tenant')
ON CONFLICT DO NOTHING;


-- ── OTP Type ────────────────────────────────────────────────────
CREATE TABLE auth.otp_type (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name             VARCHAR(50) NOT NULL UNIQUE,
    ttl_seconds      INTEGER     NOT NULL DEFAULT 300,
    max_attempts     INTEGER     NOT NULL DEFAULT 3,
    delivery_channel VARCHAR(10) NOT NULL,

    CONSTRAINT chk_otp_type_ttl      CHECK (ttl_seconds > 0),
    CONSTRAINT chk_otp_type_attempts CHECK (max_attempts > 0),
    CONSTRAINT chk_otp_type_channel  CHECK (delivery_channel = ANY (ARRAY['email', 'sms', 'both']))
);

INSERT INTO auth.otp_type (name, ttl_seconds, max_attempts, delivery_channel) VALUES
    ('signup_email',     600, 3, 'email'),
    ('signup_sms',       300, 3, 'sms'),
    ('onboarding_email', 600, 3, 'email'),
    ('onboarding_sms',   300, 3, 'sms'),
    ('password_reset',   300, 3, 'both'),
    ('two_factor',       120, 3, 'both')
ON CONFLICT DO NOTHING;


-- ── Invite Status ───────────────────────────────────────────────
CREATE TABLE auth.invite_status (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(50) NOT NULL UNIQUE,
    description TEXT
);

INSERT INTO auth.invite_status (name, description) VALUES
    ('pending',  'Sent, awaiting recipient to accept'),
    ('accepted', 'Recipient completed account setup'),
    ('expired',  'Link TTL elapsed without acceptance'),
    ('revoked',  'Manually cancelled by sender or ops')
ON CONFLICT DO NOTHING;


-- ── Audit Event Type ────────────────────────────────────────────
CREATE TABLE auth.audit_event_type (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(100) NOT NULL UNIQUE,
    category    VARCHAR(50)  NOT NULL,
    description TEXT
);

INSERT INTO auth.audit_event_type (name, category, description) VALUES
    ('login_success',          'auth',       'Credentials accepted'),
    ('login_failure',          'auth',       'Credentials rejected'),
    ('account_locked',         'auth',       'Locked after repeated failures'),
    ('account_unlocked',       'auth',       'Lock expired or admin reset'),
    ('logout',                 'auth',       'User-initiated sign-out'),
    ('otp_requested',          'otp',        'OTP generated and sent'),
    ('otp_verified',           'otp',        'OTP accepted'),
    ('otp_failed',             'otp',        'Wrong OTP entered'),
    ('password_created',       'credential', 'First password set'),
    ('password_changed',       'credential', 'Password updated by user'),
    ('password_reset_request', 'credential', 'Reset flow initiated'),
    ('invite_sent',            'invite',     'Invite link sent to recipient'),
    ('invite_accepted',        'invite',     'Account setup completed via invite'),
    ('invite_resent',          'invite',     'Invite link resent on request'),
    ('invite_revoked',         'invite',     'Invite cancelled')
ON CONFLICT DO NOTHING;


-- ── Role ────────────────────────────────────────────────────────
CREATE TABLE auth.role (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name           VARCHAR(50) NOT NULL UNIQUE,
    description    TEXT,
    is_system_role BOOLEAN     NOT NULL DEFAULT false,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO auth.role (name, description, is_system_role) VALUES
    ('chain_admin',  'Chain-level admin — access to all branches under the chain', true),
    ('tenant_admin', 'Branch-level admin — access scoped to one branch',           true),
    ('teacher',      'Teaching staff at a branch',                                 true),
    ('parent',       'Parent or guardian of a student',                            true)
ON CONFLICT DO NOTHING;


-- ── Permission ──────────────────────────────────────────────────
CREATE TABLE auth.permission (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    resource    VARCHAR(100) NOT NULL,
    action      VARCHAR(50)  NOT NULL,
    description TEXT,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT uq_permission UNIQUE (resource, action)
);


-- ── Role Permission ─────────────────────────────────────────────
CREATE TABLE auth.role_permission (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    role_id       UUID        NOT NULL REFERENCES auth.role(id) ON DELETE CASCADE,
    permission_id UUID        NOT NULL REFERENCES auth.permission(id) ON DELETE CASCADE,
    granted_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT uq_role_permission UNIQUE (role_id, permission_id)
);


-- ================================================================
-- CORE TABLES
-- ================================================================

-- ── User (unified — all roles) ───────────────────────────────────
-- Single table for all user types.
-- management_type_id + management_id together identify which chain
-- or branch this user belongs to:
--   chain_admin  → type='chain',  management_id = chain UUID
--   tenant_admin → type='tenant', management_id = tenant UUID
--   teacher      → type='tenant', management_id = tenant UUID
--   parent       → type='tenant', management_id = tenant UUID
--
-- username is nullable — set only for management users.
CREATE TABLE auth."user" (
    id                    UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    role_id               UUID         NOT NULL REFERENCES auth.role(id),
    management_type_id    UUID         NOT NULL REFERENCES auth.management_type(id),
    management_id         UUID         NOT NULL,
    name                  VARCHAR(150) NOT NULL,
    username              VARCHAR(100) UNIQUE,
    email                 VARCHAR(255) UNIQUE,
    phone                 VARCHAR(20)  UNIQUE,
    password_hash         VARCHAR(255),
    is_active             BOOLEAN      NOT NULL DEFAULT true,
    is_email_verified     BOOLEAN      NOT NULL DEFAULT false,
    is_phone_verified     BOOLEAN      NOT NULL DEFAULT false,
    onboarding_channel    VARCHAR(20),
    failed_login_attempts INTEGER      NOT NULL DEFAULT 0,
    locked_until          TIMESTAMPTZ,
    last_login_at         TIMESTAMPTZ,
    created_at            TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT chk_user_contact        CHECK ((email IS NOT NULL) OR (phone IS NOT NULL)),
    CONSTRAINT chk_user_login_attempts CHECK (failed_login_attempts >= 0),
    CONSTRAINT chk_user_channel        CHECK (
        onboarding_channel IS NULL OR
        onboarding_channel = ANY (ARRAY['manual', 'bulk_upload', 'invite'])
    )
);

CREATE INDEX idx_user_email      ON auth."user" (email)                    WHERE email IS NOT NULL;
CREATE INDEX idx_user_phone      ON auth."user" (phone)                    WHERE phone IS NOT NULL;
CREATE INDEX idx_user_locked     ON auth."user" (locked_until)             WHERE locked_until IS NOT NULL;
CREATE INDEX idx_user_role       ON auth."user" (role_id);
CREATE INDEX idx_user_mgmt       ON auth."user" (management_type_id, management_id);

CREATE TRIGGER trg_user_updated_at
    BEFORE UPDATE ON auth."user"
    FOR EACH ROW EXECUTE FUNCTION auth.set_updated_at();

COMMENT ON TABLE  auth."user"                       IS 'Unified user table for all roles. No separate management_user table.';
COMMENT ON COLUMN auth."user".management_type_id    IS 'FK to auth.management_type. Identifies whether management_id is a chain or tenant UUID.';
COMMENT ON COLUMN auth."user".management_id         IS 'chain UUID for chain_admin. tenant UUID for tenant_admin, teacher, parent.';
COMMENT ON COLUMN auth."user".username              IS 'Set for management users only. NULL for teachers and parents.';
COMMENT ON COLUMN auth."user".locked_until          IS 'NULL = not locked. Set after N failed login attempts.';


-- ── OTP ─────────────────────────────────────────────────────────
-- No user_id FK — OTPs are issued before a user row may exist.
-- User is identified via delivery_address after verification.
CREATE TABLE auth.otp (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    otp_type_id      UUID         NOT NULL REFERENCES auth.otp_type(id),
    code_hash        VARCHAR(255) NOT NULL,
    attempts         INTEGER      NOT NULL DEFAULT 0,
    is_used          BOOLEAN      NOT NULL DEFAULT false,
    delivery_address VARCHAR(255) NOT NULL,
    expires_at       TIMESTAMPTZ  NOT NULL,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT chk_otp_attempts CHECK (attempts >= 0)
);

CREATE INDEX idx_otp_active ON auth.otp (delivery_address, expires_at) WHERE is_used = false;

COMMENT ON COLUMN auth.otp.delivery_address IS 'Email or phone the OTP was sent to. Used to look up the user after verification — no direct FK.';


-- ── Session ─────────────────────────────────────────────────────
-- Stores both access token and refresh token hashes per session.
-- Access token : short-lived JWT (e.g. 15 min), verified in middleware
--                without a DB hit (signature check only). DB hit only
--                on refresh or logout.
-- Refresh token: long-lived opaque token (e.g. 7 days), hashed here.
--                Exchanged for a new access token via /auth/refresh.
-- Rotation     : each refresh issues a new refresh token and
--                invalidates the old one (refresh_token_hash updated,
--                refresh_token_last_rotated_at stamped).
CREATE TABLE auth.session (
    id                            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                       UUID         NOT NULL REFERENCES auth."user"(id) ON DELETE CASCADE,
    access_token_hash             VARCHAR(255) NOT NULL UNIQUE,
    refresh_token_hash            VARCHAR(255) NOT NULL UNIQUE,
    access_token_expires_at       TIMESTAMPTZ  NOT NULL,
    refresh_token_expires_at      TIMESTAMPTZ  NOT NULL,
    refresh_token_last_rotated_at TIMESTAMPTZ,
    ip_address                    INET,
    user_agent                    TEXT,
    device_fingerprint            VARCHAR(255),
    revoked_at                    TIMESTAMPTZ,
    created_at                    TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT chk_session_token_expiry CHECK (access_token_expires_at < refresh_token_expires_at)
);

CREATE INDEX idx_session_user         ON auth.session (user_id);
CREATE INDEX idx_session_live         ON auth.session (user_id, refresh_token_expires_at) WHERE revoked_at IS NULL;
CREATE INDEX idx_session_access_token ON auth.session (access_token_hash);
CREATE INDEX idx_session_refresh_token ON auth.session (refresh_token_hash);

COMMENT ON COLUMN auth.session.access_token_hash             IS 'SHA-256 of the JWT access token. Used only on logout/revoke — normal requests verify JWT signature in middleware without a DB hit.';
COMMENT ON COLUMN auth.session.refresh_token_hash            IS 'SHA-256 of the opaque refresh token. Checked on every /auth/refresh call.';
COMMENT ON COLUMN auth.session.access_token_expires_at       IS 'Short TTL — typically 15 minutes.';
COMMENT ON COLUMN auth.session.refresh_token_expires_at      IS 'Long TTL — typically 7 days. Session is dead when this passes.';
COMMENT ON COLUMN auth.session.refresh_token_last_rotated_at IS 'Stamped each time a refresh token is rotated. Detects reuse of old tokens.';
COMMENT ON COLUMN auth.session.revoked_at                    IS 'Non-null = session forcibly invalidated (logout, password change, admin revoke).';


-- ── Password History ────────────────────────────────────────────
CREATE TABLE auth.password_history (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID         NOT NULL REFERENCES auth."user"(id) ON DELETE CASCADE,
    password_hash VARCHAR(255) NOT NULL,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_pwd_history_user ON auth.password_history (user_id, created_at DESC);

COMMENT ON TABLE auth.password_history IS 'Last N hashes per user. App checks before accepting a new password to prevent reuse.';


-- ── Invite ──────────────────────────────────────────────────────
-- Single invited_by_user_id FK — no XOR needed since all users
-- are in auth.user.
-- management_type_id + management_id identify the scope of the
-- invite (which chain or branch it belongs to).
CREATE TABLE auth.invite (
    id                 UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    invited_by_user_id UUID         NOT NULL REFERENCES auth."user"(id),
    management_type_id UUID         NOT NULL REFERENCES auth.management_type(id),
    management_id      UUID         NOT NULL,
    target_role_id     UUID         NOT NULL REFERENCES auth.role(id),
    status_id          UUID         NOT NULL REFERENCES auth.invite_status(id),
    name               VARCHAR(150),
    email              VARCHAR(255),
    phone              VARCHAR(20),
    invite_token_hash  VARCHAR(255) NOT NULL UNIQUE,
    resend_count       INTEGER      NOT NULL DEFAULT 0,
    expires_at         TIMESTAMPTZ  NOT NULL,
    accepted_at        TIMESTAMPTZ,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT chk_invite_contact      CHECK ((email IS NOT NULL) OR (phone IS NOT NULL)),
    CONSTRAINT chk_invite_resend_count CHECK (resend_count >= 0)
);

CREATE INDEX idx_invite_email  ON auth.invite (email)                        WHERE email IS NOT NULL;
CREATE INDEX idx_invite_phone  ON auth.invite (phone)                        WHERE phone IS NOT NULL;
CREATE INDEX idx_invite_status ON auth.invite (status_id);
CREATE INDEX idx_invite_mgmt   ON auth.invite (management_type_id, management_id);
CREATE INDEX idx_invite_token  ON auth.invite (invite_token_hash);

COMMENT ON TABLE  auth.invite                       IS 'Drives the full onboarding chain: chain_admin → tenant_admin → teacher → parent.';
COMMENT ON COLUMN auth.invite.management_type_id    IS 'chain = invite is chain-scoped (e.g. tenant_admin invite). tenant = invite is branch-scoped.';
COMMENT ON COLUMN auth.invite.management_id         IS 'chain UUID or tenant UUID depending on management_type.';
COMMENT ON COLUMN auth.invite.name                  IS 'Recipient name — pre-filled on the registration form.';
COMMENT ON COLUMN auth.invite.invite_token_hash     IS 'SHA-256 hash of the raw magic link token. Raw token is never stored.';


-- ── Audit Log ───────────────────────────────────────────────────
-- Append-only. management_type_id + management_id replaces the
-- hardcoded tenant_id — supports auditing at chain or branch level.
CREATE TABLE auth.audit_log (
    id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id            UUID        REFERENCES auth."user"(id),
    management_type_id UUID        REFERENCES auth.management_type(id),
    management_id      UUID,
    event_type_id      UUID        NOT NULL REFERENCES auth.audit_event_type(id),
    ip_address         INET,
    user_agent         TEXT,
    metadata           JSONB,
    is_suspicious      BOOLEAN     NOT NULL DEFAULT false,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_user       ON auth.audit_log (user_id)                                          WHERE user_id IS NOT NULL;
CREATE INDEX idx_audit_mgmt       ON auth.audit_log (management_type_id, management_id, created_at DESC);
CREATE INDEX idx_audit_suspicious ON auth.audit_log (management_type_id, management_id, created_at DESC) WHERE is_suspicious = true;
CREATE INDEX idx_audit_meta_gin   ON auth.audit_log USING gin (metadata);

COMMENT ON TABLE  auth.audit_log                       IS 'Append-only security log. Never UPDATE or DELETE rows.';
COMMENT ON COLUMN auth.audit_log.management_type_id    IS 'Identifies whether management_id is a chain or tenant UUID.';
COMMENT ON COLUMN auth.audit_log.management_id         IS 'chain UUID or tenant UUID — scope of this audit event.';
COMMENT ON COLUMN auth.audit_log.is_suspicious         IS 'Set by app layer for anomalies (new device, unusual hour, etc.).';
