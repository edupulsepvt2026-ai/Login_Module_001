-- ================================================================
-- EDUPULSE TENANT DB — PARENTS SCHEMA
-- Database : edupulse-tenant (PostgreSQL 16)
-- Schema   : parents
--
-- Purpose:
--   Stores parent/guardian profiles, student records, and the
--   student admission (onboarding) application flow.
--   Credentials (email, phone, password, is_active, tenant_id)
--   are NOT duplicated here — they live in auth.user and are
--   fetched via the user_id FK join.
--
-- Account creation flow:
--   1. Parent receives invite (auth.invite) or self-registers
--   2. Parent verifies OTP via delivery_address (auth.otp)
--   3. Parent sets password → auth.user row created
--   4. parents.parent row created, linked via user_id
--   5. Parent adds student details → parents.student row created
--   6. Parent submits onboarding application for student admission
--
-- Tables:
--   parent               — Core parent/guardian profile
--   student              — Student profile (no auth account at this stage)
--   parent_student       — M:N link between parents and students
--   address              — Reusable address records
--   parent_address       — Junction: parent ↔ address (with label)
--   parent_contact       — Additional contact channels per parent
--   emergency_contact    — Emergency contacts listed per student
--   onboarding_application — Student admission application
--   application_document — Documents uploaded for an application
--
-- Cross-schema FKs (within this tenant DB):
--   parent.user_id                          → auth.user(id)
--   onboarding_application.reviewed_by_user_id → auth.user(id)
--   application_document.verified_by_user_id   → auth.user(id)
--
-- Masters FKs (app-layer enforced):
--   parent.gender_id                    → masters.genders(id)
--   student.blood_group_id              → masters.blood_group(id)
--   student.grade_applying_id           → masters.grade(id)
--   student.gender_id                   → masters.genders(id)
--   parent_student.relationship_type_id → masters.relationship_type(id)
--   parent_contact.contact_type_id      → masters.contact_type(id)
--   emergency_contact.relationship_type_id → masters.relationship_type(id)
--   onboarding_application.status_id    → masters.onboarding_status(id)
--   application_document.document_type_id → masters.document_type(id)
-- ================================================================

CREATE SCHEMA IF NOT EXISTS parents;


-- ================================================================
-- TABLES
-- ================================================================

-- ── Parent ──────────────────────────────────────────────────────
-- One row per parent/guardian. Stores only parent-specific profile data.
-- All auth-related fields (email, phone, is_active, tenant_id)
-- are read from auth.user via the user_id join.
CREATE TABLE parents.parent (
    id                UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           UUID         NOT NULL UNIQUE REFERENCES auth."user"(id) ON DELETE CASCADE,
    name              VARCHAR(150) NOT NULL,
    date_of_birth     DATE,
    gender_id         UUID,        -- → masters.genders(id)
    nationality       VARCHAR(100),
    occupation        VARCHAR(150),
    employer_name     VARCHAR(150),
    profile_photo_url VARCHAR(500),
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_parent_user_id ON parents.parent (user_id);

CREATE TRIGGER trg_parent_updated_at
    BEFORE UPDATE ON parents.parent
    FOR EACH ROW EXECUTE FUNCTION auth.set_updated_at();

COMMENT ON TABLE  parents.parent IS 'Parent/guardian profile. Credentials and contact info are in auth.user — join via user_id.';
COMMENT ON COLUMN parents.parent.user_id   IS 'FK to auth.user(id). UNIQUE — one parent profile per login account.';
COMMENT ON COLUMN parents.parent.gender_id IS 'FK to masters.genders(id). Enforced at app layer.';


-- ── Student ─────────────────────────────────────────────────────
-- One row per student. Students do not have their own login at this
-- stage — they are registered by their parent/guardian.
CREATE TABLE parents.student (
    id                   UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id            UUID         NOT NULL REFERENCES management.management_table(tenant_id),
    blood_group_id       UUID,        -- → masters.blood_group(id)
    grade_applying_id    UUID,        -- → masters.grade(id)
    name                 VARCHAR(150) NOT NULL,
    date_of_birth        DATE         NOT NULL,
    gender_id            UUID,        -- → masters.genders(id)
    nationality          VARCHAR(100),
    previous_school_name VARCHAR(255),
    photo_url            VARCHAR(500),
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_student_updated_at
    BEFORE UPDATE ON parents.student
    FOR EACH ROW EXECUTE FUNCTION auth.set_updated_at();

CREATE INDEX idx_student_tenant_id ON parents.student (tenant_id);

COMMENT ON TABLE  parents.student IS 'Student profile. Created and managed by the parent/guardian before admission is approved.';
COMMENT ON COLUMN parents.student.tenant_id         IS 'FK to management.management_table(tenant_id). Scopes the student to a branch. Required because students have no auth.user account.';
COMMENT ON COLUMN parents.student.blood_group_id    IS 'FK to masters.blood_group(id). Enforced at app layer.';
COMMENT ON COLUMN parents.student.grade_applying_id IS 'FK to masters.grade(id). Enforced at app layer.';
COMMENT ON COLUMN parents.student.gender_id         IS 'FK to masters.genders(id). Enforced at app layer.';


-- ── Parent Student ──────────────────────────────────────────────
-- M:N link between parents and students.
-- A student can have multiple guardians; a parent can have multiple
-- children enrolled. is_primary_guardian marks the main contact.
CREATE TABLE parents.parent_student (
    id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_id            UUID        NOT NULL REFERENCES parents.parent(id) ON DELETE CASCADE,
    student_id           UUID        NOT NULL REFERENCES parents.student(id) ON DELETE CASCADE,
    relationship_type_id UUID        NOT NULL, -- → masters.relationship_type(id)
    is_primary_guardian  BOOLEAN     NOT NULL DEFAULT false,
    has_custody          BOOLEAN     NOT NULL DEFAULT true,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT uq_parent_student UNIQUE (parent_id, student_id)
);

CREATE INDEX idx_ps_parent_id  ON parents.parent_student (parent_id);
CREATE INDEX idx_ps_student_id ON parents.parent_student (student_id);

COMMENT ON TABLE  parents.parent_student IS 'Links parents to their children. One row per parent-student pair.';
COMMENT ON COLUMN parents.parent_student.relationship_type_id IS 'FK to masters.relationship_type(id). Enforced at app layer.';
COMMENT ON COLUMN parents.parent_student.is_primary_guardian  IS 'True for the main point of contact for this student.';


-- ── Address ─────────────────────────────────────────────────────
-- Reusable address record. Linked to parents via parent_address.
CREATE TABLE parents.address (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    line1       VARCHAR(255) NOT NULL,
    line2       VARCHAR(255),
    city        VARCHAR(100) NOT NULL,
    state       VARCHAR(100) NOT NULL,
    postal_code VARCHAR(20)  NOT NULL,
    country     VARCHAR(100) NOT NULL DEFAULT 'India',
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

COMMENT ON TABLE parents.address IS 'Reusable address records. Linked to parents via parent_address junction.';


-- ── Parent Address ──────────────────────────────────────────────
-- Junction: one parent can have multiple addresses (home, office, etc.)
CREATE TABLE parents.parent_address (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_id  UUID        NOT NULL REFERENCES parents.parent(id) ON DELETE CASCADE,
    address_id UUID        NOT NULL REFERENCES parents.address(id) ON DELETE CASCADE,
    label      VARCHAR(50),
    is_primary BOOLEAN     NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT uq_parent_address UNIQUE (parent_id, address_id)
);

CREATE INDEX idx_pa_parent_id ON parents.parent_address (parent_id);

COMMENT ON TABLE  parents.parent_address IS 'Links a parent to one or more addresses. label indicates home/office/etc.';
COMMENT ON COLUMN parents.parent_address.is_primary IS 'True for the default correspondence address.';


-- ── Parent Contact ──────────────────────────────────────────────
-- Additional contact channels per parent (alternate phone, WhatsApp, etc.)
-- Primary email and mobile are in auth.user.
CREATE TABLE parents.parent_contact (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_id        UUID         NOT NULL REFERENCES parents.parent(id) ON DELETE CASCADE,
    contact_type_id  UUID         NOT NULL, -- → masters.contact_type(id)
    value            VARCHAR(150) NOT NULL,
    is_primary       BOOLEAN      NOT NULL DEFAULT false,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT uq_parent_contact UNIQUE (parent_id, contact_type_id, value)
);

CREATE INDEX idx_pc_parent_id ON parents.parent_contact (parent_id);

COMMENT ON TABLE  parents.parent_contact IS 'Extra contact channels per parent. Primary email/phone are in auth.user.';
COMMENT ON COLUMN parents.parent_contact.contact_type_id IS 'FK to masters.contact_type(id). Enforced at app layer.';


-- ── Emergency Contact ───────────────────────────────────────────
-- Emergency contacts listed per student. Not linked to a login account.
CREATE TABLE parents.emergency_contact (
    id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id           UUID        NOT NULL REFERENCES parents.student(id) ON DELETE CASCADE,
    name                 VARCHAR(150) NOT NULL,
    relationship_type_id UUID,        -- → masters.relationship_type(id)
    phone                VARCHAR(20) NOT NULL,
    email                VARCHAR(150),
    priority_order       INTEGER     NOT NULL DEFAULT 1,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_emergency_priority CHECK (priority_order > 0)
);

CREATE INDEX idx_ec_student_id ON parents.emergency_contact (student_id);

COMMENT ON TABLE  parents.emergency_contact IS 'Emergency contacts for a student. Cascade-deleted when student is removed.';
COMMENT ON COLUMN parents.emergency_contact.relationship_type_id IS 'FK to masters.relationship_type(id). Enforced at app layer.';
COMMENT ON COLUMN parents.emergency_contact.priority_order       IS '1 = first person to call. Higher number = lower priority.';


-- ── Onboarding Application ──────────────────────────────────────
-- Student admission application submitted by a parent.
-- status_id tracks the application through its lifecycle using
-- masters.onboarding_status.
CREATE TABLE parents.onboarding_application (
    id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id            UUID        NOT NULL REFERENCES parents.student(id),
    submitted_by_parent_id UUID       NOT NULL REFERENCES parents.parent(id),
    status_id             UUID        NOT NULL, -- → masters.onboarding_status(id)
    reviewed_by_user_id   UUID        REFERENCES auth."user"(id),
    submitted_at          TIMESTAMPTZ,
    reviewed_at           TIMESTAMPTZ,
    rejection_reason      TEXT,
    internal_notes        TEXT,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_oa_student_id ON parents.onboarding_application (student_id);
CREATE INDEX idx_oa_parent_id  ON parents.onboarding_application (submitted_by_parent_id);
CREATE INDEX idx_oa_status_id  ON parents.onboarding_application (status_id);

CREATE TRIGGER trg_onboarding_application_updated_at
    BEFORE UPDATE ON parents.onboarding_application
    FOR EACH ROW EXECUTE FUNCTION auth.set_updated_at();

COMMENT ON TABLE  parents.onboarding_application IS 'Student admission application. One application per student per intake.';
COMMENT ON COLUMN parents.onboarding_application.status_id           IS 'FK to masters.onboarding_status(id). Enforced at app layer.';
COMMENT ON COLUMN parents.onboarding_application.reviewed_by_user_id IS 'FK to auth.user(id). The school staff member who reviewed this application.';


-- ── Application Document ────────────────────────────────────────
-- Documents uploaded by the parent as part of an admission application.
-- One document per document_type per application (UNIQUE constraint).
CREATE TABLE parents.application_document (
    id                  UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id      UUID         NOT NULL REFERENCES parents.onboarding_application(id) ON DELETE CASCADE,
    document_type_id    UUID         NOT NULL, -- → masters.document_type(id)
    verified_by_user_id UUID         REFERENCES auth."user"(id),
    original_file_name  VARCHAR(255) NOT NULL,
    storage_url         VARCHAR(500) NOT NULL,
    mime_type           VARCHAR(100),
    file_size_bytes     BIGINT,
    is_verified         BOOLEAN      NOT NULL DEFAULT false,
    verified_at         TIMESTAMPTZ,
    uploaded_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT uq_application_document UNIQUE (application_id, document_type_id)
);

CREATE INDEX idx_ad_application_id ON parents.application_document (application_id);

COMMENT ON TABLE  parents.application_document IS 'Documents uploaded for an admission application. One per document type per application.';
COMMENT ON COLUMN parents.application_document.document_type_id    IS 'FK to masters.document_type(id). Enforced at app layer.';
COMMENT ON COLUMN parents.application_document.verified_by_user_id IS 'FK to auth.user(id). School staff who verified the document.';
COMMENT ON COLUMN parents.application_document.storage_url         IS 'Path or URL in the file storage system (S3, GCS, etc.).';
