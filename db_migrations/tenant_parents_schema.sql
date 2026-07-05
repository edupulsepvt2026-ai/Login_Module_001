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
-- Account creation flow (self-service admission — student not yet enrolled):
--   1. Parent receives invite (auth.invite) or self-registers
--   2. Parent verifies OTP via delivery_address (auth.otp)
--   3. Parent sets password → auth.user row created
--   4. parents.parent row created, linked via user_id
--   5. Parent adds student details → parents.student row created
--   6. Parent submits onboarding application for student admission
--   7. Once approved, student_enrollment (+ student_subjects) rows
--      capture the student's actual class/section/subjects per year
--
-- Account creation flow (teacher-invited — student already enrolled):
--   See docs/API_V4.0_PARENT_ONBOARDING.md. A teacher invites the parent
--   of a student already placed in their class/section — parents.student
--   + student_enrollment are created directly (no onboarding_application
--   review). One invite covers exactly one student — invite_student links
--   the two so the parent's activation screen can auto-fill the student
--   it's for, without adding a parents-specific column onto the generic,
--   shared auth.invite table. Parent activation (OTP, password) is
--   otherwise identical to the self-service flow above.
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
--   student_enrollment   — Student's class/section for a given academic year
--   student_subjects     — Subjects a student takes for a given enrollment
--   invite_student       — Links a teacher-sent parent invite to the one student it's for
--
-- Cross-schema FKs (within this tenant DB):
--   parent.user_id                          → auth.user(id)
--   onboarding_application.reviewed_by_user_id → auth.user(id)
--   application_document.verified_by_user_id   → auth.user(id)
--   invite_student.invite_id                   → auth.invite(id)
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
--   student_enrollment.class_id         → masters.classes(id)
--   student_enrollment.section_id       → masters.sections(id)
--   student_subjects.subject_id         → masters.subjects(id)
--   invite_student.relationship_type_id → masters.relationship_type(id)
--
-- Note on grade_applying_id vs student_enrollment:
--   masters.grade is year-scoped (name + level + academic_year) and is
--   used ONLY at admission time — "which year's cohort is this applicant
--   targeting". student_enrollment is a separate, ongoing fact: it reuses
--   the same flat masters.classes/masters.sections tables teachers are
--   assigned against (teachers.teacher_class_sections), with academic_year
--   living on the enrollment row itself. A promotion is a new
--   student_enrollment row, not a new masters.classes row.
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
-- date_of_birth is nullable: in the teacher-invited flow
-- (docs/API_V4.0_PARENT_ONBOARDING.md § Phase 4) the teacher creates this
-- row knowing only the student's name and class/section — DOB and the
-- rest of the profile are collected from the parent later, at Phase 5
-- Step 5. The self-service admission flow still collects DOB up front;
-- it just isn't guaranteed to exist the moment the row is created.
CREATE TABLE parents.student (
    id                   UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id            UUID         NOT NULL REFERENCES management.management_table(tenant_id),
    blood_group_id       UUID,        -- → masters.blood_group(id)
    grade_applying_id    UUID,        -- → masters.grade(id)
    name                 VARCHAR(150) NOT NULL,
    date_of_birth        DATE,
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


-- ── Student Enrollment ──────────────────────────────────────────
-- One row per student per academic year — the class/section a student
-- is actually enrolled in. Distinct from student.grade_applying_id,
-- which is only the grade an admission application targets, not an
-- ongoing fact. Reuses masters.classes/masters.sections — the same
-- flat, non-year-scoped tables teachers.teacher_class_sections uses —
-- with academic_year living on this fact row instead of on the lookup
-- tables, so a promotion inserts a new row rather than a new class.
CREATE TABLE parents.student_enrollment (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id    UUID         NOT NULL REFERENCES parents.student(id) ON DELETE CASCADE,
    class_id      UUID         NOT NULL,   -- → masters.classes(id)
    section_id    UUID         NOT NULL,   -- → masters.sections(id)
    academic_year VARCHAR(20)  NOT NULL,
    roll_number   VARCHAR(20),
    status        VARCHAR(20)  NOT NULL DEFAULT 'active',
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT uq_student_enrollment_year   UNIQUE (student_id, academic_year),
    CONSTRAINT chk_student_enrollment_status CHECK (
        status = ANY (ARRAY['active', 'promoted', 'transferred', 'withdrawn'])
    )
);

CREATE INDEX idx_student_enrollment_student ON parents.student_enrollment (student_id);
CREATE INDEX idx_student_enrollment_class   ON parents.student_enrollment (class_id, section_id);
CREATE INDEX idx_student_enrollment_year    ON parents.student_enrollment (academic_year);

CREATE TRIGGER trg_student_enrollment_updated_at
    BEFORE UPDATE ON parents.student_enrollment
    FOR EACH ROW EXECUTE FUNCTION auth.set_updated_at();

COMMENT ON TABLE  parents.student_enrollment IS 'One row per student per academic year — actual class/section enrollment. Distinct from student.grade_applying_id (an admission target, not an ongoing fact).';
COMMENT ON COLUMN parents.student_enrollment.class_id      IS 'FK to masters.classes(id). Enforced at app layer. Same table teachers.teacher_class_sections uses — not year-scoped.';
COMMENT ON COLUMN parents.student_enrollment.section_id    IS 'FK to masters.sections(id). Enforced at app layer.';
COMMENT ON COLUMN parents.student_enrollment.academic_year IS 'e.g. "2026-27". Year lives here, not on masters.classes — a promotion is a new row, not a new class.';
COMMENT ON COLUMN parents.student_enrollment.status        IS 'active = currently enrolled this year. promoted/transferred/withdrawn close out a row without deleting history.';


-- ── Student Subjects ────────────────────────────────────────────
-- Subjects a student takes for a given enrollment (academic year).
-- Scoped to the enrollment row rather than student_id directly, since
-- subject choices can change on promotion (e.g. stream selection
-- entering Class 11).
CREATE TABLE parents.student_subjects (
    id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    student_enrollment_id UUID        NOT NULL REFERENCES parents.student_enrollment(id) ON DELETE CASCADE,
    subject_id            UUID        NOT NULL,   -- → masters.subjects(id)
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT uq_student_subject UNIQUE (student_enrollment_id, subject_id)
);

CREATE INDEX idx_student_subjects_enrollment ON parents.student_subjects (student_enrollment_id);

COMMENT ON TABLE  parents.student_subjects IS 'Subjects a student takes for a given enrollment year. Scoped per-enrollment, not per-student, since subject choices can change on promotion.';
COMMENT ON COLUMN parents.student_subjects.subject_id IS 'FK to masters.subjects(id). Enforced at app layer.';


-- ── Invite Student ──────────────────────────────────────────────
-- Links one auth.invite (target_role='parent') to the single student it
-- was created for — one invite always covers exactly one student (see
-- docs/API_V4.0_PARENT_ONBOARDING.md). This exists as its own table
-- rather than a column on auth.invite so the generic, shared invite
-- table (also used by chain_admin/tenant_admin/teacher invites) doesn't
-- need a parent-specific field. At Phase 5 Step 1 (invite verify), the
-- parent's activation screen looks this up to auto-fill which student
-- the account is being created for. invite_id is a real FK (not
-- app-layer-only) since auth.invite is a core entity table in this same
-- tenant DB, not a masters.* lookup table.
CREATE TABLE parents.invite_student (
    id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    invite_id            UUID        NOT NULL UNIQUE REFERENCES auth.invite(id) ON DELETE CASCADE,
    student_id           UUID        NOT NULL REFERENCES parents.student(id) ON DELETE CASCADE,
    relationship_type_id UUID        NOT NULL,  -- → masters.relationship_type(id)
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_invite_student_student ON parents.invite_student (student_id);

COMMENT ON TABLE  parents.invite_student IS 'Links an auth.invite (target_role=parent) to the one student it was created for. UNIQUE(invite_id) — one invite, one student, by design.';
COMMENT ON COLUMN parents.invite_student.relationship_type_id IS 'FK to masters.relationship_type(id). Enforced at app layer.';
