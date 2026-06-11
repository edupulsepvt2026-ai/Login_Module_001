-- ================================================================
-- EDUPULSE TENANT DB — TEACHERS SCHEMA
-- Database : edupulse-tenant (PostgreSQL 16)
-- Schema   : teachers
--
-- Purpose:
--   Stores teacher profile and assignment data.
--   Credentials (email, phone, password, is_active, tenant_id)
--   are NOT duplicated here — they live in auth.user and are
--   fetched via the user_id FK join.
--
-- Account creation flow:
--   1. Management sends invite (auth.invite)
--   2. Teacher verifies OTP via delivery_address (auth.otp)
--   3. Teacher sets password → auth.user row created
--   4. teachers.teachers row created, linked via user_id
--
-- Tables:
--   teachers              — Core teacher profile (teacher-specific fields only)
--   teacher_class_sections — Class + section assignments per teacher
--   teacher_languages      — Languages a teacher can teach in
--   teacher_subjects       — Subjects a teacher handles
--
-- Cross-schema FKs (within this tenant DB):
--   teachers.user_id              → auth.user(id)
--   teacher_*.pincode_id          → masters.pincode(id)      [app-layer noted]
--   teacher_*.gender_id           → masters.gender(id)       [app-layer noted]
--   teacher_*.qualification_id    → masters.qualification(id)[app-layer noted]
--   teacher_class_sections.class_id   → masters.classes(id)
--   teacher_class_sections.section_id → masters.sections(id)
--   teacher_languages.language_id     → masters.language(id)
--   teacher_subjects.subject_id       → masters.subject(id)
-- ================================================================

CREATE SCHEMA IF NOT EXISTS teachers;


-- ================================================================
-- TABLES
-- ================================================================

-- ── Teachers ────────────────────────────────────────────────────
-- One row per teacher. Stores only teacher-specific profile data.
-- All auth-related fields (email, phone, is_active, tenant_id)
-- are read from auth.user via the user_id join.
CREATE TABLE teachers.teachers (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          UUID         NOT NULL UNIQUE REFERENCES auth."user"(id) ON DELETE CASCADE,
    name             VARCHAR(150) NOT NULL,
    alternate_mobile VARCHAR(15),
    address          TEXT,
    pincode_id       UUID,        -- → masters.pincode(id)
    gender_id        UUID,        -- → masters.gender(id)
    qualification_id UUID,        -- → masters.qualification(id)
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_teachers_user_id ON teachers.teachers (user_id);

CREATE TRIGGER trg_teachers_updated_at
    BEFORE UPDATE ON teachers.teachers
    FOR EACH ROW EXECUTE FUNCTION auth.set_updated_at();

COMMENT ON TABLE  teachers.teachers IS 'Teacher profile. Credentials and contact info are in auth.user — join via user_id.';
COMMENT ON COLUMN teachers.teachers.user_id          IS 'FK to auth.user(id). UNIQUE — one teacher profile per login account.';
COMMENT ON COLUMN teachers.teachers.alternate_mobile IS 'Secondary contact number. Primary mobile is in auth.user.phone.';
COMMENT ON COLUMN teachers.teachers.pincode_id       IS 'FK to masters.pincode(id). Enforced at app layer.';
COMMENT ON COLUMN teachers.teachers.gender_id        IS 'FK to masters.gender(id). Enforced at app layer.';
COMMENT ON COLUMN teachers.teachers.qualification_id IS 'FK to masters.qualification(id). Enforced at app layer.';


-- ── Teacher Class Sections ──────────────────────────────────────
-- Maps a teacher to one or more class+section combinations.
-- A teacher can be assigned to multiple classes and sections.
CREATE TABLE teachers.teacher_class_sections (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id UUID        NOT NULL REFERENCES teachers.teachers(id) ON DELETE CASCADE,
    class_id   UUID        NOT NULL,   -- → masters.classes(id)
    section_id UUID        NOT NULL,   -- → masters.sections(id)
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT uq_teacher_class_section UNIQUE (teacher_id, class_id, section_id)
);

CREATE INDEX idx_tcs_teacher_id ON teachers.teacher_class_sections (teacher_id);
CREATE INDEX idx_tcs_class_id   ON teachers.teacher_class_sections (class_id);

COMMENT ON TABLE  teachers.teacher_class_sections IS 'Class and section assignments per teacher. Cascade-deleted when teacher is removed.';
COMMENT ON COLUMN teachers.teacher_class_sections.class_id   IS 'FK to masters.classes(id). Enforced at app layer.';
COMMENT ON COLUMN teachers.teacher_class_sections.section_id IS 'FK to masters.sections(id). Enforced at app layer.';


-- ── Teacher Languages ───────────────────────────────────────────
-- Languages a teacher can teach in.
-- A teacher can know multiple languages.
CREATE TABLE teachers.teacher_languages (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id  UUID        NOT NULL REFERENCES teachers.teachers(id) ON DELETE CASCADE,
    language_id UUID        NOT NULL,   -- → masters.language(id)
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT uq_teacher_language UNIQUE (teacher_id, language_id)
);

CREATE INDEX idx_tl_teacher_id ON teachers.teacher_languages (teacher_id);

COMMENT ON TABLE  teachers.teacher_languages IS 'Languages a teacher can teach in. Cascade-deleted when teacher is removed.';
COMMENT ON COLUMN teachers.teacher_languages.language_id IS 'FK to masters.language(id). Enforced at app layer.';


-- ── Teacher Subjects ────────────────────────────────────────────
-- Subjects a teacher handles.
-- A teacher can teach multiple subjects.
CREATE TABLE teachers.teacher_subjects (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id UUID        NOT NULL REFERENCES teachers.teachers(id) ON DELETE CASCADE,
    subject_id UUID        NOT NULL,   -- → masters.subject(id)
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT uq_teacher_subject UNIQUE (teacher_id, subject_id)
);

CREATE INDEX idx_ts_teacher_id ON teachers.teacher_subjects (teacher_id);

COMMENT ON TABLE  teachers.teacher_subjects IS 'Subjects a teacher handles. Cascade-deleted when teacher is removed.';
COMMENT ON COLUMN teachers.teacher_subjects.subject_id IS 'FK to masters.subject(id). Enforced at app layer.';
