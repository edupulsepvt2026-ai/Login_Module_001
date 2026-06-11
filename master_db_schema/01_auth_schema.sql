-- ================================================================
-- EDUPULSE MASTER DB — AUTH SCHEMA
-- Database : edupulse-master (PostgreSQL 16)
-- Schema   : auth
--
-- Purpose:
--   Authentication and session management for chain-level admins
--   (chain admins) who onboard via the EduPulse onboarding portal.
--
-- Who is stored here:
--   Chain Admins — one account spans all branches under a chain.
--   Created by the external onboarding service post-payment.
--
-- Who is NOT stored here:
--   Branch Admins, Teachers, Students, Parents — all in the
--   per-school tenant database.
--
-- Tables:
--   Lookup  : otp_type, invite_status, audit_event_type
--   Core    : management_user, session, otp, invite, audit_log
-- ================================================================

CREATE SCHEMA IF NOT EXISTS auth;

-- Shared updated_at trigger (create once, reused by all schemas)
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;


-- ================================================================
-- LOOKUP TABLES  (seeded at deploy time, rarely change)
-- ================================================================

-- ── OTP Type ────────────────────────────────────────────────────
CREATE TABLE auth.otp_type (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name             VARCHAR(50) NOT NULL UNIQUE,
    ttl_seconds      INTEGER     NOT NULL DEFAULT 300,
    max_attempts     INTEGER     NOT NULL DEFAULT 3,
    delivery_channel VARCHAR(10) NOT NULL,

    CONSTRAINT otp_type_channel_check   CHECK (delivery_channel = ANY (ARRAY['email', 'sms', 'both'])),
    CONSTRAINT otp_type_ttl_check       CHECK (ttl_seconds > 0),
    CONSTRAINT otp_type_attempts_check  CHECK (max_attempts > 0)
);

INSERT INTO auth.otp_type (name, ttl_seconds, max_attempts, delivery_channel) VALUES
    ('signup_email',   600, 3, 'email'),
    ('signup_sms',     300, 3, 'sms'),
    ('password_reset', 300, 3, 'both'),
    ('two_factor',     120, 3, 'both')
ON CONFLICT DO NOTHING;


-- ── Invite Status ───────────────────────────────────────────────
CREATE TABLE auth.invite_status (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(20) NOT NULL UNIQUE,
    description TEXT
);

INSERT INTO auth.invite_status (name, description) VALUES
    ('pending',  'Sent, awaiting management to accept'),
    ('accepted', 'Management completed account setup'),
    ('expired',  'Link TTL elapsed without acceptance'),
    ('revoked',  'Manually cancelled by ops team')
ON CONFLICT DO NOTHING;


-- ── Audit Event Type ────────────────────────────────────────────
CREATE TABLE auth.audit_event_type (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(100) NOT NULL UNIQUE,
    category    VARCHAR(50)  NOT NULL,
    description TEXT,

    CONSTRAINT audit_event_category_check CHECK (
        category = ANY (ARRAY['auth', 'otp', 'credential', 'invite', 'onboarding', 'payment', 'subscription'])
    )
);

INSERT INTO auth.audit_event_type (name, category, description) VALUES
    ('login_success',          'auth',         'Credentials accepted'),
    ('login_failure',          'auth',         'Credentials rejected'),
    ('account_locked',         'auth',         'Locked after repeated failures'),
    ('account_unlocked',       'auth',         'Lock expired or admin reset'),
    ('logout',                 'auth',         'User-initiated sign-out'),
    ('otp_requested',          'otp',          'OTP generated and sent'),
    ('otp_verified',           'otp',          'OTP accepted'),
    ('otp_failed',             'otp',          'Wrong OTP entered'),
    ('password_created',       'credential',   'First password set via magic link'),
    ('password_changed',       'credential',   'Password updated by user'),
    ('password_reset_request', 'credential',   'Reset flow initiated'),
    ('invite_sent',            'invite',       'Magic link sent after payment confirmed'),
    ('invite_accepted',        'invite',       'Account setup completed via magic link'),
    ('invite_resent',          'invite',       'Magic link resent on request'),
    ('invite_revoked',         'invite',       'Magic link cancelled'),
    ('application_submitted',  'onboarding',   'School application submitted'),
    ('application_approved',   'onboarding',   'Application approved by EduPulse team'),
    ('application_rejected',   'onboarding',   'Application rejected by EduPulse team'),
    ('payment_initiated',      'payment',      'Razorpay order created'),
    ('payment_success',        'payment',      'Payment confirmed via webhook'),
    ('payment_failed',         'payment',      'Payment failed'),
    ('subscription_created',   'subscription', 'Branch plan activated post-payment'),
    ('subscription_cancelled', 'subscription', 'Branch plan cancelled')
ON CONFLICT DO NOTHING;


-- ================================================================
-- CORE TABLES
-- ================================================================

-- ── Management User (Chain Admin) ───────────────────────────────
-- Credentials for chain-level admins created during EduPulse
-- onboarding. One row per admin. Access spans all branches under
-- their chain.
--
-- WHO lives here:
--   Chain Admins only. Onboarded via the external EduPulse
--   onboarding service after payment is confirmed.
--
-- WHO does NOT live here:
--   Branch Admins, Teachers, Students, Parents — all stored in
--   the per-school tenant database.
CREATE TABLE auth.management_user (
    id                    UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    chain_id              UUID         NOT NULL,                   -- → onboarding.chain.id (cross-schema, app-layer FK)
    email                 VARCHAR(255) UNIQUE,
    phone                 VARCHAR(20)  UNIQUE,
    username              VARCHAR(100) UNIQUE,
    name                  VARCHAR(150) NOT NULL,
    password_hash         VARCHAR(255),
    is_active             BOOLEAN      NOT NULL DEFAULT true,
    is_email_verified     BOOLEAN      NOT NULL DEFAULT false,
    is_phone_verified     BOOLEAN      NOT NULL DEFAULT false,
    failed_login_attempts INTEGER      NOT NULL DEFAULT 0,
    locked_until          TIMESTAMPTZ,
    last_login_at         TIMESTAMPTZ,
    created_at            TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ  NOT NULL DEFAULT now(),

    -- at least one contact method must exist
    CONSTRAINT chk_mgmt_contact    CHECK ((email IS NOT NULL) OR (phone IS NOT NULL)),
    CONSTRAINT chk_failed_attempts CHECK (failed_login_attempts >= 0)
);

CREATE INDEX idx_mgmt_user_email    ON auth.management_user (email)        WHERE email IS NOT NULL;
CREATE INDEX idx_mgmt_user_phone    ON auth.management_user (phone)        WHERE phone IS NOT NULL;
CREATE INDEX idx_mgmt_user_chain    ON auth.management_user (chain_id);
CREATE INDEX idx_mgmt_user_locked   ON auth.management_user (locked_until) WHERE locked_until IS NOT NULL;

CREATE TRIGGER trg_management_user_updated_at
    BEFORE UPDATE ON auth.management_user
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE  auth.management_user IS 'Chain-level admin credentials (chain admins only). Branch admins, teachers, students, and parents are stored in the per-school tenant database.';
COMMENT ON COLUMN auth.management_user.chain_id      IS 'FK to onboarding.chain.id — cross-schema, enforced at app layer. This admin has access to all branches under this chain.';
COMMENT ON COLUMN auth.management_user.username      IS 'Login handle chosen during account setup. Unique globally. NULL until admin completes registration via invite link.';
COMMENT ON COLUMN auth.management_user.password_hash IS 'NULL until admin accepts magic link invite and sets a password.';
COMMENT ON COLUMN auth.management_user.locked_until  IS 'NULL = not locked. Set by app layer after N consecutive failed login attempts.';


-- ── OTP ─────────────────────────────────────────────────────────
-- One row per OTP issued. Never reuse — always insert a new row.
-- User is identified via delivery_address (email or phone).
CREATE TABLE auth.otp (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    otp_type_id      UUID         NOT NULL REFERENCES auth.otp_type(id),
    code_hash        VARCHAR(255) NOT NULL,    -- bcrypt/SHA-256 of the raw code
    attempts         INTEGER      NOT NULL DEFAULT 0,
    is_used          BOOLEAN      NOT NULL DEFAULT false,
    delivery_address VARCHAR(255) NOT NULL,    -- email or phone the OTP was sent to; used to identify the user
    expires_at       TIMESTAMPTZ  NOT NULL,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT otp_attempts_check CHECK (attempts >= 0)
);

CREATE INDEX idx_otp_active ON auth.otp (delivery_address, expires_at) WHERE is_used = false;

COMMENT ON TABLE  auth.otp IS 'Append-only. Insert a new row for every OTP. Never update code_hash of an existing row.';
COMMENT ON COLUMN auth.otp.code_hash        IS 'Store the hash, never the raw OTP. Verify by hashing the submitted code and comparing.';
COMMENT ON COLUMN auth.otp.delivery_address IS 'Email or phone the OTP was sent to. Used to look up and link the record to the user after verification.';


-- ── Session ─────────────────────────────────────────────────────
CREATE TABLE auth.session (
    id                 UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id            UUID         NOT NULL REFERENCES auth.management_user(id) ON DELETE CASCADE,
    access_token_hash  VARCHAR(255) NOT NULL UNIQUE,
    refresh_token_hash VARCHAR(255) NOT NULL UNIQUE,
    ip_address         INET,
    user_agent         TEXT,
    device_fingerprint VARCHAR(255),
    expires_at         TIMESTAMPTZ  NOT NULL,
    revoked_at         TIMESTAMPTZ,            -- NULL = active
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_session_user ON auth.session (user_id);
CREATE INDEX idx_session_live ON auth.session (user_id, expires_at) WHERE revoked_at IS NULL;

COMMENT ON COLUMN auth.session.revoked_at          IS 'NULL = active. Non-NULL = logged out or force revoked.';
COMMENT ON COLUMN auth.session.access_token_hash   IS 'SHA-256 of raw JWT. Lookup by hash, never store raw token.';
COMMENT ON COLUMN auth.session.device_fingerprint  IS 'Browser/device fingerprint for suspicious login detection.';


-- ── Invite ──────────────────────────────────────────────────────
-- Magic link sent to management after their payment is confirmed.
-- Management clicks the link to create their portal password.
CREATE TABLE auth.invite (
    id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    management_user_id UUID        NOT NULL REFERENCES auth.management_user(id),
    status_id          UUID        NOT NULL REFERENCES auth.invite_status(id),
    invite_token_hash  VARCHAR(255) NOT NULL UNIQUE,
    resend_count       INTEGER     NOT NULL DEFAULT 0,
    expires_at         TIMESTAMPTZ NOT NULL,
    accepted_at        TIMESTAMPTZ,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT invite_resend_count_check CHECK (resend_count >= 0)
);

CREATE INDEX idx_invite_user   ON auth.invite (management_user_id);
CREATE INDEX idx_invite_status ON auth.invite (status_id);
CREATE INDEX idx_invite_active ON auth.invite (management_user_id, expires_at)
    WHERE accepted_at IS NULL;

COMMENT ON COLUMN auth.invite.invite_token_hash IS 'SHA-256 of raw magic link token. Raw token sent only in the email link.';
COMMENT ON COLUMN auth.invite.resend_count      IS 'Incremented each time ops resends the invite. Used for rate limiting.';


-- ── Audit Log ───────────────────────────────────────────────────
-- Append-only security trail. Never UPDATE or DELETE rows.
CREATE TABLE auth.audit_log (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID        REFERENCES auth.management_user(id),  -- nullable: pre-auth events
    event_type_id UUID        NOT NULL REFERENCES auth.audit_event_type(id),
    ip_address    INET,
    user_agent    TEXT,
    metadata      JSONB,                  -- {"chain_id": "...", "branch_id": "...", "reason": "..."}
    is_suspicious BOOLEAN     NOT NULL DEFAULT false,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_user       ON auth.audit_log (user_id)            WHERE user_id IS NOT NULL;
CREATE INDEX idx_audit_time       ON auth.audit_log (created_at DESC);
CREATE INDEX idx_audit_suspicious ON auth.audit_log (created_at DESC)    WHERE is_suspicious = true;
CREATE INDEX idx_audit_metadata   ON auth.audit_log USING gin (metadata) WHERE metadata IS NOT NULL;

COMMENT ON TABLE  auth.audit_log IS 'Append-only. Never UPDATE or DELETE rows.';
COMMENT ON COLUMN auth.audit_log.user_id    IS 'NULL for pre-auth events (e.g., failed login with unknown email).';
COMMENT ON COLUMN auth.audit_log.metadata   IS 'Context-specific JSON: chain_id, branch_id, invoice_id, error details etc.';
