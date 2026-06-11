-- ================================================================
-- EDUPULSE MASTER DB — ONBOARDING SCHEMA
-- Database : edupulse-master (PostgreSQL 16)
-- Schema   : onboarding
--
-- Purpose:
--   Collects school information from management during signup.
--   Drives the three-level verification flow.
--   Once all three levels pass → routes to payment (billing schema).
--
-- Cross-schema dependencies:
--   auth.management_user  ← chain.created_by, branch_document.uploaded_by
--                            branch_document.reviewed_by
--   billing.plan          ← branch_subscription.plan_id
--
-- Three Verification Levels:
--   L1 — User verification    : email OTP + phone OTP (auth schema flags)
--   L2 — Regulatory check     : UDISE code + affiliation number vs govt API
--   L3 — Document review      : recognition certificate + affiliation cert
--
-- After branch_verification.overall_status = 'VERIFIED'
--   → payment flow starts (billing schema)
-- ================================================================

CREATE SCHEMA IF NOT EXISTS onboarding;


-- ================================================================
-- 1. CHAIN
--    Top-level entity. One chain = one school brand / group.
--    Example: "Velammal" is a chain.
--    Created by management user after L1 (email+phone verified).
-- ================================================================

CREATE TABLE onboarding.chain (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(200) NOT NULL,
    logo_url    VARCHAR(500),
    pan_number  VARCHAR(20)  UNIQUE,
    gst_number  VARCHAR(20)  UNIQUE,
    is_active   BOOLEAN      NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT chain_pan_format CHECK (
        pan_number IS NULL OR pan_number ~ '^[A-Z]{5}[0-9]{4}[A-Z]{1}$'
    ),
    CONSTRAINT chain_gst_format CHECK (
        gst_number IS NULL OR length(gst_number) = 15
    )
);

CREATE TRIGGER trg_chain_updated_at
    BEFORE UPDATE ON onboarding.chain
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE onboarding.chain IS 'One row per school brand/group. Created by the external onboarding service after payment — no management_user exists yet at this point. Chain admins are linked via auth.management_user.chain_id.';
COMMENT ON COLUMN onboarding.chain.pan_number IS 'Required for GST invoice generation. Validated against PAN regex.';


-- ================================================================
-- 2. BRANCH
--    One branch = one physical school campus.
--    Example: "Velammal - Madurai" is a branch of chain "Velammal".
--    A chain must have at least one branch.
-- ================================================================

CREATE TABLE onboarding.branch (
    id                 UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    chain_id           UUID         NOT NULL REFERENCES onboarding.chain(id),
    name               VARCHAR(200) NOT NULL,
    address            TEXT         NOT NULL,
    city               VARCHAR(100) NOT NULL,
    state              VARCHAR(100) NOT NULL,
    pincode            VARCHAR(10)  NOT NULL,
    board_type         VARCHAR(20)  NOT NULL,     -- CBSE, ICSE, STATE_BOARD, IB, IGCSE
    school_type        VARCHAR(30)  NOT NULL,     -- GOVT, PRIVATE, AIDED, UNAIDED
    establishment_year INTEGER,
    is_active          BOOLEAN      NOT NULL DEFAULT true,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT branch_board_type_check CHECK (
        board_type = ANY (ARRAY['CBSE', 'ICSE', 'STATE_BOARD', 'IB', 'IGCSE'])
    ),
    CONSTRAINT branch_school_type_check CHECK (
        school_type = ANY (ARRAY['GOVT', 'PRIVATE', 'AIDED', 'UNAIDED'])
    ),
    CONSTRAINT branch_establishment_year_check CHECK (
        establishment_year IS NULL
        OR (establishment_year BETWEEN 1800 AND EXTRACT(YEAR FROM now())::INTEGER)
    ),
    CONSTRAINT branch_pincode_format CHECK (pincode ~ '^[0-9]{6}$')
);

CREATE INDEX idx_branch_chain_id ON onboarding.branch (chain_id);
CREATE INDEX idx_branch_pincode  ON onboarding.branch (pincode);

CREATE TRIGGER trg_branch_updated_at
    BEFORE UPDATE ON onboarding.branch
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

COMMENT ON COLUMN onboarding.branch.board_type  IS 'Drives L2 logic: CBSE/ICSE branches must provide affiliation_number; STATE_BOARD/IB/IGCSE may skip it.';
COMMENT ON COLUMN onboarding.branch.school_type IS 'Used for document type requirements during L3 verification.';


-- ================================================================
-- 3. BRANCH REGULATORY  (L2 Verification Data)
--    UDISE code and affiliation number collected per branch.
--    One row per branch (1:1). Created when branch is created.
--    Updated as codes are submitted and verified.
-- ================================================================

CREATE TABLE onboarding.branch_regulatory (
    id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id             UUID        NOT NULL UNIQUE REFERENCES onboarding.branch(id) ON DELETE CASCADE,
    udise_code            VARCHAR(20),            -- 11-digit UDISE code from DISE portal
    affiliation_number    VARCHAR(50),            -- Required if board_type = CBSE or ICSE
    affiliation_board     VARCHAR(20),            -- mirrors branch.board_type for clarity
    udise_verified        BOOLEAN     NOT NULL DEFAULT false,
    affiliation_verified  BOOLEAN     NOT NULL DEFAULT false,
    udise_raw_response    JSONB,                  -- raw JSON from govt UDISE portal API
    verified_at           TIMESTAMPTZ,            -- when both applicable checks passed
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_branch_regulatory_branch ON onboarding.branch_regulatory (branch_id);
CREATE INDEX idx_branch_regulatory_udise  ON onboarding.branch_regulatory (udise_code) WHERE udise_code IS NOT NULL;

COMMENT ON TABLE  onboarding.branch_regulatory IS 'L2 verification data. 1:1 with branch. Created alongside branch row.';
COMMENT ON COLUMN onboarding.branch_regulatory.udise_code         IS '11-digit code assigned by DISE portal. Verified via govt API.';
COMMENT ON COLUMN onboarding.branch_regulatory.affiliation_number IS 'Mandatory for CBSE/ICSE branches. Skip for STATE_BOARD/IB/IGCSE.';
COMMENT ON COLUMN onboarding.branch_regulatory.udise_raw_response IS 'Full govt portal response stored for audit. Never delete.';


-- ================================================================
-- 4. BRANCH DOCUMENT  (L3 Verification Data)
--    Documents uploaded by management and reviewed by EduPulse ops.
--    Multiple documents per branch (recognition cert, affiliation cert, etc).
-- ================================================================

CREATE TABLE onboarding.branch_document (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id        UUID         NOT NULL REFERENCES onboarding.branch(id) ON DELETE CASCADE,
    uploaded_by      UUID         NOT NULL,       -- → auth.management_user.id
    document_type    VARCHAR(50)  NOT NULL,
    file_url         VARCHAR(500) NOT NULL,       -- S3 / GCS signed path
    file_name        VARCHAR(255) NOT NULL,
    file_size_bytes  BIGINT,
    mime_type        VARCHAR(100),
    status           VARCHAR(20)  NOT NULL DEFAULT 'PENDING',
    reviewed_by      UUID,                        -- → auth.management_user.id (EduPulse ops)
    rejection_reason TEXT,
    reviewed_at      TIMESTAMPTZ,
    uploaded_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT branch_document_type_check CHECK (
        document_type = ANY (ARRAY[
            'school_recognition_certificate',
            'affiliation_certificate',
            'udise_document',
            'pan_card',
            'gst_certificate',
            'other'
        ])
    ),
    CONSTRAINT branch_document_status_check CHECK (
        status = ANY (ARRAY['PENDING', 'APPROVED', 'REJECTED'])
    ),
    CONSTRAINT branch_document_rejection_requires_reviewer CHECK (
        status <> 'REJECTED' OR (reviewed_by IS NOT NULL AND rejection_reason IS NOT NULL)
    )
);

CREATE INDEX idx_branch_document_branch ON onboarding.branch_document (branch_id);
CREATE INDEX idx_branch_document_status ON onboarding.branch_document (branch_id, status) WHERE status = 'PENDING';

COMMENT ON COLUMN onboarding.branch_document.uploaded_by     IS 'FK to auth.management_user.id — the management user who uploaded this doc.';
COMMENT ON COLUMN onboarding.branch_document.reviewed_by     IS 'FK to auth.management_user.id — EduPulse internal ops member who reviewed.';
COMMENT ON COLUMN onboarding.branch_document.rejection_reason IS 'Required when status = REJECTED. Constraint enforces this.';


-- ================================================================
-- 5. BRANCH COMMUNICATION
--    Official school contact details collected during onboarding.
--    Used to send messages to parents and reach the school.
--    1:1 with branch.
-- ================================================================

CREATE TABLE onboarding.branch_communication (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id        UUID         NOT NULL UNIQUE REFERENCES onboarding.branch(id) ON DELETE CASCADE,
    official_email   VARCHAR(255),
    official_phone   VARCHAR(20),
    whatsapp_number  VARCHAR(20),                 -- used for parent broadcast messages
    website_url      VARCHAR(500),
    email_verified   BOOLEAN      NOT NULL DEFAULT false,
    phone_verified   BOOLEAN      NOT NULL DEFAULT false,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT branch_comm_contact_check CHECK (
        official_email IS NOT NULL OR official_phone IS NOT NULL
    )
);

CREATE INDEX idx_branch_comm_branch ON onboarding.branch_communication (branch_id);

CREATE TRIGGER trg_branch_communication_updated_at
    BEFORE UPDATE ON onboarding.branch_communication
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

COMMENT ON COLUMN onboarding.branch_communication.whatsapp_number IS 'School WhatsApp Business number. Used for parent notifications.';
COMMENT ON COLUMN onboarding.branch_communication.email_verified  IS 'Set to true after OTP verification of official_email.';
COMMENT ON COLUMN onboarding.branch_communication.phone_verified  IS 'Set to true after OTP verification of official_phone.';


-- ================================================================
-- 6. BRANCH VERIFICATION
--    Tracks the verification state across all three levels.
--    1:1 with branch. Created alongside branch row.
--
--    L1  — User verification   : management email + phone verified (from auth.management_user)
--    L2  — Regulatory check    : UDISE + affiliation verified (from branch_regulatory)
--    L3  — Document review     : recognition cert + affiliation cert approved (from branch_document)
--
--    Transition: overall_status → 'VERIFIED' triggers payment flow.
-- ================================================================

CREATE TABLE onboarding.branch_verification (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id           UUID        NOT NULL UNIQUE REFERENCES onboarding.branch(id) ON DELETE CASCADE,

    -- L1: User identity verified (email OTP + phone OTP)
    l1_status           VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    l1_completed_at     TIMESTAMPTZ,

    -- L2: Regulatory codes verified against govt portals
    l2_status           VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    l2_completed_at     TIMESTAMPTZ,

    -- L3: Documents reviewed and approved by EduPulse ops
    l3_status           VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    l3_completed_at     TIMESTAMPTZ,

    -- Aggregate: set to VERIFIED only when L1 + L2 + L3 all pass
    overall_status      VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    overall_verified_at TIMESTAMPTZ,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT branch_verification_l1_check CHECK (
        l1_status = ANY (ARRAY['PENDING', 'VERIFIED', 'FAILED'])
    ),
    CONSTRAINT branch_verification_l2_check CHECK (
        l2_status = ANY (ARRAY['PENDING', 'VERIFIED', 'FAILED', 'NOT_REQUIRED'])
    ),
    CONSTRAINT branch_verification_l3_check CHECK (
        l3_status = ANY (ARRAY['PENDING', 'APPROVED', 'REJECTED'])
    ),
    CONSTRAINT branch_verification_overall_check CHECK (
        overall_status = ANY (ARRAY['PENDING', 'IN_PROGRESS', 'VERIFIED', 'REJECTED'])
    ),
    -- overall_verified_at must be set when overall_status = VERIFIED
    CONSTRAINT branch_verification_verified_at_check CHECK (
        overall_status <> 'VERIFIED' OR overall_verified_at IS NOT NULL
    )
);

CREATE INDEX idx_branch_verification_branch  ON onboarding.branch_verification (branch_id);
CREATE INDEX idx_branch_verification_overall ON onboarding.branch_verification (overall_status)
    WHERE overall_status NOT IN ('VERIFIED', 'REJECTED');

CREATE TRIGGER trg_branch_verification_updated_at
    BEFORE UPDATE ON onboarding.branch_verification
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE  onboarding.branch_verification IS '1:1 with branch. Source of truth for verification progress. overall_status = VERIFIED unblocks payment.';
COMMENT ON COLUMN onboarding.branch_verification.l1_status IS 'Driven by auth.management_user.is_email_verified AND is_phone_verified.';
COMMENT ON COLUMN onboarding.branch_verification.l2_status IS 'NOT_REQUIRED used for STATE_BOARD branches where affiliation check is skipped.';
COMMENT ON COLUMN onboarding.branch_verification.l3_status IS 'Set by EduPulse ops after manually reviewing branch_document rows.';


-- ================================================================
-- 7. BRANCH SUBSCRIPTION
--    Records the plan selected by management during onboarding,
--    before payment is made. This is the "intent" record.
--
--    After payment succeeds:
--      → billing.branch_plan is created as the authoritative record
--      → this row's payment_reference is filled in
--
--    Do NOT use this for billing logic — use billing.branch_plan.
-- ================================================================

CREATE TABLE onboarding.branch_subscription (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id         UUID        NOT NULL UNIQUE REFERENCES onboarding.branch(id) ON DELETE CASCADE,
    plan_id           UUID        NOT NULL,       -- → billing.plan.id
    status            VARCHAR(20) NOT NULL DEFAULT 'PENDING_PAYMENT',
    started_at        TIMESTAMPTZ,                -- set after payment confirmed
    expires_at        TIMESTAMPTZ,                -- set after payment confirmed
    payment_reference VARCHAR(100),               -- Razorpay payment_id, filled post-payment
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT branch_subscription_status_check CHECK (
        status = ANY (ARRAY['PENDING_PAYMENT', 'ACTIVE', 'EXPIRED', 'CANCELLED'])
    )
);

CREATE INDEX idx_branch_subscription_branch ON onboarding.branch_subscription (branch_id);
CREATE INDEX idx_branch_subscription_plan   ON onboarding.branch_subscription (plan_id);

CREATE TRIGGER trg_branch_subscription_updated_at
    BEFORE UPDATE ON onboarding.branch_subscription
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TABLE  onboarding.branch_subscription IS 'Plan selection intent during onboarding, before payment. Authoritative billing record is billing.branch_plan.';
COMMENT ON COLUMN onboarding.branch_subscription.plan_id           IS 'FK to billing.plan.id — enforced at app layer (cross-schema).';
COMMENT ON COLUMN onboarding.branch_subscription.payment_reference IS 'Razorpay payment_id. Populated by billing service after payment.captured webhook.';
COMMENT ON COLUMN onboarding.branch_subscription.started_at        IS 'Set to 1st of next month after payment confirmed. Mirrors billing.branch_plan.starts_at.';


-- ================================================================
-- CROSS-SCHEMA FK SUMMARY (enforced at application layer)
--
--   onboarding.branch_document.uploaded_by  → auth.management_user.id
--   onboarding.branch_document.reviewed_by  → auth.management_user.id
--   onboarding.branch_subscription.plan_id  → billing.plan.id
--
-- REVERSE REFERENCES (other schemas pointing here):
--   auth.management_user.chain_id           → onboarding.chain.id
--     Chain is created first (by onboarding service post-payment).
--     Management user is created later when the admin sets up their
--     portal account. The link flows from management_user → chain,
--     not the other way around.
--
-- TENANT DB BOUNDARY:
--   Branch admins, teachers, students, and parents are NOT in
--   the master DB. They live in the per-school tenant database.
--   The tenant DB links back to onboarding.branch via branch_id.
-- ================================================================
