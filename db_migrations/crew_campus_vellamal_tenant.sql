--
-- PostgreSQL database dump
--

\restrict nkrJM2SC0KBOYHHeDWN2ewdeEa46prwFd1a6Vhh9iMequJkBx6cOPdaFLQk9yNW

-- Dumped from database version 16.14 (Ubuntu 16.14-0ubuntu0.24.04.1)
-- Dumped by pg_dump version 18.1 (Ubuntu 18.1-1.pgdg24.04+2)

-- Started on 2026-06-02 02:30:55 IST

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 7 (class 2615 OID 46407)
-- Name: auth; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA auth;


ALTER SCHEMA auth OWNER TO postgres;

--
-- TOC entry 8 (class 2615 OID 46408)
-- Name: management; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA management;


ALTER SCHEMA management OWNER TO postgres;

--
-- TOC entry 9 (class 2615 OID 46409)
-- Name: masters; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA masters;


ALTER SCHEMA masters OWNER TO postgres;

--
-- TOC entry 10 (class 2615 OID 46410)
-- Name: parents; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA parents;


ALTER SCHEMA parents OWNER TO postgres;

--
-- TOC entry 11 (class 2615 OID 46411)
-- Name: teachers; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA teachers;


ALTER SCHEMA teachers OWNER TO postgres;

--
-- TOC entry 2 (class 3079 OID 46412)
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- TOC entry 4029 (class 0 OID 0)
-- Dependencies: 2
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- TOC entry 300 (class 1255 OID 46449)
-- Name: set_updated_at(); Type: FUNCTION; Schema: auth; Owner: postgres
--

CREATE FUNCTION auth.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;


ALTER FUNCTION auth.set_updated_at() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 223 (class 1259 OID 46450)
-- Name: audit_event_type; Type: TABLE; Schema: auth; Owner: postgres
--

CREATE TABLE auth.audit_event_type (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(100) NOT NULL,
    category character varying(50) NOT NULL,
    description text
);


ALTER TABLE auth.audit_event_type OWNER TO postgres;

--
-- TOC entry 224 (class 1259 OID 46456)
-- Name: audit_log; Type: TABLE; Schema: auth; Owner: postgres
--

CREATE TABLE auth.audit_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    tenant_id uuid NOT NULL,
    event_type_id uuid NOT NULL,
    ip_address inet,
    user_agent text,
    metadata jsonb,
    is_suspicious boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE auth.audit_log OWNER TO postgres;

--
-- TOC entry 4030 (class 0 OID 0)
-- Dependencies: 224
-- Name: TABLE audit_log; Type: COMMENT; Schema: auth; Owner: postgres
--

COMMENT ON TABLE auth.audit_log IS 'Append-only security log. Never UPDATE or DELETE rows.';


--
-- TOC entry 4031 (class 0 OID 0)
-- Dependencies: 224
-- Name: COLUMN audit_log.is_suspicious; Type: COMMENT; Schema: auth; Owner: postgres
--

COMMENT ON COLUMN auth.audit_log.is_suspicious IS 'Set by app layer for anomalies (new country, unusual hour, etc.).';


--
-- TOC entry 225 (class 1259 OID 46464)
-- Name: invite; Type: TABLE; Schema: auth; Owner: postgres
--

CREATE TABLE auth.invite (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    invited_by_user_id uuid,                   -- set when a user (teacher) sends the invite
    invited_by_management_user_id uuid,        -- set when a management user sends the invite
    target_role_id uuid NOT NULL,
    status_id uuid NOT NULL,
    email character varying(255),
    phone character varying(20),
    invite_token_hash character varying(255) NOT NULL,
    resend_count integer DEFAULT 0 NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    accepted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_invite_contact CHECK (((email IS NOT NULL) OR (phone IS NOT NULL))),
    CONSTRAINT invite_resend_count_check CHECK ((resend_count >= 0)),
    CONSTRAINT chk_invite_sender CHECK (
        (invited_by_user_id IS NOT NULL) <> (invited_by_management_user_id IS NOT NULL)
    )
);


ALTER TABLE auth.invite OWNER TO postgres;

--
-- TOC entry 4032 (class 0 OID 0)
-- Dependencies: 225
-- Name: TABLE invite; Type: COMMENT; Schema: auth; Owner: postgres
--

COMMENT ON TABLE auth.invite IS 'Drives the full onboarding chain: management → teacher → parent.';


--
-- TOC entry 4033 (class 0 OID 0)
-- Dependencies: 225
-- Name: COLUMN invite.invite_token_hash; Type: COMMENT; Schema: auth; Owner: postgres
--

COMMENT ON COLUMN auth.invite.invite_token_hash IS 'Hash of a one-time signed token. Raw token is never stored.';


--
-- TOC entry 226 (class 1259 OID 46474)
-- Name: invite_status; Type: TABLE; Schema: auth; Owner: postgres
--

CREATE TABLE auth.invite_status (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(50) NOT NULL,
    description text
);


ALTER TABLE auth.invite_status OWNER TO postgres;

--
-- TOC entry 262 (class 1259 OID 47118)
-- Name: management_user; Type: TABLE; Schema: auth; Owner: postgres
--

CREATE TABLE auth.management_user (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    chain_id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    email character varying(255),
    phone character varying(20),
    username character varying(100),
    password_hash character varying(255),
    is_active boolean DEFAULT true NOT NULL,
    is_email_verified boolean DEFAULT false NOT NULL,
    is_phone_verified boolean DEFAULT false NOT NULL,
    failed_login_attempts integer DEFAULT 0 NOT NULL,
    locked_until timestamp with time zone,
    last_login_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_mgmt_contact CHECK (((email IS NOT NULL) OR (phone IS NOT NULL))),
    CONSTRAINT management_user_failed_login_attempts_check CHECK ((failed_login_attempts >= 0))
);


ALTER TABLE auth.management_user OWNER TO postgres;

--
-- TOC entry 4034 (class 0 OID 0)
-- Dependencies: 262
-- Name: TABLE management_user; Type: COMMENT; Schema: auth; Owner: postgres
--

COMMENT ON TABLE auth.management_user IS 'Standalone credentials table for management users. Not linked to auth.user. Teachers and parents use auth.user instead.';


--
-- TOC entry 4035 (class 0 OID 0)
-- Dependencies: 262
-- Name: COLUMN management_user.chain_id; Type: COMMENT; Schema: auth; Owner: postgres
--

COMMENT ON COLUMN auth.management_user.chain_id IS 'The school chain this manager administers. Access spans all branches (tenant_ids) under this chain.';


--
-- TOC entry 4036 (class 0 OID 0)
-- Dependencies: 262
-- Name: COLUMN management_user.tenant_id; Type: COMMENT; Schema: auth; Owner: postgres
--

COMMENT ON COLUMN auth.management_user.tenant_id IS 'Primary branch tenant for this manager. Stored as FK reference for the branch they were onboarded under.';


--
-- TOC entry 4037 (class 0 OID 0)
-- Dependencies: 262
-- Name: COLUMN management_user.locked_until; Type: COMMENT; Schema: auth; Owner: postgres
--

COMMENT ON COLUMN auth.management_user.locked_until IS 'NULL = not locked. Set by app layer after N failed login attempts.';


--
-- TOC entry 227 (class 1259 OID 46480)
-- Name: otp; Type: TABLE; Schema: auth; Owner: postgres
--

CREATE TABLE auth.otp (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    otp_type_id uuid NOT NULL,
    code_hash character varying(255) NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    is_used boolean DEFAULT false NOT NULL,
    delivery_address character varying(255) NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT otp_attempts_check CHECK ((attempts >= 0))
);


ALTER TABLE auth.otp OWNER TO postgres;

--
-- TOC entry 4038 (class 0 OID 0)
-- Dependencies: 227
-- Name: TABLE otp; Type: COMMENT; Schema: auth; Owner: postgres
--

COMMENT ON TABLE auth.otp IS 'One row per OTP issued. Never reuse; always insert a fresh row.';


--
-- TOC entry 228 (class 1259 OID 46490)
-- Name: otp_type; Type: TABLE; Schema: auth; Owner: postgres
--

CREATE TABLE auth.otp_type (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(50) NOT NULL,
    ttl_seconds integer DEFAULT 300 NOT NULL,
    max_attempts integer DEFAULT 3 NOT NULL,
    delivery_channel character varying(10) NOT NULL,
    CONSTRAINT otp_type_delivery_channel_check CHECK (((delivery_channel)::text = ANY (ARRAY[('email'::character varying)::text, ('sms'::character varying)::text, ('both'::character varying)::text]))),
    CONSTRAINT otp_type_max_attempts_check CHECK ((max_attempts > 0)),
    CONSTRAINT otp_type_ttl_seconds_check CHECK ((ttl_seconds > 0))
);


ALTER TABLE auth.otp_type OWNER TO postgres;

--
-- TOC entry 4039 (class 0 OID 0)
-- Dependencies: 228
-- Name: COLUMN otp_type.ttl_seconds; Type: COMMENT; Schema: auth; Owner: postgres
--

COMMENT ON COLUMN auth.otp_type.ttl_seconds IS 'Seconds before the OTP expires.';


--
-- TOC entry 229 (class 1259 OID 46499)
-- Name: password_history; Type: TABLE; Schema: auth; Owner: postgres
--

CREATE TABLE auth.password_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    password_hash character varying(255) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE auth.password_history OWNER TO postgres;

--
-- TOC entry 4040 (class 0 OID 0)
-- Dependencies: 229
-- Name: TABLE password_history; Type: COMMENT; Schema: auth; Owner: postgres
--

COMMENT ON TABLE auth.password_history IS 'Last N hashes per user. App layer checks before accepting a new password to prevent reuse.';


--
-- TOC entry 230 (class 1259 OID 46504)
-- Name: permission; Type: TABLE; Schema: auth; Owner: postgres
--

CREATE TABLE auth.permission (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    resource character varying(100) NOT NULL,
    action character varying(50) NOT NULL,
    description text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE auth.permission OWNER TO postgres;

--
-- TOC entry 4041 (class 0 OID 0)
-- Dependencies: 230
-- Name: TABLE permission; Type: COMMENT; Schema: auth; Owner: postgres
--

COMMENT ON TABLE auth.permission IS 'Granular resource-action pairs used in RBAC.';


--
-- TOC entry 231 (class 1259 OID 46511)
-- Name: role; Type: TABLE; Schema: auth; Owner: postgres
--

CREATE TABLE auth.role (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(50) NOT NULL,
    description text,
    is_system_role boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE auth.role OWNER TO postgres;

--
-- TOC entry 4042 (class 0 OID 0)
-- Dependencies: 231
-- Name: TABLE role; Type: COMMENT; Schema: auth; Owner: postgres
--

COMMENT ON TABLE auth.role IS 'System roles: super_admin, management, teacher, parent.';


--
-- TOC entry 4043 (class 0 OID 0)
-- Dependencies: 231
-- Name: COLUMN role.is_system_role; Type: COMMENT; Schema: auth; Owner: postgres
--

COMMENT ON COLUMN auth.role.is_system_role IS 'TRUE rows cannot be deleted by application code.';


--
-- TOC entry 232 (class 1259 OID 46519)
-- Name: role_permission; Type: TABLE; Schema: auth; Owner: postgres
--

CREATE TABLE auth.role_permission (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    role_id uuid NOT NULL,
    permission_id uuid NOT NULL,
    granted_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE auth.role_permission OWNER TO postgres;

--
-- TOC entry 233 (class 1259 OID 46524)
-- Name: session; Type: TABLE; Schema: auth; Owner: postgres
--

CREATE TABLE auth.session (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    access_token_hash character varying(255) NOT NULL,
    refresh_token_hash character varying(255) NOT NULL,
    ip_address inet,
    user_agent text,
    device_fingerprint character varying(255),
    expires_at timestamp with time zone NOT NULL,
    revoked_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE auth.session OWNER TO postgres;

--
-- TOC entry 4044 (class 0 OID 0)
-- Dependencies: 233
-- Name: COLUMN session.revoked_at; Type: COMMENT; Schema: auth; Owner: postgres
--

COMMENT ON COLUMN auth.session.revoked_at IS 'Non-null = session invalidated (logout / forced sign-out).';


--
-- TOC entry 234 (class 1259 OID 46531)
-- Name: user; Type: TABLE; Schema: auth; Owner: postgres
--

CREATE TABLE auth."user" (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    role_id uuid NOT NULL,
    email character varying(255),
    phone character varying(20),
    password_hash character varying(255),
    is_active boolean DEFAULT true NOT NULL,
    is_email_verified boolean DEFAULT false NOT NULL,
    is_phone_verified boolean DEFAULT false NOT NULL,
    onboarding_channel character varying(20),
    failed_login_attempts integer DEFAULT 0 NOT NULL,
    locked_until timestamp with time zone,
    last_login_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_user_contact CHECK (((email IS NOT NULL) OR (phone IS NOT NULL))),
    CONSTRAINT user_failed_login_attempts_check CHECK ((failed_login_attempts >= 0)),
    CONSTRAINT user_onboarding_channel_check CHECK (((onboarding_channel)::text = ANY (ARRAY[('manual'::character varying)::text, ('bulk_upload'::character varying)::text, ('invite'::character varying)::text])))
);


ALTER TABLE auth."user" OWNER TO postgres;

--
-- TOC entry 4045 (class 0 OID 0)
-- Dependencies: 234
-- Name: TABLE "user"; Type: COMMENT; Schema: auth; Owner: postgres
--

COMMENT ON TABLE auth."user" IS 'One row per platform user regardless of role.';


--
-- TOC entry 4046 (class 0 OID 0)
-- Dependencies: 234
-- Name: COLUMN "user".tenant_id; Type: COMMENT; Schema: auth; Owner: postgres
--

COMMENT ON COLUMN auth."user".tenant_id IS 'Scopes the user to a specific school/management account.';


--
-- TOC entry 4047 (class 0 OID 0)
-- Dependencies: 234
-- Name: COLUMN "user".locked_until; Type: COMMENT; Schema: auth; Owner: postgres
--

COMMENT ON COLUMN auth."user".locked_until IS 'NULL means not locked. Set by app layer after N failed attempts.';


--
-- TOC entry 263 (class 1259 OID 47151)
-- Name: chain; Type: TABLE; Schema: management; Owner: postgres
--

CREATE TABLE management.chain (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(100) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE management.chain OWNER TO postgres;

--
-- TOC entry 4048 (class 0 OID 0)
-- Dependencies: 263
-- Name: TABLE chain; Type: COMMENT; Schema: management; Owner: postgres
--

COMMENT ON TABLE management.chain IS 'Master record for each school chain (brand). One row per school group. Branches are in management_table.';


--
-- TOC entry 235 (class 1259 OID 46546)
-- Name: management_table; Type: TABLE; Schema: management; Owner: postgres
--

CREATE TABLE management.management_table (
    tenant_id uuid DEFAULT gen_random_uuid() NOT NULL,
    chain_id uuid NOT NULL,
    branch_id uuid NOT NULL,
    chain_name character varying(100) NOT NULL,
    branch_name character varying(100) NOT NULL,
    branch_city character varying(100),
    branch_state character varying(100),
    branch_address text,
    branch_phone character varying(20),
    branch_email character varying(150),
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE management.management_table OWNER TO postgres;

--
-- TOC entry 236 (class 1259 OID 46555)
-- Name: blood_group; Type: TABLE; Schema: masters; Owner: postgres
--

CREATE TABLE masters.blood_group (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(10) NOT NULL
);


ALTER TABLE masters.blood_group OWNER TO postgres;

--
-- TOC entry 237 (class 1259 OID 46559)
-- Name: classes; Type: TABLE; Schema: masters; Owner: postgres
--

CREATE TABLE masters.classes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(50) NOT NULL
);


ALTER TABLE masters.classes OWNER TO postgres;

--
-- TOC entry 238 (class 1259 OID 46563)
-- Name: contact_type; Type: TABLE; Schema: masters; Owner: postgres
--

CREATE TABLE masters.contact_type (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(100) NOT NULL
);


ALTER TABLE masters.contact_type OWNER TO postgres;

--
-- TOC entry 239 (class 1259 OID 46567)
-- Name: document_type; Type: TABLE; Schema: masters; Owner: postgres
--

CREATE TABLE masters.document_type (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(100) NOT NULL,
    is_required boolean DEFAULT false NOT NULL,
    accepted_formats character varying(255)
);


ALTER TABLE masters.document_type OWNER TO postgres;

--
-- TOC entry 240 (class 1259 OID 46572)
-- Name: genders; Type: TABLE; Schema: masters; Owner: postgres
--

CREATE TABLE masters.genders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(50) NOT NULL
);


ALTER TABLE masters.genders OWNER TO postgres;

--
-- TOC entry 241 (class 1259 OID 46576)
-- Name: grade; Type: TABLE; Schema: masters; Owner: postgres
--

CREATE TABLE masters.grade (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(50) NOT NULL,
    level integer NOT NULL,
    academic_year character varying(20) NOT NULL
);


ALTER TABLE masters.grade OWNER TO postgres;

--
-- TOC entry 242 (class 1259 OID 46580)
-- Name: languages; Type: TABLE; Schema: masters; Owner: postgres
--

CREATE TABLE masters.languages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(100) NOT NULL
);


ALTER TABLE masters.languages OWNER TO postgres;

--
-- TOC entry 243 (class 1259 OID 46584)
-- Name: onboarding_status; Type: TABLE; Schema: masters; Owner: postgres
--

CREATE TABLE masters.onboarding_status (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(100) NOT NULL,
    description character varying(255),
    sort_order integer DEFAULT 0 NOT NULL
);


ALTER TABLE masters.onboarding_status OWNER TO postgres;

--
-- TOC entry 244 (class 1259 OID 46589)
-- Name: pincodes; Type: TABLE; Schema: masters; Owner: postgres
--

CREATE TABLE masters.pincodes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    code character varying(10) NOT NULL,
    city character varying(100) NOT NULL,
    state character varying(100) NOT NULL
);


ALTER TABLE masters.pincodes OWNER TO postgres;

--
-- TOC entry 245 (class 1259 OID 46593)
-- Name: qualifications; Type: TABLE; Schema: masters; Owner: postgres
--

CREATE TABLE masters.qualifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(100) NOT NULL
);


ALTER TABLE masters.qualifications OWNER TO postgres;

--
-- TOC entry 246 (class 1259 OID 46597)
-- Name: relationship_type; Type: TABLE; Schema: masters; Owner: postgres
--

CREATE TABLE masters.relationship_type (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(100) NOT NULL,
    description character varying(255)
);


ALTER TABLE masters.relationship_type OWNER TO postgres;

--
-- TOC entry 247 (class 1259 OID 46601)
-- Name: sections; Type: TABLE; Schema: masters; Owner: postgres
--

CREATE TABLE masters.sections (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(50) NOT NULL
);


ALTER TABLE masters.sections OWNER TO postgres;

--
-- TOC entry 248 (class 1259 OID 46605)
-- Name: subjects; Type: TABLE; Schema: masters; Owner: postgres
--

CREATE TABLE masters.subjects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying(100) NOT NULL
);


ALTER TABLE masters.subjects OWNER TO postgres;

--
-- TOC entry 249 (class 1259 OID 46609)
-- Name: address; Type: TABLE; Schema: parents; Owner: postgres
--

CREATE TABLE parents.address (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    line1 character varying(255) NOT NULL,
    line2 character varying(255),
    city character varying(100) NOT NULL,
    state character varying(100) NOT NULL,
    postal_code character varying(20) NOT NULL,
    country character varying(100) DEFAULT 'India'::character varying NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE parents.address OWNER TO postgres;

--
-- TOC entry 250 (class 1259 OID 46617)
-- Name: application_document; Type: TABLE; Schema: parents; Owner: postgres
--

CREATE TABLE parents.application_document (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    application_id uuid NOT NULL,
    document_type_id uuid NOT NULL,
    verified_by_user_id uuid,
    original_file_name character varying(255) NOT NULL,
    storage_url character varying(500) NOT NULL,
    mime_type character varying(100),
    file_size_bytes bigint,
    is_verified boolean DEFAULT false NOT NULL,
    verified_at timestamp without time zone,
    uploaded_at timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE parents.application_document OWNER TO postgres;

--
-- TOC entry 251 (class 1259 OID 46625)
-- Name: emergency_contact; Type: TABLE; Schema: parents; Owner: postgres
--

CREATE TABLE parents.emergency_contact (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    student_id uuid NOT NULL,
    full_name character varying(150) NOT NULL,
    relationship character varying(100),
    phone character varying(20) NOT NULL,
    email character varying(150),
    priority_order integer DEFAULT 1 NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE parents.emergency_contact OWNER TO postgres;

--
-- TOC entry 252 (class 1259 OID 46631)
-- Name: onboarding_application; Type: TABLE; Schema: parents; Owner: postgres
--

CREATE TABLE parents.onboarding_application (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    student_id uuid NOT NULL,
    submitted_by_parent_id uuid NOT NULL,
    status_id uuid NOT NULL,
    reviewed_by_user_id uuid,
    submitted_at timestamp without time zone,
    reviewed_at timestamp without time zone,
    rejection_reason text,
    internal_notes text,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE parents.onboarding_application OWNER TO postgres;

--
-- TOC entry 253 (class 1259 OID 46639)
-- Name: parent; Type: TABLE; Schema: parents; Owner: postgres
--

CREATE TABLE parents.parent (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    first_name character varying(100) NOT NULL,
    last_name character varying(100) NOT NULL,
    date_of_birth date,
    gender character varying(20),
    nationality character varying(100),
    occupation character varying(150),
    employer_name character varying(150),
    profile_photo_url character varying(500),
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE parents.parent OWNER TO postgres;

--
-- TOC entry 254 (class 1259 OID 46647)
-- Name: parent_address; Type: TABLE; Schema: parents; Owner: postgres
--

CREATE TABLE parents.parent_address (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    parent_id uuid NOT NULL,
    address_id uuid NOT NULL,
    label character varying(50),
    is_primary boolean DEFAULT false NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE parents.parent_address OWNER TO postgres;

--
-- TOC entry 255 (class 1259 OID 46653)
-- Name: parent_contact; Type: TABLE; Schema: parents; Owner: postgres
--

CREATE TABLE parents.parent_contact (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    parent_id uuid NOT NULL,
    contact_type_id uuid NOT NULL,
    value character varying(150) NOT NULL,
    is_primary boolean DEFAULT false NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE parents.parent_contact OWNER TO postgres;

--
-- TOC entry 256 (class 1259 OID 46659)
-- Name: parent_student; Type: TABLE; Schema: parents; Owner: postgres
--

CREATE TABLE parents.parent_student (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    parent_id uuid NOT NULL,
    student_id uuid NOT NULL,
    relationship_type_id uuid NOT NULL,
    is_primary_guardian boolean DEFAULT false NOT NULL,
    has_custody boolean DEFAULT true NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE parents.parent_student OWNER TO postgres;

--
-- TOC entry 257 (class 1259 OID 46666)
-- Name: student; Type: TABLE; Schema: parents; Owner: postgres
--

CREATE TABLE parents.student (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    blood_group_id uuid,
    grade_applying_id uuid,
    first_name character varying(100) NOT NULL,
    last_name character varying(100) NOT NULL,
    date_of_birth date NOT NULL,
    gender character varying(20),
    nationality character varying(100),
    previous_school_name character varying(255),
    photo_url character varying(500),
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE parents.student OWNER TO postgres;

--
-- TOC entry 258 (class 1259 OID 46674)
-- Name: teacher_class_sections; Type: TABLE; Schema: teachers; Owner: postgres
--

CREATE TABLE teachers.teacher_class_sections (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    teacher_id uuid NOT NULL,
    class_id uuid NOT NULL,
    section_id uuid NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE teachers.teacher_class_sections OWNER TO postgres;

--
-- TOC entry 259 (class 1259 OID 46679)
-- Name: teacher_languages; Type: TABLE; Schema: teachers; Owner: postgres
--

CREATE TABLE teachers.teacher_languages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    teacher_id uuid NOT NULL,
    language_id uuid NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE teachers.teacher_languages OWNER TO postgres;

--
-- TOC entry 260 (class 1259 OID 46684)
-- Name: teacher_subjects; Type: TABLE; Schema: teachers; Owner: postgres
--

CREATE TABLE teachers.teacher_subjects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    teacher_id uuid NOT NULL,
    subject_id uuid NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE teachers.teacher_subjects OWNER TO postgres;

--
-- TOC entry 261 (class 1259 OID 46689)
-- Name: teachers; Type: TABLE; Schema: teachers; Owner: postgres
--

CREATE TABLE teachers.teachers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    name character varying(150) NOT NULL,
    mobile character varying(15) NOT NULL,
    alternate_mobile character varying(15),
    email character varying(150),
    address text,
    pincode_id uuid NOT NULL,
    gender_id uuid NOT NULL,
    qualification_id uuid NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE teachers.teachers OWNER TO postgres;

--
-- TOC entry 3983 (class 0 OID 46450)
-- Dependencies: 223
-- Data for Name: audit_event_type; Type: TABLE DATA; Schema: auth; Owner: postgres
--

INSERT INTO auth.audit_event_type (id, name, category, description) VALUES ('f5dd8ab7-f60e-49a7-a4dd-78f318e2c247', 'login_success', 'auth', 'Credentials accepted, session opened');
INSERT INTO auth.audit_event_type (id, name, category, description) VALUES ('d3dd3300-d562-487f-b7dd-15162f6f6e0a', 'login_failure', 'auth', 'Credentials rejected');
INSERT INTO auth.audit_event_type (id, name, category, description) VALUES ('6792caa9-7f6f-4b56-a69a-c4a3657ac57c', 'account_locked', 'auth', 'Account locked after repeated failures');
INSERT INTO auth.audit_event_type (id, name, category, description) VALUES ('8584a4e6-6443-49ab-a3a2-d02d305586e5', 'account_unlocked', 'auth', 'Lock period expired or admin reset');
INSERT INTO auth.audit_event_type (id, name, category, description) VALUES ('8876981d-2ff0-4921-bfee-60acc9ac0afc', 'logout', 'auth', 'User-initiated sign-out');
INSERT INTO auth.audit_event_type (id, name, category, description) VALUES ('77aa2bc6-5f53-41cd-b2cd-9a758b8757f7', 'otp_requested', 'otp', 'New OTP code generated and dispatched');
INSERT INTO auth.audit_event_type (id, name, category, description) VALUES ('09fef301-8a3b-4404-bd86-8222ff136dec', 'otp_verified', 'otp', 'OTP code accepted');
INSERT INTO auth.audit_event_type (id, name, category, description) VALUES ('81a08996-2b4c-43cc-be36-d243fe0b6646', 'otp_failed', 'otp', 'Wrong OTP code entered');
INSERT INTO auth.audit_event_type (id, name, category, description) VALUES ('fbe9a145-c11e-4682-8a91-bef1e0260702', 'otp_expired', 'otp', 'OTP used after TTL');
INSERT INTO auth.audit_event_type (id, name, category, description) VALUES ('8fb2b061-8623-46a5-bdd3-6aeaf6d0cbd6', 'password_created', 'credential', 'First password set after invite');
INSERT INTO auth.audit_event_type (id, name, category, description) VALUES ('0de047c2-4598-4d04-8906-7eee9da78f48', 'password_changed', 'credential', 'Password updated by user');
INSERT INTO auth.audit_event_type (id, name, category, description) VALUES ('8cfd7cb9-5e01-4465-89e4-1f3cdcc7cfc7', 'password_reset_request', 'credential', 'Password reset initiated');
INSERT INTO auth.audit_event_type (id, name, category, description) VALUES ('1e4d30e1-4b4a-4467-8e1e-ac9c7fcaedb6', 'invite_sent', 'invite', 'Invite link dispatched to new user');
INSERT INTO auth.audit_event_type (id, name, category, description) VALUES ('f349a101-ccfe-4397-9eb0-95452c852e20', 'invite_accepted', 'invite', 'New user completed registration');
INSERT INTO auth.audit_event_type (id, name, category, description) VALUES ('00f1b8d1-ca0c-4e3a-b79e-75f4ebb887ef', 'invite_resent', 'invite', 'Invite link resent on request');
INSERT INTO auth.audit_event_type (id, name, category, description) VALUES ('c71bf0ec-dfbb-42a5-a3a5-f46784681c96', 'invite_revoked', 'invite', 'Invite cancelled before acceptance');
INSERT INTO auth.audit_event_type (id, name, category, description) VALUES ('1d9e2001-59be-46fe-a65c-d8ece6380ed5', 'session_revoked', 'session', 'Session forcefully terminated');
INSERT INTO auth.audit_event_type (id, name, category, description) VALUES ('abc61e99-c1b1-4ab1-b0d1-48b7b76f9ecc', 'suspicious_activity', 'security', 'Anomaly flagged by application layer');


--
-- TOC entry 3984 (class 0 OID 46456)
-- Dependencies: 224
-- Data for Name: audit_log; Type: TABLE DATA; Schema: auth; Owner: postgres
--



--
-- TOC entry 3985 (class 0 OID 46464)
-- Dependencies: 225
-- Data for Name: invite; Type: TABLE DATA; Schema: auth; Owner: postgres
--



--
-- TOC entry 3986 (class 0 OID 46474)
-- Dependencies: 226
-- Data for Name: invite_status; Type: TABLE DATA; Schema: auth; Owner: postgres
--

INSERT INTO auth.invite_status (id, name, description) VALUES ('d001e3b7-8dff-4183-b051-5a7a2c49e8d6', 'pending', 'Dispatched, awaiting user acceptance');
INSERT INTO auth.invite_status (id, name, description) VALUES ('785a3a08-f669-4795-92b6-284b7c4c29c3', 'accepted', 'User completed OTP verification and set a password');
INSERT INTO auth.invite_status (id, name, description) VALUES ('4bada971-075c-4ec7-8adc-4c8bec212cbc', 'expired', 'Invite TTL elapsed without acceptance');
INSERT INTO auth.invite_status (id, name, description) VALUES ('3ca35087-3b7e-4b49-a419-8daf99dd17be', 'revoked', 'Manually cancelled by the sender');


--
-- TOC entry 4022 (class 0 OID 47118)
-- Dependencies: 262
-- Data for Name: management_user; Type: TABLE DATA; Schema: auth; Owner: postgres
--



--
-- TOC entry 3987 (class 0 OID 46480)
-- Dependencies: 227
-- Data for Name: otp; Type: TABLE DATA; Schema: auth; Owner: postgres
--



--
-- TOC entry 3988 (class 0 OID 46490)
-- Dependencies: 228
-- Data for Name: otp_type; Type: TABLE DATA; Schema: auth; Owner: postgres
--

INSERT INTO auth.otp_type (id, name, ttl_seconds, max_attempts, delivery_channel) VALUES ('3a7c2da5-6f32-472f-8bda-5a56412e85da', 'onboarding_email', 600, 3, 'email');
INSERT INTO auth.otp_type (id, name, ttl_seconds, max_attempts, delivery_channel) VALUES ('50c42715-ad9c-4b78-b9b7-fc293feab628', 'onboarding_sms', 300, 3, 'sms');
INSERT INTO auth.otp_type (id, name, ttl_seconds, max_attempts, delivery_channel) VALUES ('6e56e117-7453-4f58-a58e-4979590adddf', 'password_reset', 300, 3, 'both');
INSERT INTO auth.otp_type (id, name, ttl_seconds, max_attempts, delivery_channel) VALUES ('b582bf5d-019b-4ed7-8dd8-221bf2e54838', 'two_factor', 120, 3, 'both');


--
-- TOC entry 3989 (class 0 OID 46499)
-- Dependencies: 229
-- Data for Name: password_history; Type: TABLE DATA; Schema: auth; Owner: postgres
--



--
-- TOC entry 3990 (class 0 OID 46504)
-- Dependencies: 230
-- Data for Name: permission; Type: TABLE DATA; Schema: auth; Owner: postgres
--

INSERT INTO auth.permission (id, resource, action, description, created_at) VALUES ('a1567225-cef2-4148-9e2c-63a2e4667ceb', 'teacher', 'create', 'Onboard a new teacher', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.permission (id, resource, action, description, created_at) VALUES ('9ba181fb-f1a5-4fb2-911a-47c8f20f6356', 'teacher', 'read', 'View teacher profile', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.permission (id, resource, action, description, created_at) VALUES ('5f4229e0-7062-45c4-81ce-6ac5a2983a0a', 'teacher', 'update', 'Edit teacher details', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.permission (id, resource, action, description, created_at) VALUES ('fc42bcb5-475d-4018-810b-445708b8eaf4', 'teacher', 'delete', 'Remove a teacher', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.permission (id, resource, action, description, created_at) VALUES ('e4591624-8b2e-40a1-8784-b822706796cf', 'student', 'create', 'Enrol a new student', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.permission (id, resource, action, description, created_at) VALUES ('c686d0a4-06e6-4d75-b800-3197bf8c4054', 'student', 'read', 'View student profile', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.permission (id, resource, action, description, created_at) VALUES ('649ea151-5c3a-4604-ab24-c45165973c0d', 'student', 'update', 'Edit student data', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.permission (id, resource, action, description, created_at) VALUES ('68fb2d36-8949-4d25-a465-c002e5b6b034', 'student', 'delete', 'Remove a student record', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.permission (id, resource, action, description, created_at) VALUES ('5b4c118b-fd7e-4cc0-8c7e-c4d2c7894e11', 'parent', 'create', 'Onboard a parent / guardian', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.permission (id, resource, action, description, created_at) VALUES ('587732cb-a019-43ab-8d5b-509b50635fb3', 'parent', 'read', 'View parent profile', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.permission (id, resource, action, description, created_at) VALUES ('507a5e43-85c4-4793-9fd9-4a23e0e84613', 'parent', 'update', 'Edit parent data', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.permission (id, resource, action, description, created_at) VALUES ('53066835-35e8-4cdf-bc40-49a1ee60adf1', 'parent', 'delete', 'Remove a parent record', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.permission (id, resource, action, description, created_at) VALUES ('7483f4d6-d954-43c8-b754-e9ef8b62853f', 'homework', 'create', 'Assign homework', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.permission (id, resource, action, description, created_at) VALUES ('f5326f31-ba41-4c6d-aad1-1c64bc52171d', 'homework', 'read', 'View homework', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.permission (id, resource, action, description, created_at) VALUES ('1c26e585-3bcf-4e6e-b5c3-df27ae70ec0f', 'homework', 'update', 'Edit homework', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.permission (id, resource, action, description, created_at) VALUES ('3b0dbabb-0981-4722-ab08-cdf397489a1b', 'homework', 'delete', 'Delete homework', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.permission (id, resource, action, description, created_at) VALUES ('34d811d8-6d48-406b-9a8a-4e01d0380ea0', 'report', 'read', 'View reports', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.permission (id, resource, action, description, created_at) VALUES ('a85bebc9-7275-4b1e-a6a7-04d171a9043d', 'report', 'export', 'Export reports', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.permission (id, resource, action, description, created_at) VALUES ('3cba48aa-8fbd-4906-92f0-b40be3d5966c', 'invite', 'send', 'Send onboarding invites', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.permission (id, resource, action, description, created_at) VALUES ('9b0d794a-a5bd-44e9-98f3-8857fbfa187c', 'invite', 'revoke', 'Cancel an existing invite', '2026-05-30 11:54:15.450941+05:30');


--
-- TOC entry 3991 (class 0 OID 46511)
-- Dependencies: 231
-- Data for Name: role; Type: TABLE DATA; Schema: auth; Owner: postgres
--

INSERT INTO auth.role (id, name, description, is_system_role, created_at) VALUES ('ea7ea511-90b7-4f25-8161-e2005e257b87', 'super_admin', 'Platform-level administrator — spans all tenants', true, '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role (id, name, description, is_system_role, created_at) VALUES ('048047ca-5a63-4452-8490-bb6929af92b3', 'management', 'School management / principal account', true, '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role (id, name, description, is_system_role, created_at) VALUES ('6c0c43c0-5cdd-4ce3-b048-c0fdefac10a8', 'teacher', 'Teaching and administrative staff', true, '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role (id, name, description, is_system_role, created_at) VALUES ('201adc98-c25e-4ed2-b5b8-129433bdfad8', 'parent', 'Parent or legal guardian', true, '2026-05-30 11:54:15.450941+05:30');


--
-- TOC entry 3992 (class 0 OID 46519)
-- Dependencies: 232
-- Data for Name: role_permission; Type: TABLE DATA; Schema: auth; Owner: postgres
--

INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('77eb9378-3207-414a-b039-ded145f7d360', '048047ca-5a63-4452-8490-bb6929af92b3', 'a1567225-cef2-4148-9e2c-63a2e4667ceb', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('f43bf0b8-488c-41f4-a876-1ab0234ea053', '048047ca-5a63-4452-8490-bb6929af92b3', '9ba181fb-f1a5-4fb2-911a-47c8f20f6356', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('ff334e25-2f89-4ae6-b52e-d3a9da79ec89', '048047ca-5a63-4452-8490-bb6929af92b3', '5f4229e0-7062-45c4-81ce-6ac5a2983a0a', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('a030cf56-d42a-4f17-94e5-dc566fa43731', '048047ca-5a63-4452-8490-bb6929af92b3', 'fc42bcb5-475d-4018-810b-445708b8eaf4', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('9b3428e6-3fe2-48b4-b82b-768bc906e18e', '048047ca-5a63-4452-8490-bb6929af92b3', 'e4591624-8b2e-40a1-8784-b822706796cf', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('799188fe-7b6f-46cf-a61a-57daa4976b5f', '048047ca-5a63-4452-8490-bb6929af92b3', 'c686d0a4-06e6-4d75-b800-3197bf8c4054', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('3de81b02-7c81-4418-b09f-b42a8e9ffe98', '048047ca-5a63-4452-8490-bb6929af92b3', '649ea151-5c3a-4604-ab24-c45165973c0d', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('bf9b2b11-b522-488e-af58-c73b18f8fa99', '048047ca-5a63-4452-8490-bb6929af92b3', '68fb2d36-8949-4d25-a465-c002e5b6b034', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('a853e2bf-42aa-4a3c-970f-dcaea3114c7f', '048047ca-5a63-4452-8490-bb6929af92b3', '5b4c118b-fd7e-4cc0-8c7e-c4d2c7894e11', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('462261c9-8407-4d6b-9ab7-f97481b8402a', '048047ca-5a63-4452-8490-bb6929af92b3', '587732cb-a019-43ab-8d5b-509b50635fb3', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('c24af26d-c97f-4be0-a46f-f91d9944759c', '048047ca-5a63-4452-8490-bb6929af92b3', '507a5e43-85c4-4793-9fd9-4a23e0e84613', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('d43c4492-64d1-4891-b65d-df4e2fe79189', '048047ca-5a63-4452-8490-bb6929af92b3', '53066835-35e8-4cdf-bc40-49a1ee60adf1', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('97fffb64-aecd-4555-8d42-3014ae4ff419', '048047ca-5a63-4452-8490-bb6929af92b3', '7483f4d6-d954-43c8-b754-e9ef8b62853f', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('01bd78f8-a7e1-4b5f-ab7e-1ded6a0c2a06', '048047ca-5a63-4452-8490-bb6929af92b3', 'f5326f31-ba41-4c6d-aad1-1c64bc52171d', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('1695e9e1-86d5-47bc-b856-2bc4de50260f', '048047ca-5a63-4452-8490-bb6929af92b3', '1c26e585-3bcf-4e6e-b5c3-df27ae70ec0f', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('613b800b-4061-41f0-b399-826082c3a9c3', '048047ca-5a63-4452-8490-bb6929af92b3', '3b0dbabb-0981-4722-ab08-cdf397489a1b', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('ac179c14-a817-42f6-99fa-5aa879832ff9', '048047ca-5a63-4452-8490-bb6929af92b3', '34d811d8-6d48-406b-9a8a-4e01d0380ea0', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('62b8e0c4-c9a2-4511-9cc5-88a630c12488', '048047ca-5a63-4452-8490-bb6929af92b3', 'a85bebc9-7275-4b1e-a6a7-04d171a9043d', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('45eb16e2-331f-4d49-a25a-1d3930fc50ba', '048047ca-5a63-4452-8490-bb6929af92b3', '3cba48aa-8fbd-4906-92f0-b40be3d5966c', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('e56d3324-aabb-446f-843c-7fe903d1b237', '048047ca-5a63-4452-8490-bb6929af92b3', '9b0d794a-a5bd-44e9-98f3-8857fbfa187c', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('2ef84d95-f252-42e7-923d-535e2f26e941', '6c0c43c0-5cdd-4ce3-b048-c0fdefac10a8', 'e4591624-8b2e-40a1-8784-b822706796cf', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('c75abe36-8e6d-4b03-90de-f0e6a60d4cc9', '6c0c43c0-5cdd-4ce3-b048-c0fdefac10a8', 'c686d0a4-06e6-4d75-b800-3197bf8c4054', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('3f9187a4-ab10-49be-abf8-336fa928aca3', '6c0c43c0-5cdd-4ce3-b048-c0fdefac10a8', '649ea151-5c3a-4604-ab24-c45165973c0d', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('cee036d0-272f-45b1-966b-6485138e0fb3', '6c0c43c0-5cdd-4ce3-b048-c0fdefac10a8', '68fb2d36-8949-4d25-a465-c002e5b6b034', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('c3d096d4-bf4e-4dbc-9ec9-807da1fc94d6', '6c0c43c0-5cdd-4ce3-b048-c0fdefac10a8', '5b4c118b-fd7e-4cc0-8c7e-c4d2c7894e11', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('0a6e76a3-71c2-4c96-ba79-f1a14c6e75af', '6c0c43c0-5cdd-4ce3-b048-c0fdefac10a8', '587732cb-a019-43ab-8d5b-509b50635fb3', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('a72ca144-b544-4fd6-85d6-e8ffd4d5ceaf', '6c0c43c0-5cdd-4ce3-b048-c0fdefac10a8', '507a5e43-85c4-4793-9fd9-4a23e0e84613', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('c14108af-192f-4bb2-bd29-9bc4629beb5f', '6c0c43c0-5cdd-4ce3-b048-c0fdefac10a8', '53066835-35e8-4cdf-bc40-49a1ee60adf1', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('5383952a-a393-4f60-8315-5ab406c92e65', '6c0c43c0-5cdd-4ce3-b048-c0fdefac10a8', '7483f4d6-d954-43c8-b754-e9ef8b62853f', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('30ad9d24-3b22-4dfe-8476-3fdbee118ef6', '6c0c43c0-5cdd-4ce3-b048-c0fdefac10a8', 'f5326f31-ba41-4c6d-aad1-1c64bc52171d', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('8ebfd61f-88b8-4b4c-adac-33a3ed03a6a6', '6c0c43c0-5cdd-4ce3-b048-c0fdefac10a8', '1c26e585-3bcf-4e6e-b5c3-df27ae70ec0f', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('3efccb6d-6446-4b43-8d46-9b551eed78c6', '6c0c43c0-5cdd-4ce3-b048-c0fdefac10a8', '3b0dbabb-0981-4722-ab08-cdf397489a1b', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('d827e04e-9c8d-456f-ba45-ea4c33002cae', '6c0c43c0-5cdd-4ce3-b048-c0fdefac10a8', '34d811d8-6d48-406b-9a8a-4e01d0380ea0', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('61464e68-4b10-475c-a20f-2269793eda92', '6c0c43c0-5cdd-4ce3-b048-c0fdefac10a8', '3cba48aa-8fbd-4906-92f0-b40be3d5966c', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('07598635-da86-47b5-8ba9-d12e665cfe5f', '201adc98-c25e-4ed2-b5b8-129433bdfad8', 'f5326f31-ba41-4c6d-aad1-1c64bc52171d', '2026-05-30 11:54:15.450941+05:30');
INSERT INTO auth.role_permission (id, role_id, permission_id, granted_at) VALUES ('4758bded-a06e-4da0-b958-e9190274aa8b', '201adc98-c25e-4ed2-b5b8-129433bdfad8', '34d811d8-6d48-406b-9a8a-4e01d0380ea0', '2026-05-30 11:54:15.450941+05:30');


--
-- TOC entry 3993 (class 0 OID 46524)
-- Dependencies: 233
-- Data for Name: session; Type: TABLE DATA; Schema: auth; Owner: postgres
--



--
-- TOC entry 3994 (class 0 OID 46531)
-- Dependencies: 234
-- Data for Name: user; Type: TABLE DATA; Schema: auth; Owner: postgres
--



--
-- TOC entry 4023 (class 0 OID 47151)
-- Dependencies: 263
-- Data for Name: chain; Type: TABLE DATA; Schema: management; Owner: postgres
--



--
-- TOC entry 3995 (class 0 OID 46546)
-- Dependencies: 235
-- Data for Name: management_table; Type: TABLE DATA; Schema: management; Owner: postgres
--



--
-- TOC entry 3996 (class 0 OID 46555)
-- Dependencies: 236
-- Data for Name: blood_group; Type: TABLE DATA; Schema: masters; Owner: postgres
--

INSERT INTO masters.blood_group (id, name) VALUES ('a2454657-0983-4533-a9c5-6ebc6cc6a43a', 'A+');
INSERT INTO masters.blood_group (id, name) VALUES ('347ef384-4713-471b-8096-403f1e306d88', 'A-');
INSERT INTO masters.blood_group (id, name) VALUES ('f3df353c-aebc-43f3-8448-ae239b7e3ac6', 'B+');
INSERT INTO masters.blood_group (id, name) VALUES ('081e0ae6-8482-477c-ab35-19ba4ec033c9', 'B-');
INSERT INTO masters.blood_group (id, name) VALUES ('53cb3f4c-0793-4551-93db-cd66b5d04732', 'O+');
INSERT INTO masters.blood_group (id, name) VALUES ('39722156-8161-4542-a9f8-d0a1ad629c84', 'O-');
INSERT INTO masters.blood_group (id, name) VALUES ('a3200a29-8236-47ef-bc3d-fbf3b4f7e710', 'AB+');
INSERT INTO masters.blood_group (id, name) VALUES ('474fe46f-bd52-4f50-a4d0-3c125a667903', 'AB-');


--
-- TOC entry 3997 (class 0 OID 46559)
-- Dependencies: 237
-- Data for Name: classes; Type: TABLE DATA; Schema: masters; Owner: postgres
--

INSERT INTO masters.classes (id, name) VALUES ('e9b4101b-7acc-455c-bb57-2197b07eb650', 'Nursery');
INSERT INTO masters.classes (id, name) VALUES ('eaaa3a73-8fc3-4a8e-950a-100c5eb9027b', 'LKG');
INSERT INTO masters.classes (id, name) VALUES ('a025a5c5-ad14-44fd-8173-f3a6916c52ba', 'UKG');
INSERT INTO masters.classes (id, name) VALUES ('ffe3d087-5bcb-484e-afd5-c06d634c9cdd', 'Class 1');
INSERT INTO masters.classes (id, name) VALUES ('97a6b885-a0a7-47c9-b0cb-9616dca07e3a', 'Class 2');
INSERT INTO masters.classes (id, name) VALUES ('4342dc98-21a7-4a14-8e9c-17915b0ae14f', 'Class 3');
INSERT INTO masters.classes (id, name) VALUES ('1dcb4e2f-d59e-4dab-b6ac-837499e16a8d', 'Class 4');
INSERT INTO masters.classes (id, name) VALUES ('4c4d4a6b-e7d6-4668-b959-1252ac219e5d', 'Class 5');
INSERT INTO masters.classes (id, name) VALUES ('aa600da9-787c-4683-9789-3b358df5c532', 'Class 6');
INSERT INTO masters.classes (id, name) VALUES ('47fca2e3-e9d4-4100-af0f-e99603d68834', 'Class 7');
INSERT INTO masters.classes (id, name) VALUES ('3e8afde6-54b3-4648-88af-1aacbe9b5c2d', 'Class 8');
INSERT INTO masters.classes (id, name) VALUES ('14a1f016-e242-4725-ac24-ae487a1a7199', 'Class 9');
INSERT INTO masters.classes (id, name) VALUES ('3a4eeae3-f112-4bc2-9b51-08ae662272a3', 'Class 10');
INSERT INTO masters.classes (id, name) VALUES ('60800c1d-7fc7-4fe4-86ab-9e84a5540458', 'Class 11');
INSERT INTO masters.classes (id, name) VALUES ('3115e4b4-ac3f-4ac3-972c-36713bb89b93', 'Class 12');


--
-- TOC entry 3998 (class 0 OID 46563)
-- Dependencies: 238
-- Data for Name: contact_type; Type: TABLE DATA; Schema: masters; Owner: postgres
--

INSERT INTO masters.contact_type (id, name) VALUES ('04208474-e0dd-45ed-a3a5-363b511e3a75', 'Mobile');
INSERT INTO masters.contact_type (id, name) VALUES ('9a169194-cc6a-45f5-ba34-7caebe43ce36', 'WhatsApp');
INSERT INTO masters.contact_type (id, name) VALUES ('12b15c03-3542-42e5-b5d1-8f66283ba6cf', 'Email');
INSERT INTO masters.contact_type (id, name) VALUES ('7e9fc4c0-f0db-4c8e-b313-7caccab06b87', 'Alternate Mobile');
INSERT INTO masters.contact_type (id, name) VALUES ('3fd57c9b-2c36-4aa1-af22-fca9a4c6ad3b', 'Work Phone');
INSERT INTO masters.contact_type (id, name) VALUES ('39b0018a-0546-4f50-a0da-de8415a359a7', 'Home Phone');


--
-- TOC entry 3999 (class 0 OID 46567)
-- Dependencies: 239
-- Data for Name: document_type; Type: TABLE DATA; Schema: masters; Owner: postgres
--

INSERT INTO masters.document_type (id, name, is_required, accepted_formats) VALUES ('66a8f32d-0acf-434b-8b04-163c05c73616', 'Aadhar Card', true, 'jpg,jpeg,png,pdf');
INSERT INTO masters.document_type (id, name, is_required, accepted_formats) VALUES ('79f2d292-6d22-4c96-ac53-650bcfc0a677', 'Birth Certificate', true, 'jpg,jpeg,png,pdf');
INSERT INTO masters.document_type (id, name, is_required, accepted_formats) VALUES ('57327fd1-64be-4051-a666-cd48d328bf43', 'Transfer Certificate', true, 'jpg,jpeg,png,pdf');
INSERT INTO masters.document_type (id, name, is_required, accepted_formats) VALUES ('1a3d4813-edb1-4ad0-aa1d-73dd2ceca29a', 'School Leaving Certificate', false, 'jpg,jpeg,png,pdf');
INSERT INTO masters.document_type (id, name, is_required, accepted_formats) VALUES ('5696f246-fe7d-4815-980d-8c6827a2ca58', 'Caste Certificate', false, 'jpg,jpeg,png,pdf');
INSERT INTO masters.document_type (id, name, is_required, accepted_formats) VALUES ('a5e4db65-7864-4979-a7e0-1a446e1fa114', 'Income Certificate', false, 'jpg,jpeg,png,pdf');
INSERT INTO masters.document_type (id, name, is_required, accepted_formats) VALUES ('8d3448c7-3f3a-4659-8271-20afd4a11ef1', 'Passport', false, 'jpg,jpeg,png,pdf');
INSERT INTO masters.document_type (id, name, is_required, accepted_formats) VALUES ('f415e65f-5dba-456c-ac13-f788e76aa6bb', 'Vaccination Certificate', false, 'jpg,jpeg,png,pdf');
INSERT INTO masters.document_type (id, name, is_required, accepted_formats) VALUES ('cd1d8203-8874-41ee-a0ff-49826a1d45eb', 'Medical Certificate', false, 'jpg,jpeg,png,pdf');
INSERT INTO masters.document_type (id, name, is_required, accepted_formats) VALUES ('cae5fbfa-0da1-4bb0-94b9-6519474c80fc', 'Conduct Certificate', false, 'jpg,jpeg,png,pdf');
INSERT INTO masters.document_type (id, name, is_required, accepted_formats) VALUES ('a209dd1f-b3ea-49d2-a668-1c0b2bec29e1', 'Progress Report (Previous Year)', false, 'jpg,jpeg,png,pdf');
INSERT INTO masters.document_type (id, name, is_required, accepted_formats) VALUES ('0d29fb1a-c7a1-4974-8efa-d608b4ed01f9', 'Nativity Certificate', false, 'jpg,jpeg,png,pdf');
INSERT INTO masters.document_type (id, name, is_required, accepted_formats) VALUES ('4762ac26-3096-421d-80d4-fc41a2bbf937', 'Photo', true, 'jpg,jpeg,png');


--
-- TOC entry 4000 (class 0 OID 46572)
-- Dependencies: 240
-- Data for Name: genders; Type: TABLE DATA; Schema: masters; Owner: postgres
--

INSERT INTO masters.genders (id, name) VALUES ('9d1b819b-2058-4540-85af-cc288ebf9568', 'Male');
INSERT INTO masters.genders (id, name) VALUES ('9ee137c4-d307-4230-bffe-cd8e8cdb61c9', 'Female');
INSERT INTO masters.genders (id, name) VALUES ('e65d7a4b-d75c-4436-8f1d-7711edf467a4', 'Other');
INSERT INTO masters.genders (id, name) VALUES ('d50e3284-8182-497d-9ea3-1977f848f9b9', 'Prefer not to say');


--
-- TOC entry 4001 (class 0 OID 46576)
-- Dependencies: 241
-- Data for Name: grade; Type: TABLE DATA; Schema: masters; Owner: postgres
--

INSERT INTO masters.grade (id, name, level, academic_year) VALUES ('62d6193b-7113-46a4-89cd-91242860fe14', 'Nursery', 0, '2025-26');
INSERT INTO masters.grade (id, name, level, academic_year) VALUES ('e65236a2-ea91-45e6-8164-f417bb1d758e', 'LKG', 1, '2025-26');
INSERT INTO masters.grade (id, name, level, academic_year) VALUES ('35b6792c-3a32-48e5-9b6e-c1f6ee5d6772', 'UKG', 2, '2025-26');
INSERT INTO masters.grade (id, name, level, academic_year) VALUES ('64438b71-ca0e-4e2f-8e73-bf383dabfb4a', 'Grade 1', 3, '2025-26');
INSERT INTO masters.grade (id, name, level, academic_year) VALUES ('974d1845-6dd4-4e39-9c3d-39bf92c1f863', 'Grade 2', 4, '2025-26');
INSERT INTO masters.grade (id, name, level, academic_year) VALUES ('5f4028e8-8b85-4175-9189-2f41082249ab', 'Grade 3', 5, '2025-26');
INSERT INTO masters.grade (id, name, level, academic_year) VALUES ('f18d1712-a6c6-4311-9a02-a68708757a32', 'Grade 4', 6, '2025-26');
INSERT INTO masters.grade (id, name, level, academic_year) VALUES ('d5163683-9a94-411a-9e44-da07d306650a', 'Grade 5', 7, '2025-26');
INSERT INTO masters.grade (id, name, level, academic_year) VALUES ('94bc0895-9acd-4abe-be05-9d955ed46234', 'Grade 6', 8, '2025-26');
INSERT INTO masters.grade (id, name, level, academic_year) VALUES ('d020d6a9-a152-40e2-832e-fa1a6f75bfdd', 'Grade 7', 9, '2025-26');
INSERT INTO masters.grade (id, name, level, academic_year) VALUES ('03e109e1-963d-4e35-a1af-a6442f0e1f88', 'Grade 8', 10, '2025-26');
INSERT INTO masters.grade (id, name, level, academic_year) VALUES ('5d09a643-ce91-494d-b6ae-b66395ce1bcf', 'Grade 9', 11, '2025-26');
INSERT INTO masters.grade (id, name, level, academic_year) VALUES ('2d30b873-459b-49fb-a421-ec060ee13588', 'Grade 10', 12, '2025-26');
INSERT INTO masters.grade (id, name, level, academic_year) VALUES ('22200d99-c3b1-45cb-9797-62127c555b59', 'Grade 11', 13, '2025-26');
INSERT INTO masters.grade (id, name, level, academic_year) VALUES ('f40b9f9a-9986-4244-94d5-f01aaaed1300', 'Grade 12', 14, '2025-26');


--
-- TOC entry 4002 (class 0 OID 46580)
-- Dependencies: 242
-- Data for Name: languages; Type: TABLE DATA; Schema: masters; Owner: postgres
--

INSERT INTO masters.languages (id, name) VALUES ('57c8303b-cc37-4289-b936-c3eb7afcdbac', 'Tamil');
INSERT INTO masters.languages (id, name) VALUES ('4251197f-b05c-4297-a0ac-408d6e5af61d', 'English');
INSERT INTO masters.languages (id, name) VALUES ('dcaf9052-03b1-4ce8-b2ea-e4bb032741d2', 'Hindi');
INSERT INTO masters.languages (id, name) VALUES ('2190f725-ca21-4b02-a900-b2fca3e9f912', 'Telugu');
INSERT INTO masters.languages (id, name) VALUES ('2a820317-73e5-48a3-92c8-3b746a13c6c2', 'Malayalam');
INSERT INTO masters.languages (id, name) VALUES ('3e50e4c8-cf77-4a14-b90b-399382cb1ffc', 'Kannada');
INSERT INTO masters.languages (id, name) VALUES ('d2a48dff-3ce9-4974-925e-8dc8d6130c56', 'Urdu');
INSERT INTO masters.languages (id, name) VALUES ('dbcb5809-f6a0-4db5-8a74-0406dca7030c', 'Sanskrit');
INSERT INTO masters.languages (id, name) VALUES ('88a29770-c7f3-46fa-8cce-1b3d5ba8e782', 'French');
INSERT INTO masters.languages (id, name) VALUES ('94070f01-e64b-4f3f-9952-7b6206d0a99e', 'German');
INSERT INTO masters.languages (id, name) VALUES ('e55a9d11-c180-47fb-b3e3-31ed1a2bb2cb', 'Bengali');
INSERT INTO masters.languages (id, name) VALUES ('224e022f-1282-4278-acde-954078ff3282', 'Marathi');
INSERT INTO masters.languages (id, name) VALUES ('921b7a25-c2d6-4b0b-8850-efbc72a272da', 'Gujarati');


--
-- TOC entry 4003 (class 0 OID 46584)
-- Dependencies: 243
-- Data for Name: onboarding_status; Type: TABLE DATA; Schema: masters; Owner: postgres
--

INSERT INTO masters.onboarding_status (id, name, description, sort_order) VALUES ('a3f82285-3390-40ad-928a-6d68e19049ef', 'Pending', 'Application not yet submitted', 1);
INSERT INTO masters.onboarding_status (id, name, description, sort_order) VALUES ('f9aa6b4a-8add-43a4-8b8a-dd9444f8a7e1', 'Document Submitted', 'Documents uploaded, awaiting review', 2);
INSERT INTO masters.onboarding_status (id, name, description, sort_order) VALUES ('99a06639-6118-48f9-af40-e67438e12ecb', 'Under Review', 'EduPulse team is reviewing documents', 3);
INSERT INTO masters.onboarding_status (id, name, description, sort_order) VALUES ('491f3f1e-a8f9-4947-8225-b976fc0b8c1d', 'Approved', 'Application approved, fee pending', 4);
INSERT INTO masters.onboarding_status (id, name, description, sort_order) VALUES ('b35e16b1-a6df-48b0-8f51-7f2a191e189b', 'Fee Paid', 'Admission fee paid', 5);
INSERT INTO masters.onboarding_status (id, name, description, sort_order) VALUES ('72841441-e7f6-4896-a2f9-e33c94eeb2d1', 'Enrolled', 'Student officially enrolled', 6);
INSERT INTO masters.onboarding_status (id, name, description, sort_order) VALUES ('27088755-ac71-427b-9bed-69623d8e2e29', 'Waitlisted', 'Placed on waitlist pending seat availability', 7);
INSERT INTO masters.onboarding_status (id, name, description, sort_order) VALUES ('fb101780-d05d-4839-9298-c5c42bca1dcb', 'Rejected', 'Application rejected by school', 8);
INSERT INTO masters.onboarding_status (id, name, description, sort_order) VALUES ('60423ebb-e1cf-4143-9495-b7af1df39dae', 'Withdrawn', 'Application withdrawn by parent', 9);


--
-- TOC entry 4004 (class 0 OID 46589)
-- Dependencies: 244
-- Data for Name: pincodes; Type: TABLE DATA; Schema: masters; Owner: postgres
--

INSERT INTO masters.pincodes (id, code, city, state) VALUES ('163f94c2-32ea-4115-88c7-eac453fdc232', '600001', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fde5e5be-06b1-4283-8767-903032c8ff12', '600002', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c349b90b-212a-410d-ba7d-f9b077807227', '600003', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2e76c686-43fc-4a86-bfe7-2499fc3deb34', '600004', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('37957271-871f-4ab5-ba75-6e7edd514a4f', '600005', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1c05d3f2-487f-4fa5-b857-db7be4f59b25', '600006', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('080f68f8-0939-4d01-bbba-50422b7082f5', '600007', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a5605a44-8f0b-4b7b-a88d-d7c7bc8a5c7d', '600008', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0eb22a83-0d96-40d1-af0a-31cb27d90a95', '600009', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('056fe3b5-e8da-4d52-89b3-8629ff90453e', '600010', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a45c6ace-7a78-47ac-b321-8a1880692c52', '600011', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('11509410-21b6-4a5d-8412-fc712c001fdb', '600012', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('73c6e41e-d46d-4cd6-b546-1a25007ea46a', '600013', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('40c81de1-66ed-4870-8f1d-82852f44c74e', '600014', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('804702ff-597a-434b-bd7a-4123d0e17b8a', '600015', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('999699ae-ac59-461e-868c-ec53ecfaf4c5', '600016', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1f0dd1dd-a0e4-4e93-bcb0-937d714779d5', '600017', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d8a1b319-5149-4a18-b5b8-a811da9c5f63', '600018', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('75d62932-60bd-4294-9056-2bd2f357a60b', '600019', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3decf7ba-761f-4e18-bab9-ce71aee473f4', '600020', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('11c7acd3-0e34-4960-a8de-c6c9bbc64ca3', '600025', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e241111a-9f33-4141-a096-a4ecedd70566', '600026', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ee127f93-5c8e-4396-bcd5-2204f6cb84ba', '600028', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('abc3246c-05ae-495f-9d49-fb4d62e06eb6', '600029', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('aa81be38-6fbe-4783-bfb6-6447bba23bfa', '600030', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e54028bf-a666-4631-9c1e-8814261a1d7c', '600031', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b8570baa-debf-47a0-b34a-f4503305ad3a', '600033', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7a2f39fd-7dcd-4999-974d-ffd187606d10', '600034', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('08f334eb-126e-42e0-830d-242517632577', '600035', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('044c9dff-a943-4fda-8de6-8845090ef1a9', '600037', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2de9e969-9a56-4ef3-8a78-6fc405fd41bd', '600038', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2a22f4d2-1915-447c-b4a5-c38e57c2c4db', '600040', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('10869251-a1ba-442b-8e2a-7601d10c7f87', '600041', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bb0ec235-d36d-418a-928f-4cad5c3a6a06', '600042', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ae35f370-5553-4789-9c4f-21fd93107feb', '600043', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f9ee5f51-cf0f-4e08-b361-5b21cfeafc15', '600044', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('43228ab9-69a3-4037-9208-b0c6736e4038', '600045', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a2a8ff56-ee02-4679-af77-110b30ead16a', '600049', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('304ed2fc-a81c-4fc1-96cd-d5cf37cc8a7a', '600050', 'Avadi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6f15dbd7-d477-4b1b-849b-0516ef010215', '600053', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d205aeee-aac9-4931-a220-ba301825989f', '600054', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a42241be-530c-499b-a202-6db9b79c0ae1', '600056', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('72c41ad6-6353-4ecb-97c6-c5c9ef50144d', '600058', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('49efaa75-1383-4f72-8e80-2f8635645cf2', '600064', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('36025d03-da8c-4fe2-beeb-7c35289ef8fe', '600073', 'Chromepet', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b3832d4c-ae04-4c0a-b472-9272e1f166bc', '600074', 'Tambaram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5f95ea01-7646-4bdf-b9ed-34172e008350', '600077', 'Tambaram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d66a72ed-a032-4013-a1e8-4f9114f0b68c', '600083', 'Pallavaram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('dfcf4cf5-620c-4994-a17e-5a59c158effc', '600086', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('633d44eb-6297-4cbb-a94c-1ebd98fd6418', '600088', 'Pammal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d25f6da5-c432-4c7d-b654-59d10b37b3b5', '600089', 'Selaiyur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ff77769e-3ef2-4f51-b374-94114f6be4c5', '600091', 'Medavakkam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3350a5ea-12d0-4830-b343-e87852176d6b', '600096', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('90ba9a0f-be91-470b-b785-db5f8d795549', '600097', 'Kundrathur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b8058612-b9a5-4fdb-9ba3-51b2ef15249c', '600100', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2fdc752e-ee46-41b9-a6fe-f28817a5ac3a', '600101', 'Poonamallee', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1bfb5b56-398f-4410-aeb4-6abd8ae42188', '600107', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f3f49584-2f48-41a0-9c38-c193456905df', '600110', 'Red Hills', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('67542bba-729c-47c6-b4b1-be15caa536ee', '600115', 'Tiruvottiyur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1041eb44-c4dd-44ba-b817-55e304aafbec', '600119', 'Ennore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('20f5ee4d-f255-4cef-bb0a-e9e03671d67f', '602001', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('023d298c-77c4-4ebb-9e95-57e1cb2261f8', '602002', 'Ponneri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fd931d58-6a5e-4a84-9705-b33a57aaac17', '602003', 'Tiruttani', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e8d6904f-cf44-4155-bf23-949fae315f37', '602021', 'Gummidipoondi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8b5979cf-7d70-446a-acff-00be4adad8a9', '602022', 'Thiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('abebc0e9-299b-4ecd-9586-d59d69fcf2bf', '602023', 'Thiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7a875748-7280-4c7a-9d5f-1aef57638678', '602024', 'Sholavaram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('87e83cf1-b461-483e-ab71-8dcf768e200d', '602025', 'Redhills', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c566ccc5-ad73-451d-a1ab-dd691e5169bf', '602026', 'Uthukottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9750c066-59b9-4c09-8a5f-6b2e66bf55d6', '631001', 'Kancheepuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c60889c4-a7b8-44db-bda1-734185d4c166', '631002', 'Kancheepuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4eb3c787-2959-4084-8c9e-37d8c5fb0f5a', '631003', 'Kancheepuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('29a9c3e3-d322-4431-82c0-7140f0175cfc', '631004', 'Kancheepuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3eb7a68b-9bcc-478d-a1f5-2779ee1f5a0c', '631005', 'Sriperumbudur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ca079dee-1f9b-449b-bd84-e9a4d61bd19a', '631006', 'Uthiramerur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('71f799f8-4384-46b1-933e-cdd298348335', '631501', 'Chengalpattu', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c0ee3155-c66c-46bb-ab1f-f1ca4e69ef5b', '631502', 'Madurantakam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d32139a2-15f5-4c5c-8af1-8792557bc4d3', '631601', 'Tambaram East', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('674663cb-b15a-42e6-981e-7984cc077064', '631701', 'Singaperumalkoil', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0e621dff-eaa1-43a3-b79f-f7ef62d7eb3b', '631702', 'Walajabad', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('35ab8eb6-21e0-42e3-9af0-6ffdb589a395', '603001', 'Chengalpattu', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('da1bb418-feb2-427b-89f1-4d8a2f64d882', '603002', 'Chengalpattu', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0f3cc110-1a64-48d5-b172-10f04022791b', '603003', 'Mahabalipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('56355cf4-ccb2-481e-8c76-44b5e0049b43', '603101', 'Uthiramerur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('17c09010-2d68-46ac-add0-500bef0a5ff4', '603201', 'Sriperumbudur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('77e2abd0-4a59-4162-b270-f13d595f2809', '603203', 'Madurantakam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('26d725f5-d7ce-434b-b9f4-054ccb110eb1', '603301', 'Vandalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('43fa087f-fe1b-4504-a898-dc099fe9b552', '632001', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0be366ce-5a2d-42bb-9f92-793bf88b3232', '632002', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e0cffe05-d722-4986-8ef1-d163341ebcb8', '632003', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c1f2aaad-2c38-4a8d-a7aa-dfa5f6b6119c', '632004', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a6ed5b91-65d0-40a6-afd5-138d23cdfe99', '632005', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('39532aba-ca13-4061-a066-23ef7de2a763', '632006', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c934a23d-62a3-48b9-af38-704b761a2e5b', '632007', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('03683154-5362-4787-be7f-5adc1a729652', '632008', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('290ebb67-4bf2-4e41-ba5a-0bc17a9099b3', '632009', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a7e4ba8c-d241-4b66-8b28-01a61e424a4b', '632010', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ee93e53f-908e-4b08-ba43-9e8757d5f747', '632011', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5be486ef-6b71-422f-9227-00915219b02d', '632012', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b5f2faba-f698-41a8-a3d6-f6797dff755d', '632013', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e0eacd64-b1dc-4032-a720-755622c6fcb3', '632014', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cac63976-41b2-42b9-b62c-84c3b4e607ed', '632055', 'Arakkonam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7418d78c-35c3-45ed-9aed-0a0ad4049728', '632101', 'Ambur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9b47d9ce-328b-41f9-8480-9ee771920777', '632201', 'Ranipet', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9f016811-702e-4050-b0be-eba6336fa9fd', '632401', 'Tirupattur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c2671b7f-8199-4f6d-af87-cc30e7e42767', '632401', 'Arani', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f0af6176-e9cf-4af1-a43f-88373c6737cd', '632501', 'Arcot', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6d83fcda-f218-49b3-84e4-793e65917894', '632502', 'Walajapet', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('996ea999-dc3d-40c9-aa0d-d3d17113c21d', '632513', 'Ranipet', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d0011bb6-72ce-45ff-9d99-faa74f7bd4a8', '635601', 'Tirupattur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9380ba52-4566-4032-9eaa-bd81755fd600', '635651', 'Ambur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ce98ab92-4b5c-4dab-86fd-8abad0b50cff', '635652', 'Vaniyambadi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e535a915-2b5a-4be9-9628-a1f640f02542', '635653', 'Jolarpet', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('017d0f81-304d-466b-9b44-97707a27e189', '635701', 'Vaniyambadi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5487d3e0-79b2-43ec-bb85-d88e71b70583', '635001', 'Dharmapuri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bf00ea1e-11bb-4b25-a029-694dcfb7e57e', '635002', 'Dharmapuri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e0eedfea-aae6-4089-9dc1-d9e669c2c36f', '635101', 'Harur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('76a6f288-84af-4274-946a-e14566c259d4', '635201', 'Pennagaram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2f4515e6-7b08-4312-8b7f-eb38a5d914c8', '635301', 'Uthangarai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('def94728-4677-4b4e-ade2-e475cead5aec', '635401', 'Palacode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('03f94d7e-b24c-42e5-bc87-46902eb77c82', '635108', 'Hosur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fef38829-71ab-4849-8ed5-39835ba014a7', '635109', 'Hosur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('02a4bf26-feaf-4405-87b7-9cd30c249d47', '635110', 'Hosur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('298dd964-78bf-40a3-9d59-48a2db7065d7', '635115', 'Hosur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9319ea94-6785-444a-abd7-6dde7ff915f9', '635120', 'Hosur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('157dbe77-4ec0-44b0-a9a3-dfb4ba474aac', '635126', 'Hosur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('075a6e2c-4eec-480e-94eb-9521cc681768', '635130', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('33fe2de0-e65c-4901-9be0-77af155fca7a', '635301', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f61321be-5c60-4cde-94ea-12f4f2c64b26', '635302', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6f90dfde-24fb-41cd-a530-6be49e949c72', '636001', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d7deee11-d8c4-4176-a6ef-8d5efcc00cfa', '636002', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('da20ce47-a3ea-4dc1-9257-4fe3a4fa03b6', '636003', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5dd526bb-ac2a-4bb8-aa8f-d194b49d57d3', '636004', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('38b92194-0973-4c8a-96b6-66adfe031240', '636005', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3a6da10f-a762-4886-a1d8-374f1718f4d8', '636006', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8db6dade-d119-41ba-b86a-2ef618c39406', '636007', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c65a9037-f3d5-4848-94d8-b1cbd40892ee', '636008', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b2c6d2be-ea74-4928-9bed-0e397507e88f', '636009', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('375ddf3b-d0e5-4792-b0cb-9a20ff788c9d', '636010', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a5dd6b44-b44e-4eff-8796-a2a0b4ecfe72', '636011', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7763ae48-f5fd-4aa9-a1f5-c39d12580651', '636012', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5dd635e9-a06b-480d-9524-18b713a461ce', '636013', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c05d7ded-c371-4f85-a763-9742b940f271', '636014', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3011d41a-89f3-4c14-a7e1-d2ddbf5bd8e7', '636015', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1c8739b2-3ad8-470b-b804-d8d239274a04', '636016', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e662d0a0-8167-434c-9551-725c63415d67', '636030', 'Vazhapadi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('458f75ee-e673-49b3-a385-730a99cdb512', '636101', 'Omalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('70b59237-1ba9-4561-ac0d-1873b7579537', '636201', 'Mettur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9552c569-1cfc-440b-8e04-584f137caed2', '636301', 'Attur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9aecb941-8246-4aaf-9b60-853d9753da8a', '636401', 'Sankari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c3d723f9-c181-4ce4-8144-0d6ada6ed3c8', '636501', 'Yercaud', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d4869531-742c-4066-8ad8-4a72c3a61580', '637001', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('38fec399-55b7-4205-8e84-8325085c69ef', '637002', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a5013436-ded2-4849-9c04-86c6593b5e9f', '637003', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1d679d6c-fd34-498e-838d-737ca83677c7', '637013', 'Tiruchengode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('29301dc1-9ba1-45fa-92d3-3c0e1f2d0e91', '637014', 'Tiruchengode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('db2dca9a-d2a4-43ab-ab59-4db6257cf867', '637101', 'Rasipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1c326169-33d4-4a1c-987d-1b1f6e771e2a', '637201', 'Paramathi Velur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d26e3ff0-f41c-4a85-9c80-0f84d76fdc14', '638001', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('25562710-2501-48fd-93ef-bd5efc34944d', '638002', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e261f46c-5eab-491b-a923-1db6b8f29e05', '638003', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e204a3ad-a2ca-42d7-b25f-599e71532107', '638004', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('61443f9f-f63c-4369-9321-213a925c16ef', '638005', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('12c53e55-9992-40cc-ac3a-ec948497b67d', '638006', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('849dc89c-38f3-4f0a-b78f-c7ceac363fe4', '638007', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4a978dca-9915-4aad-8660-a13a6eeb620e', '638008', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('18cdef2b-c7ec-4af6-8dfc-f2ba8553dbd4', '638009', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6d710e37-cc75-44f3-a42e-8a4ab4f3f7de', '638010', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ad77767e-5753-4bb3-87e8-e47cb1c53922', '638011', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a8eed515-3fcc-41e2-9460-9c980aeca8c9', '638012', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c52e66b5-4a5a-4c56-bc97-c96e82eb3c33', '638051', 'Bhavani', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f6c8e173-8a80-4f5f-b8b5-18ba8f84f70d', '638052', 'Bhavani', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fffc1f93-77ca-497e-a882-fc23ea608f3c', '638101', 'Perundurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('17ee0a4d-426a-421c-92e4-b95994fb77d1', '638112', 'Gobichettipalayam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ecf3a48f-d3cf-4cea-a293-aee97181e81e', '638301', 'Sathyamangalam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('55d9f6d9-803c-4b0b-b3cf-fd25087b3b16', '638401', 'Anthiyur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('28c4a1f3-bc2d-41f4-b710-c44e516a4f7f', '638458', 'Kodumudi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('67d47eda-8b54-493c-b0ab-d7177f16ddda', '641001', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cec4196c-fa7a-4302-bd4f-201a306a1b23', '641002', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('558f0736-2b9d-40e3-ad3c-6dddde8931a7', '641003', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1407c649-60e6-4d36-a00d-ff0ec04b7310', '641004', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f039d57b-85e3-4b3a-8e65-27a6be7a8b6a', '641005', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('70f1ebc0-2a20-48af-bf23-1aa1f10e9d63', '641006', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('14694671-e18f-4007-ace7-b3caa8fc4691', '641007', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3563b561-608a-4bab-b38a-0c04b79eb9bf', '641008', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cce47d9b-978e-4d2e-9dcd-75a9965385d3', '641009', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9fde611d-e344-41ce-9f56-019d41d68fe7', '641010', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('63c8c3bb-d4b9-4392-b0b5-d44952f04407', '641011', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9f4c9cb2-176d-40b0-8237-311dc1fbac12', '641012', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3a1bee13-16f2-495f-96e2-99f40447f0a2', '641013', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e8ef999c-9bfc-4009-9994-468d89ae0d3d', '641014', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ed0c040f-37e5-48d3-baf5-2d3e6de29501', '641015', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ea5c3b03-72b7-47a9-a00f-d2d52e21c3cf', '641016', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('19a25d35-ce5a-4d2b-b33f-90343ede636a', '641017', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f0b06516-39fa-4ca3-ab10-6d0fec803484', '641018', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('141b074d-88a2-453d-8bb3-4dbeafffa02a', '641019', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('20c44fd0-a88a-4866-800c-8c54ae12d0ac', '641020', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9fa1fe61-f8f0-4015-9689-95b204a043ce', '641021', 'Annur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('237f13aa-920c-48ee-8089-24a30e86a4f1', '641022', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('818365cd-4d7b-44d5-9a45-732bf792b7eb', '641023', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('249e8fc1-b65c-495a-9478-f22b2792c034', '641024', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('308fee68-deda-4e84-8981-e26b88fdef8d', '641025', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('356bc0a4-c780-4612-bcfe-01cb92bad917', '641026', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('eaecfc1d-3b2b-4b03-afe8-024b6ec70aec', '641027', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('045c751d-55ed-4380-994b-8931f0bd5453', '641028', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('082de7ca-af2f-4f68-98e0-d87fd3b0fe3d', '641029', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('34f6bee6-8410-4764-9424-48d34fefa738', '641030', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('102ca75b-b316-44e0-a8b7-a3917675d91d', '641031', 'Sulur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2f8d9a0a-cba1-453f-8036-689e6f040233', '641032', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bb1634cd-62b1-421c-bb02-ffcb133df98d', '641033', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8c63add6-3251-468c-aa17-a326f5ea7bc9', '641034', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2ab92bc1-a06c-4bdb-b5c7-29016e15ebb0', '641035', 'Irugur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cd9d9fe9-a4b9-417e-bf5e-48a784a7db09', '641036', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a3b99285-233c-45d7-a3c6-ff6d34c77685', '641037', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6f14eeee-f637-483a-8a46-c560c226b82f', '641038', 'Madukkarai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c1f84ab3-529b-485a-9eb4-c86424f49a92', '641041', 'Othakalmandapam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e2bded26-eb69-4be7-809f-2a8402cc3305', '641101', 'Mettupalayam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('dc203fdc-e4da-498f-b4dd-2e27484cf030', '641105', 'Mettupalayam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d7ffb387-0587-456d-a91a-8f5836f468a6', '641301', 'Pollachi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e97b115e-905a-47db-b2de-0ac91b5fc9a4', '641401', 'Valparai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6b10f2e9-6e7e-4bee-82f6-f3dc8ac9ca22', '641201', 'Palladam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d10e3175-d601-4549-bdab-3d3c87322793', '641601', 'Tirupur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b021b574-1468-481a-8c7c-7ad43b3feda4', '641602', 'Tirupur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('01652a2c-4066-46fd-9bd5-1a631724ec6a', '641603', 'Tirupur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a1081f4a-627b-420a-b2a9-5eb7be159c37', '641604', 'Tirupur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cfb9b7c2-7467-4c2c-b2f4-0eb15fa4cdaf', '641605', 'Avinashi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f99f7b28-a535-4ea6-a652-b4ab85ad8bc1', '641606', 'Palladam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('de314727-7ec0-43e8-a233-0e362538652e', '641607', 'Uthukuli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0e4df910-4a43-4069-8b9d-fc24307d597a', '641608', 'Dharapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fadf07e8-ea3c-400c-a3e9-50f027cf65fc', '641609', 'Udumalpet', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('87f2ba22-35fc-4c6f-96e4-9a2029ec79cc', '641610', 'Kangeyam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ebf9edb6-8c65-4314-a164-09634585e184', '641659', 'Tirupur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('aea0520d-363d-437b-8815-f0b81f8f91c0', '643001', 'Ooty', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d64707b2-aecc-447d-a766-adbbd0d6d6b6', '643002', 'Ooty', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3b521086-33e3-4582-9c5a-df6ea87cf503', '643003', 'Ooty', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('98634979-11c3-4c80-909e-e90f697ca640', '643004', 'Ooty', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('27e7de08-83fa-4656-8f57-a6ceb74fb2c5', '643101', 'Coonoor', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('280765e7-4e28-4015-8f7c-733f45153c97', '643102', 'Coonoor', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fa262c7e-d811-470f-b47a-d2e7c375c1b7', '643201', 'Gudalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f20afe5f-0a65-4f1a-8703-155bf21f78e7', '643209', 'Gudalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5c850919-5f50-4b14-9340-c5d4d7a684ed', '643211', 'Kotagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('440cd42f-210a-4ac9-aab5-b5f346f5ed07', '643213', 'Lovedale', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ec82938e-6486-4f28-bce5-3251434c6382', '639001', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d7d21206-011d-496d-8e26-75793e33b8bd', '639002', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ff0121c4-50b9-4953-871c-276c8c717c9b', '639003', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('788ea98b-6196-4492-95c8-5283858afc99', '639004', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f0a4ab7e-1a1d-4bba-aab9-d194d5ff4a57', '639005', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ecebfbd6-d212-49bf-a4b4-150f6ea2ee39', '639006', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f00baa22-37cb-4e95-acac-a2f7f7d55f84', '639007', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('dce8c7c1-8ad7-4213-b4aa-280114c5f1bc', '639101', 'Kulithalai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0a89167e-2557-481e-b801-56bd80ced714', '639111', 'Manapparai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('724b8cb8-91dd-455a-8fc4-bde89d28f97e', '639136', 'Manmangalam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cb115f6b-fc33-47b5-871e-fb74ecae9110', '620001', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1350302a-26d4-4515-a33d-f7e74852b061', '620002', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8a2bede1-d589-48bf-801a-4fca7d5c53da', '620003', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9aa5cc95-93f4-4ae4-8265-b9e74ded62b0', '620004', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7440e9e4-504b-4bdb-9a26-3924f42b5d9d', '620005', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2778eeb8-31a6-4b43-a7bd-bcde8dfbbc1e', '620006', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('107cb872-84ae-47ad-9ef4-b11c9ae56541', '620007', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ffb68f50-7f2f-40f6-901e-c81d26bdb7f8', '620008', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f07614ee-4a99-4d8f-8ea9-f5845f2d4449', '620009', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('dcca81b5-153b-4f2d-9ffd-05d8f903fd5a', '620010', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('dc16cd87-4093-4b4a-801f-2370a0826ead', '620011', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('04822562-9b8a-4d50-a4e0-0d0d4b86195b', '620012', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d4d453bd-62f0-4815-8bb3-725745ec7042', '620013', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d5a21163-4e92-43c1-a1e3-c28887407fb3', '620014', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9cc83959-98be-4819-84c4-a4c00bda925b', '620015', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f0cb6f5e-8ef0-48ba-a172-800a2ec9f55e', '620016', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3a643367-db52-4bb0-a79b-71cf46bbfb15', '620017', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7196654e-3982-4287-8887-3decf46fe10b', '620018', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('35b91d57-0c14-4f80-bb9e-acb6eff60f63', '620019', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0b594f97-699f-4de3-a548-cc8b14671380', '620020', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4ce6de83-309f-470e-b1d9-9489237898f5', '620021', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('51785ca4-f4b2-41cb-b6d9-9d47fc90acf1', '620023', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('84683d7d-3828-48bc-9284-be5e9f05fd12', '621001', 'Perambalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4cfd3680-87d5-4445-8d57-84d2f5c4ec79', '621002', 'Perambalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e5eb56d5-d940-4dd2-ad05-fa9dc1c1f7f6', '621101', 'Ariyalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4f613138-6df5-4673-b7be-099e363b3834', '621202', 'Jayamkondam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('27624e48-9526-4c9a-bd21-3a02a5bf6fd6', '621704', 'Ariyalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('16f9a0f5-d2d3-412a-b5c0-35cca8ab3e99', '621705', 'Ariyalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c7c9b923-115c-463a-a6ff-22dcdbe2532d', '621706', 'Ariyalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c70cc23a-5af1-485e-b917-7e305ee032d9', '621712', 'Jayamkondam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e746dc87-d84b-4a1b-ba6e-9332996e7134', '621729', 'Sendurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0acc7de9-1d2c-423b-8d9d-6b1d73077deb', '613001', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6c23cb0b-9357-4861-abfd-6cefd98706ae', '613002', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8f5783cf-98e7-4043-8658-cbaf6ccb2e23', '613003', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('abf7fb9b-6059-4d1c-baf4-54680072d7fc', '613004', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('76d4467d-bd8d-49f7-90e4-aa2640871b74', '613005', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c293d8de-525a-4036-8d36-9a78733f8dfa', '613006', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2dcbc6ed-9ad1-4479-9155-c4955a5d19b6', '613007', 'Pattukottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('73ccbbae-6505-42f4-9881-89471fa179a8', '613101', 'Papanasam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('faeeeaff-9c7d-4719-8612-d75c87a15733', '612001', 'Kumbakonam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d7077ada-8a25-4cb1-9603-2d350ee8472b', '612002', 'Kumbakonam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3946311f-7724-49f8-b02e-d3b7ebb30241', '612101', 'Mayiladuthurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a27479a8-5a5b-47d1-b1e4-58f39c98b258', '612201', 'Kumbakonam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6ba4caab-d6a4-41f5-b2c9-c271edcddc30', '610001', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f9692a91-f825-4ca0-ac32-50c6c46c1cdb', '610002', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('281f7db4-dcfc-4a0f-b9d5-1af32bf65061', '610101', 'Papanasam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e4253ae0-f1d3-405c-a33a-22b13a6afb21', '610201', 'Valangaiman', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('39df3745-33af-49cb-8d5d-952db9177a0d', '611001', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f68a4875-f4b4-491f-b326-d6a74d43f98b', '611002', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('507fa3d6-0593-4406-871a-79086225a94b', '611101', 'Velankanni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4767a671-0a95-40f6-a900-cfff712ffc06', '611201', 'Mayiladuthurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d976602f-4b7a-4be9-b10b-0ee9298573ec', '611301', 'Sirkazhi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0e807902-2a0a-445a-b55b-1ba6e54158d6', '609001', 'Mayiladuthurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('dea9388b-e77a-46c7-941b-75e56eeb5d58', '609002', 'Mayiladuthurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6ec6a8a7-c83d-4c03-99fc-9990981de0a9', '609003', 'Sirkazhi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ef9ffcf4-bd5a-4213-b7ff-bd44b9cfa912', '609101', 'Poompuhar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('dfac1621-932d-413c-bf80-d9eba3cc0a9f', '607001', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d13157c7-52d1-403c-8ec5-b0186b249345', '607002', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d8a5ea1c-1be8-4334-b5a5-85ddfc37c17d', '607003', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3ac9e3d5-5fc1-4df6-bfdb-12a4e352fcd8', '607101', 'Chidambaram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5bf2bf07-e2a2-4739-8040-fac4e7deea16', '607201', 'Panruti', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('65c49994-e7e3-4ac8-b5ef-7802df8b6725', '607301', 'Virudhachalam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('825cc1f8-6906-4fd4-84a0-190b6a508bde', '607401', 'Neyveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1e627603-a75d-4fa2-b0e0-a13b76f4ff59', '607801', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c1baab64-8a74-443f-a6a9-f3e8f1d34d15', '605001', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ad172dbd-b3a2-411a-826b-2670ab15726f', '605101', 'Tindivanam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a20d47e0-ae4c-4bf5-8d89-1fb4a4f899e3', '605201', 'Gingee', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f0edca61-abdb-4c10-8190-2c9860f1f7c9', '605301', 'Ulundurpet', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cfbbc45b-3242-42f2-ad2c-1e31684b82dc', '605601', 'Kallakurichi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5df53d8f-e589-482c-832a-ff0c3b5ecda1', '605701', 'Sankarapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('25ab407f-4f6f-416f-bd13-1fd8fe1d1f53', '606202', 'Kallakurichi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0b350315-d988-4ea4-aff5-bf2b23593e69', '636354', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b0b416c7-c33c-4c30-b8c6-981e66947d28', '606203', 'Kallakurichi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('14039d8d-9d83-4585-9c83-417c87a6c110', '606301', 'Ulundurpet', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('846de1dd-f28a-4bff-9c54-548a366e27db', '625001', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('52ed7607-5324-4fb5-b893-822458738bf4', '625002', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('839167b1-3989-4464-bb88-8e8e829f31f2', '625003', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b65b9d21-4193-4094-8a65-cf3a5f3c150b', '625004', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8cd4aa9f-417c-4137-b313-e460adf34cef', '625005', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('71a8ae98-8866-4ef2-a56d-5ddb5702011e', '625006', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('73640915-de0e-4aec-8090-b710db416a6e', '625007', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3623c710-c2df-4cf0-bd55-bb316bff949b', '625008', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8ade582f-2131-4944-97b0-0c3fe8bf7cd9', '625009', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('39dca02f-ee30-405d-abd1-4ab3f00c2d47', '625010', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('50a8c1e3-33e0-4cb0-b71b-134776da6784', '625011', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e6d69b85-f57c-48dd-b28f-2e9e07acd943', '625012', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('90664f50-4c4d-4777-ade3-3de766bed460', '625014', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e4826d99-0caa-42dd-ad57-f840fc501087', '625015', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ea9f56b8-65eb-40bc-b812-cd5e30d08422', '625016', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a52bcc3c-28b6-4d84-89a7-65173dd93909', '625017', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7eda464a-4c90-49ff-a27f-2c974a1bf17d', '625018', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0663a75e-7bbe-4330-8756-eaa306678086', '625019', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('515d0c51-1ca8-4fdf-a8b2-7af1975d4fd1', '625020', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9e866434-a3b4-41e7-a0d8-d7dfb618f436', '625021', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3d58480c-5378-41f6-befb-4e6e1c013c62', '625022', 'Melur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4170a673-8a86-433c-bacc-6a2bb0dc5744', '625107', 'Melur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('14dd5d5f-238a-46d5-a10f-64f01259f547', '625122', 'Melur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('47fd6e68-7260-4ec6-9caf-5b824c578b0a', '624001', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('56fc1dac-3042-4a63-b243-66f118e4197a', '624002', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1697dd46-462c-4578-9f5c-ebda8c8dea87', '624003', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0529f9fc-83c5-4754-b0c8-84c285997fa2', '624101', 'Kodaikanal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1d46c609-fe2c-47fc-9596-0f41f95d190a', '624103', 'Kodaikanal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('69abe2fd-2c79-4db6-ab0d-d091f1a9c655', '624201', 'Palani', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f87de165-6945-4fec-8b03-78ff15c89b8a', '624202', 'Palani', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f9999322-6b73-4a73-ae6c-34c1aca867a3', '624301', 'Natham', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c911d1df-35dc-4ac2-a4cc-9f2226195a41', '624401', 'Batlagundu', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2b65b1a7-9828-49b9-9287-ebd97bb604a5', '624501', 'Oddanchatram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b8247a01-fed6-46e4-9316-6614cc33147c', '625501', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c8394c49-d767-44b3-b53f-3c2154c726a4', '625502', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('37ac636c-5924-4aec-9cd6-1401a8c2c868', '625503', 'Uthamapalayam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6375cd9b-a5b0-4df2-9c79-3a5449f19346', '625514', 'Bodinayakanur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('40752f9d-4450-4b12-a462-030ef4774183', '625601', 'Cumbum', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d672e717-e72b-47ee-9c01-9129157305b6', '626001', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bb1adcaf-46a5-4211-b9d5-3b87a23aee08', '626002', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0a707146-b94d-45a4-b4af-e57544abc5ec', '626101', 'Rajapalayam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('72cbc730-1466-470b-8dd3-572bac879699', '626117', 'Rajapalayam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f6150b97-98d0-4ea3-859b-826df72acbe8', '626128', 'Rajapalayam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9cdb056f-d265-47aa-b732-607bb5ce4f14', '626201', 'Sivakasi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('051fb471-053c-4528-85d3-7cd56beccf51', '626202', 'Sivakasi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('49192aa4-ec15-4fe7-88c7-ffd206672ec0', '630001', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8aa30ac9-9431-4b24-a46e-41b66dfb5579', '630002', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1d621edc-c33e-49fb-808a-d89386feec12', '630101', 'Karaikudi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9924c088-55a9-48f8-a54a-c9e23cae0ba3', '630201', 'Devakottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('53b16e9b-2c84-4dc3-b0c5-bd1b3b2d33b3', '630301', 'Manamadurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2bc9606b-486b-4a0c-9aef-a0ba648e201c', '630401', 'Tirupathur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f581767b-55f6-41d1-929f-9a806cf82c01', '630502', 'Ilayangudi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9a61455f-fe7d-4c2f-a7e2-c507ea7deab1', '630561', 'Paramakudi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('15bea407-5ec0-4dd0-b95d-558a98661ab7', '622001', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f467db89-444b-4ffb-abb5-45e208495a9d', '622002', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('70959407-1e92-4631-88a3-3c344296f4ce', '622003', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f407beee-a52e-41c1-8b01-45da03507f3e', '622101', 'Karaikudi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b6c5f974-9a8a-4c1a-8a38-a5dc6d849332', '622201', 'Devakottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('29d6a12e-4532-466a-854e-43382dbcadfa', '622301', 'Paramakudi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('303a59dc-275f-4d46-9583-8095036aa5d6', '622401', 'Aranthangi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7f4cca11-b399-4b52-b4a2-7acbaed28797', '622501', 'Gandarvakottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9749c04a-f50d-46ac-bc94-0bfc6199c98f', '623501', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2b6d7046-8eb1-4464-a120-27d839cad43e', '623502', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('48b86f4d-ff3f-44a6-ba8a-8d58f3396b83', '623503', 'Rameswaram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6e111407-19a3-4974-b3b3-dd65a5c115ee', '623526', 'Pamban', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fa647784-1ff1-416b-b1c0-20704b9dec07', '623601', 'Paramakudi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('029ff0d8-26a9-4b53-abd2-10479c2f19c6', '623701', 'Mandapam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5ea7093d-7391-4202-a1fe-89757ab23626', '623806', 'Mudukulathur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('139de91e-8fce-4650-ab5d-4516eb7fba03', '628001', 'Thoothukudi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('80db3b21-dbc3-4104-9e59-f452b3a346bf', '628002', 'Thoothukudi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('26a08d7a-9456-46ad-a83d-8c1937daf703', '628003', 'Thoothukudi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('15cf60c4-56bc-4291-8439-34cb4f943cc6', '628004', 'Thoothukudi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cb0ae0a5-89b4-4187-a699-4490922d5c52', '628005', 'Thoothukudi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('45e44cc7-a233-4b77-8f83-d8e11bd05041', '628006', 'Thoothukudi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('764ef8e5-6cd9-493f-9562-ad5571cfa846', '628007', 'Kovilpatti', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('223820d6-c4be-44ed-a467-104dc87c8792', '628008', 'Kayalpatnam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5200f95d-021a-41d9-aabf-f789f362c1f9', '628101', 'Tiruchendur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a6b6197c-6b72-4c05-902c-683231d3c140', '628201', 'Srivaikundam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3c6f9e11-413b-4b22-adf7-19152a0303fa', '628901', 'Ottapidaram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('38d3dcac-4448-4374-90d2-bd20fad196b9', '627001', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('512a9de9-d7ad-4f09-802e-5cea7c3cec1c', '627002', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e518048c-e4e8-46a8-9e3d-3c7e9827070a', '627003', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0fac9164-e71a-4f75-b0da-247f896eac44', '627004', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e708946b-3bbc-488c-a29f-526ef5aa221c', '627005', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('76a17285-5fac-43d1-b391-9668d25f2199', '627006', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7dc86e9f-54ae-441e-9c6f-52d991695d1f', '627007', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ed82fe2b-c0cd-4a11-ba10-a629e4d6a188', '627008', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ca37bacf-2d48-43f9-af4d-d110df0a3790', '627009', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1aec2e36-f3d4-443c-8bf8-49d9c18f3a0b', '627010', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4e8f71ab-3f78-410e-afbc-13565dbe2bfc', '627011', 'Nanguneri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('02ff0aa7-24e5-4a5b-aa99-5dfa4dd147cc', '627012', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('19ed1e06-23c3-464c-9e58-ee0c7486b272', '627101', 'Ambasamudram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cf40ffb4-8359-4d3a-a1c1-80dc84ebf45f', '627201', 'Cheranmahadevi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f06d6fab-4337-4cc6-ab8d-b24a012ffddb', '627401', 'Tenkasi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('93ab7041-b348-4d4c-9f06-2083c0ddfe65', '627601', 'Sankarankovil', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2b08b2e0-e90e-4015-900a-7490169b6ea4', '627801', 'Tenkasi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('557c2ebf-5ac3-4cca-a452-25bb9e22550a', '627802', 'Shenkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9e17408a-f70f-4adf-b910-690d6f77ff78', '627803', 'Kadayanallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0ddb7f60-644d-4e18-b13a-76f6f73115df', '627804', 'Courtallam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('048d6208-6656-48c7-bac4-492f2ca89de8', '627851', 'Tenkasi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d731bb58-3b06-406a-bca7-9155758e9715', '629001', 'Kanniyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('50abdd9f-0799-4f1f-96ad-29b11f1bed0e', '629002', 'Kanniyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d774fe83-72c6-41b9-b6ad-1fc97bc095ef', '629003', 'Nagercoil', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1c54c7d7-1817-4ba5-bc73-1fd69fc8026b', '629004', 'Nagercoil', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cb37cf8e-ca9e-4f72-a47b-0e926dca07d7', '629101', 'Marthandam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('68cceb74-4b43-442c-8443-182b70c6737e', '629151', 'Padmanabhapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b5e81d27-583b-41bb-94e6-c33fc04a5b54', '629201', 'Kuzhithurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ecb16242-390e-4891-b01b-60898df14257', '629401', 'Thuckalay', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b6a03947-bbf4-4302-a32e-bd841fd168dc', '629501', 'Valliyoor', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('52db7be8-f3e1-4460-a218-49a3b55e1742', '629601', 'Sankarankovil', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0620c3d6-fc0d-4f76-87e0-2c09affdaa8e', '629701', 'Sengottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('724189ba-c93e-4240-ab34-88fd51297eed', '629801', 'Tenkasi', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f0eb6328-8f00-4a65-80d1-edbd92917ae4', '629809', 'Colachel', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('932b9207-383c-46b5-9d3b-bb80b12a712c', '600016', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a905b630-b2a1-41f0-8f7a-01721612637e', '600019', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f5192c0f-b1b4-4e60-8e04-104dc1952f6c', '600024', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('63af3bbc-840d-42eb-9642-162462034850', '600021', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8cc687ab-f7ba-4474-ac05-53cc7b814762', '600022', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5029f549-716f-426d-9de6-f1eb29d729b1', '600023', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cbaabffd-3b83-4ff1-b148-8a1e824f939e', '600036', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2e8bc719-d9d6-49da-be14-666f21f94599', '600037', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8ed72589-f142-40c3-b772-3e786344afc2', '600039', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0a98776c-328a-4bd8-9979-4005196aca8b', '600032', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('362d7d9e-ba01-4583-9a18-7f0b3d1eedff', '600046', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('03b841c1-b458-490d-a244-c693e5c20111', '600049', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ae36e33f-4d2c-4315-8c61-e560e067c0e0', '600050', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6bec2dec-3d40-4d9c-90a1-ce06d0bd37f2', '600047', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('52666db5-7245-4b3b-a7d3-e0093909fc68', '600041', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('80f06d02-25ee-4f0c-8ec5-31755ff70d46', '600045', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b77d0f04-0d4d-4a7a-9d47-8164263b8e32', '600044', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f0180b76-9d63-4fda-aa16-c0274e096ade', '600043', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b92aac94-807e-4453-ac74-66a8e0d23440', '600048', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('45514cb2-e6ad-47c0-b399-d23142dfc5bf', '600060', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9c022b28-ff25-4785-8afe-3de1b9108d3a', '600056', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ec231cf8-8a98-48cb-868f-7dc4680ed871', '600056', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b26a56da-9841-476a-95d4-2fc6f3c0dada', '600052', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e4546dcf-8f62-436e-b8cd-47baa2c75001', '600055', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('850e4225-9f7a-4d0e-8bcc-f817686f11b6', '600058', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('35f95171-2d8e-4f37-8e2f-2095deed8043', '600058', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ec3ade0e-3e3a-4c0e-82f9-47f60afa2f11', '600059', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('69c7cc99-a939-4e7b-be81-b9ce091b6bd3', '600051', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c9dd5183-db0f-4e61-8c9b-d5db5d143899', '600054', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ac602e02-019c-453c-a229-8c04a7722268', '600057', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('06d0c14c-0419-46ef-a2be-6b37cc6edb06', '600053', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b084ab3a-5b6c-4772-a2f7-fb921e6de0ca', '600068', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('eca85d05-f079-4e2b-92ab-e2a8b38e1d2e', '600063', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7bf89ad9-a491-4787-a90c-af61580bcdbd', '600064', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d9bc024a-345c-4418-9ec9-e1164e66b84c', '600061', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7492339a-c379-454b-a0e4-9d2304463287', '600067', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ade54be6-2e9b-4bff-88c4-08f60169dfae', '600066', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e9c0c559-35a4-40c5-968c-64edd95c624f', '600065', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cfed7cda-4d38-4395-88ec-de7f7b181ea5', '600070', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('10874a99-c6a9-4f7e-b0eb-cb664460a548', '600062', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0102575f-781b-44ab-adf4-8e7d016a19b3', '600069', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6992d449-c989-49f2-9426-affaeb2bfbdc', '600074', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c73835b5-7428-4cc6-80f1-14bcfd80a481', '600073', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5ab1f047-c720-4a6b-80e0-53521ea29b15', '600072', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9d4b79d3-d4d0-4961-b6c6-ad67ca068a66', '600078', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b01613f7-b67c-4764-a8e4-a83c3641c3ab', '600071', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('69e2b0e4-0306-43d7-8fd3-7301858776b1', '600076', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('404aa7fc-699e-4bce-ac52-a37551afe9c1', '600075', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('eb83b4d9-2c8a-4af3-a8f1-72422ec93c9c', '600077', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f2650c6f-cda9-4d7b-ae9c-e3551c67a815', '600085', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('84bb97a4-96b5-4885-bc0f-4fb9976e262a', '600081', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c0afd9a5-09df-4d56-9650-c06d94fec56f', '600087', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f0978c9a-f021-4f15-b294-92bfb89e9715', '600083', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2753b33c-538f-48ea-adfd-c3cab3cb9bd8', '600089', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('955e9dd7-5a4a-4f70-a106-d9b1fbbf28ac', '600088', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('da723085-0c54-44b8-9464-0b0708223e14', '600084', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b2042440-2172-45c7-bc77-ebb3959cb090', '600082', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('73b7b01c-8c0a-46e8-96bb-54cf0a3cac31', '600090', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ff3dc7bd-a2e6-4507-8166-530e7c73b96b', '600091', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d97d7353-9398-4c35-b061-4911a5bbd387', '600093', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9fec7fe0-a453-41f9-8d07-12b58253002f', '600094', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('67c6aa38-c4a1-49b1-86f5-2dd555c5e7f5', '600096', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('caa09e53-9003-449a-9049-425ade80e0e0', '600097', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2ed848c3-6a37-4681-9a6d-3ccbcbdd83a6', '600098', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cc5fb542-63a7-4e2d-be57-70a76f89d62b', '600092', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0d789a5f-cb62-4229-8cd4-c64da4c0fbca', '600100', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ca1d2304-6b59-46c9-a2f7-4ff4a68884c9', '600095', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('dcd5d564-bcfb-4291-93a8-47721a469f53', '600099', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('37682b2f-c4f4-45bc-9852-5f6616cf4277', '600102', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4d0a5e27-6dbc-468e-87e4-aec29c087c0d', '600101', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('36ef23b2-f347-4cca-85d5-17c3d73cb225', '600103', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ce8428d6-1d46-4ea0-a17e-c262fd2bb0e5', '600106', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a517bf32-8b6e-4e6d-bcd9-d017f478e035', '600104', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('224146de-d655-4aab-9c7d-ec6ed1d2fc09', '600107', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('abe8b6e2-2e68-4448-a250-7b2e6b72a16a', '600110', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('37fdc81d-049a-47b9-b2e4-25d9667b4e1a', '600116', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0253d694-9a8d-44a9-a9bd-7d027e37fdba', '600115', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('222f9f65-d189-4cd3-a547-40a84f593969', '600118', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fe247865-e3e8-44a3-afdb-692f12959687', '600113', 'Chennai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2c4a8acb-1f1d-4292-8d12-78de70558eb2', '600119', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d02337b4-00cd-422a-b040-57aa514b4f97', '600117', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9cee7d7b-3ab6-4386-86a0-fd3e62faeaed', '601201', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b84bad2f-86a4-4ae2-8fc7-8c764c856a77', '601202', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b9b44169-70cf-45a1-9c52-df5382c05d44', '601203', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4155bde0-4b1c-4cdf-a843-50679acd6f04', '601204', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('31a10f13-068d-4826-851f-f034c9c01886', '601206', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4abc136a-c25a-4dad-a742-2c21be6c60f5', '601205', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2d752857-347e-4e87-aa13-f79dba0b17e7', '601301', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c248d4bf-b62c-4fb5-aad7-6d1edf763af6', '602002', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9d687067-cb68-4641-940a-ed3e6a390277', '602003', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4f23df4c-7e5f-4d78-9081-89413f768d39', '602021', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4c46a99b-31e9-4769-8820-4337ddb3de37', '602023', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6b984e30-f37c-4ae4-9f61-0766c24ec1c0', '602024', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a52876ad-eea5-4755-91e5-3d96f1bf1b3c', '602026', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7ec2cc7d-fcc7-48fe-b247-2d9263afdabc', '602025', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7f7d0189-068d-4de3-824c-485705e95f1c', '603001', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b5ba80c0-159e-4044-9400-3ecf56d0d60a', '603003', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('508c1636-d6c1-4e79-a548-0e11593fc91b', '603002', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3e40cf94-1deb-4531-8c10-280bd9a7ff8b', '603101', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('aa4d8e54-c043-4896-912e-f04d5cc6decd', '603102', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7e994ada-1ae8-4d27-ba73-3782354b4651', '603103', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6a7fdc86-7e31-4795-bd86-88667c05b4d6', '603104', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e5ae2f3c-53b1-4234-ab66-764adff20124', '603106', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ba1bc1ac-326e-4d2a-8480-491024dcdfb1', '603105', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('747be454-1954-42a5-9fc1-9523dfa33de2', '603108', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e78554ed-2336-4b66-b301-2c102f4ccea3', '603109', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('194a30b3-33c0-41ec-87a4-01d29050b9e9', '603107', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f6862f7b-0771-4a1d-9295-dcfd1448f0d3', '603111', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('41075743-9aed-4767-90f5-2a5485fb1545', '603110', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('337370c9-f097-4fc8-980a-0ad2901e34c1', '603112', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7e8506a4-d33e-48c4-96c8-13108f8c3d64', '603127', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6f96c5e0-ac1f-4cff-af89-8779b194dd10', '603204', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2c55c9a9-20d0-47ae-a902-a6f26c4de30b', '603203', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9c7fd548-dba3-4ac7-95df-2aef68846985', '603202', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cf7fc9ad-f444-4c42-8ae0-cf12d604af5f', '603201', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fb0e03fe-ec26-4bcf-a333-fb752684cd26', '603209', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('55b298cd-20fe-44e4-9f5f-a4254930cad5', '603210', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('19437448-5c5c-4baf-a5a7-1def26cdf21a', '603211', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('39714bb1-4b99-4514-8858-2a5939340637', '603302', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ab448c39-5fc0-4eda-a0ce-3076b25d9d8f', '603301', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('83b7882d-5104-4839-b34b-050f2d31791c', '603303', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('84551113-a0b0-48e9-b85d-47566a449cf7', '603304', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c0d3ce45-0f50-47c2-b786-ef4f451bb8c2', '603305', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fb9c3bc9-2047-42f9-8ddd-3054cc64ada0', '603307', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('023c0015-d2ba-4ff9-905c-cda167265819', '603309', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('562f9087-0f16-4d41-9e9e-e39d872fdc88', '603312', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f912ab47-dcc5-40b6-aa6c-0d26d54a9f4c', '603311', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3a2c493c-3a31-4eba-9036-11e1034734d7', '603313', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e95d584c-19a8-4b67-8395-5acf7f1a88c8', '603314', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('55422a86-8bfe-4158-89ec-0d621e3046f0', '603310', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0c1e74f9-5332-453e-af18-ff17de212141', '603306', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('688b8fbd-2988-4d79-b9a5-938af014419e', '603308', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d7475410-872a-40da-b205-f88d06cea972', '603319', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('630083e8-4cbb-49a7-a33b-d1a9dfeef277', '605007', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('14053719-0e15-4c08-9d72-3cfe321612c0', '605014', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2d55bbdf-2a70-46e3-9654-45d4cace53a4', '605103', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ea5d52a1-f961-4e63-806a-66fac549c07d', '605102', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('285a8a55-b28f-4203-9026-6e44dd57255d', '605101', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('637cca4d-bf2b-4d8a-969b-571542736c6d', '605105', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d4ea6857-673f-49c5-a012-50433f6002f3', '605106', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6361e0eb-e587-4083-9b1e-054fa8097bd3', '605106', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e5c4fd49-bd01-48d8-9d63-3f3485f1ba25', '605108', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('62155500-07dd-438d-a16a-052cbb74f4e1', '605109', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('67034bd6-5fbe-48c5-b9ba-c122d1cb5994', '605107', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bfc66d21-9cdf-458c-9827-98d33e940138', '605110', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('51f7bdf0-4056-4389-8025-2a6f782452b7', '605111', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7abd04c2-05a6-4b32-9d9e-957ff6cee164', '605202', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('61629c10-ccda-4f86-b8dc-8df8b942985e', '605203', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6fec449b-f9f3-4d04-ba4b-8e666f5f4c88', '605201', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ec000062-81fe-4cf4-824f-1ebd98860bff', '605301', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cc02d795-5848-4ea5-aaa2-8f1f5c7ffeaa', '605302', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3cd44348-07ab-4a78-beed-04afdd5ec50a', '605401', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0c1ec7b6-538b-4935-aefc-a5a733a259d3', '605402', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5ac1c371-25a5-4049-a08f-c6c951bdf9e5', '605501', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ae307ed9-1eee-4938-94ad-ea94f3413fae', '605502', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1cf1d9e0-4a3e-41e6-a09f-ddd9f3d8918e', '605601', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0c8aa7de-7db4-4db7-a770-c5fd2822b07c', '605602', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e5547393-a025-46e7-9c91-e05e0688faa2', '605651', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fcdea9fd-bc2a-4162-a0c0-b86086171f91', '605652', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('00681956-773e-4b56-916a-443580a03c78', '605701', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0dd5e6de-4426-4287-9a2e-341b2811db1b', '605702', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5f2195ef-1fdd-42cd-b3c0-7b206e3b1155', '605702', 'Tiruvannamalai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7b49824f-c154-4af1-a798-22ca2dd5f0da', '605752', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d1e524e7-aabc-4872-aa52-83be9456877f', '605751', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e34cd0eb-fa7a-4d9d-8354-0bee0a38d100', '605754', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('247635c4-7696-480e-a7cb-cd7d7f421255', '605757', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('50ba2688-bd42-4efa-914a-e72d85342d9f', '605759', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('facfc97a-fdfb-4d69-99ab-47c0746ab96b', '605755', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('de11f615-be6b-43bd-a92b-4267c652ce47', '605756', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9516cb8d-5691-43bd-9d31-9771e74387e1', '605758', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('df2e12d9-40b4-4b86-95b4-09ffd35fcbd3', '605766', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ccc17d4a-cf59-4852-9a43-61fd1e6d5bb5', '605802', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('54ab0caf-42d6-4796-acc0-50ff5a8bb6a1', '605801', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7c903d25-3b79-499e-81df-cd0c319e424f', '605803', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('26e08b3c-4703-448f-b3fb-9136788d7727', '606003', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4f627f90-f654-422b-bc0c-5fd1f06f6c3f', '606001', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('044c6bf8-b685-4b2c-b835-74f891beace4', '606102', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('05926f21-1fdb-4645-a739-26e367fc4b38', '606103', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('15af4b8c-3aae-4f80-9a77-798d87975cdd', '606104', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('56b28a95-eafb-4412-a62a-8aef74f031c9', '606104', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7295489c-054e-4913-a285-d5f39f7a35d8', '606105', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d7ea17dd-de58-4c84-84ba-981fadc6cacd', '606107', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e6b3b94b-d61b-4f0c-90eb-217bdc8a0a0b', '606106', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5bc2dafa-1b65-4ae2-bd05-16cdf3812421', '606108', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('503759cf-7089-4a13-8b0b-511a8cb87e1a', '606110', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ff797cbc-3ccc-4938-bfe6-7072057fc3a6', '606111', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('16796a9c-55f1-4526-b5d2-45f943762610', '606115', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f1a38580-34e2-435a-9667-ce31ccb5d446', '606201', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('80b246fd-5fbd-4ea9-be84-98345432652e', '606203', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e19fab7a-88bf-4781-aa2b-d5e50814ab68', '606204', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('65c1dec6-614f-4c2a-8457-2670807d1a7e', '606205', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('dbc2d17d-c8b0-456e-8f96-693c3e907761', '606202', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('90248fa1-c164-4e67-9dbd-227fae77eddb', '606206', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c0c3b538-13a5-4bec-a4ef-2520f4a68b1b', '606207', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6710bfb5-1fd9-4029-a38c-bab6cb0c800f', '606208', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d848ad87-0593-4657-b55c-61611f07392d', '606209', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fa1f6e3e-8218-41ec-a864-63f7725948ac', '606213', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2a87085f-1f8e-4190-8eea-f1204f74c80a', '606301', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('be6566f9-3c47-4027-a9a9-fa9487e8b6fc', '606302', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('99b947cc-f583-4985-b6cb-20fea0431939', '606303', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('00224d0c-1eeb-4f42-a1cc-a7bd39fac65f', '606304', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('26a33406-5a6a-43af-a945-52586f0d7de2', '606305', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7999b1b4-aaa8-422e-a208-3337cf2587aa', '607004', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6c0b338c-78f8-4950-b7dc-c44cdcb6d408', '607005', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3b76788b-9fb5-4aa6-b736-7961a8b3ff2f', '607006', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a8a01905-3ce3-472f-8889-d2bd9dda534d', '607102', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5b0a3a4e-1832-4ac7-9230-c2b33047d51a', '607101', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4bb13d03-9b47-47e8-add9-ef5d5cf7142b', '607101', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f5fa3897-1fa3-4056-a729-d58083b1ae88', '607103', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('91739242-98b0-46d1-bc58-00d62d692593', '607104', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fba06312-3933-416c-b1f2-c9f9e4a43004', '607105', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0f5aec48-7833-4c8d-b5c1-9fd8ebc9b099', '607106', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4cbfaed6-ae0e-4ec6-bc61-95d04b0744ff', '607108', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d613261d-bf84-433f-a29d-06afe330545d', '607107', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e34b988a-e9e4-49ff-ae98-184fabe15259', '607109', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('20aebf31-117c-47c6-8f48-32161ca3a505', '607112', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('61d38853-9ad2-48b3-9c44-65391d92a650', '607201', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4019e3b2-9257-471e-bda8-d75264b028da', '607201', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6ed20daf-e095-4d84-8584-db6f472730ff', '607202', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bde28e18-16c0-49c1-a8f8-d3d2e71fb098', '607203', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bc9e4c68-c39a-426f-b990-72dca33f56dd', '607204', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1614bf6e-7ddf-47a4-b14a-07b043802be9', '607205', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9360dc7f-3869-40a8-9cc3-0e177ffa61f0', '607209', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b6f45c4f-81e3-4319-8bf3-a21dc5665f34', '607301', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b3972022-4590-48ac-bde6-0cdb1d022cc8', '607303', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cac18f1b-ce4d-400b-aca7-ec2dda1b2200', '607302', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d8343536-8b3f-48f3-b9cb-4c2bb9afc14a', '607308', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('298072b1-2a2b-4a36-81fd-31d4be2fe3c5', '607401', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5367543a-c488-4b13-83c3-0caa65a18e7b', '607403', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('73949e1d-4371-4533-be58-616dc7be7b17', '607403', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('509d0a1c-eca4-4183-a970-4f5b6998be88', '607402', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2ee967b2-9e62-4bd6-b41c-47f5f3dc3754', '607802', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('001b7cc7-a037-42f5-aff3-2948d7c7feff', '607804', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('054dfabd-6c9d-4450-9e33-c1ddb29c581c', '607805', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4f3172d2-33be-40aa-90b2-d96ea9f4c3f4', '607805', 'Villupuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('787e09f6-a6ec-4e0a-94ce-07bb69579950', '607803', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('35555319-bb81-4c52-b0ba-d6f10423dcc5', '607807', 'Cuddalore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a9cfa19e-d6a2-427f-be65-c9506ac167c5', '609001', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3c12d485-1d8b-4ae7-9885-505a53f52b2c', '609003', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f81e19af-9032-4562-8b41-a7455cedb77b', '609102', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('25745688-6e8e-48ee-a5b5-ab655ed01725', '609104', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('15252b03-6113-4ace-9ba1-612ecf078523', '609103', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('92a9188b-482d-46fe-8991-a5bc37821525', '609101', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('eebb3273-51df-4596-9b73-b2bace4e4bf2', '609105', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a4f079e7-6a53-47cd-b672-dcaa0375135c', '609106', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e0018814-fe9d-4511-8281-09d16897db73', '609107', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6fe82a17-67e3-480c-be86-215c0b1b87b8', '609108', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('be729ffb-b135-4cd7-95e2-fbda81661494', '609109', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ef112b2d-8c65-481e-bed4-e9a7ad2e751b', '609110', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f9a37c2a-8784-45be-a05a-d9edbf257eaf', '609112', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('73cddc0f-12c1-4279-9a53-e6e98856c77f', '609113', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b6166f2e-a737-4f55-a4f9-59e00fd909a7', '609114', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5bd0f84e-1603-48c2-9023-0224fd744196', '609111', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('19dae221-f89b-4c0c-8521-efa7d99902f4', '609115', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cede30ae-b47c-4dbc-b89f-eb2e6b378b79', '609116', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('aef1a3e3-a7a6-4dce-88ca-2a71673954e5', '609118', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('693808af-af12-4199-b4cf-67c90ac8e259', '609117', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a335e3bc-46f8-4d83-b6ee-c65e19b4dcc8', '609201', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('60659de5-dcaf-4648-8991-bc8b0631b011', '609203', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e725c92d-77ef-466a-a5b7-ac06e939a410', '609202', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('30212917-74f9-4058-82b5-5a26b7923ad9', '609205', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c79aee10-1c6c-4156-99a7-b4d0b53ddbe0', '609204', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0688491b-a2a5-4554-a0a3-ca7fbe8aa514', '609302', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5e9265bf-50d1-4ddf-987c-b556fbd90943', '609301', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('83b42825-a059-444f-9b8c-e87ccaffd1f2', '609303', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8108e52b-aab3-4938-a28a-50107580ce7a', '609305', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('357c357a-be34-459d-a0d5-efedb98f195d', '609304', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ab6775dd-0b31-4f75-a0c4-a57391476d70', '609307', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b2768264-8331-4953-9636-e7d15775ce93', '609310', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('83b80fd1-2064-422a-89d5-a3bd6f2ae11a', '610003', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8159a0fa-a553-4e1d-8d63-1b34cf93a7df', '609308', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('eab11c70-ff24-49de-92e9-554d8a208f52', '609309', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('658158b4-09cd-4859-a243-3ad49573308f', '609306', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b6ff6bd1-e314-4cde-a048-46b167cca420', '610004', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('beb18064-981e-4cdb-8bd9-94f1e70989f0', '610102', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a09a6285-bc35-45bf-8ca4-46d4d5a32c32', '610101', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('13648965-ce93-4863-90e6-078d14507abd', '610101', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('93ac1e93-2314-4549-b883-b299d2777358', '610103', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3966d954-9e6a-45f2-9a18-db41e261122c', '610104', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('969c8b4a-3668-4fd6-afff-1758c256b27b', '610105', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('110deb07-bf93-4aff-8b2f-6b545d980c0a', '610109', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('84f5b824-5616-4ee2-8b47-66a78ab19445', '610106', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('34c0ddaa-1f55-41c4-9ad4-bb3747a13f67', '610106', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('38e684fd-e0f9-4a13-8c85-e81d8854c8f6', '610107', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1a827cfe-ab99-4c9c-b099-0f4d833cd0d2', '610202', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('36cf7a4f-f912-4c8b-8b60-1069f840f297', '610201', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3e8ce623-f203-441c-8733-300aad143a9b', '610201', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fb3a5f01-9bbf-4ff5-a17d-8f12b2cf0774', '610203', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('be045fc0-1a4b-45cf-ba38-88bc24ae9300', '610203', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f4eb2db3-d97a-4c03-bf01-4232db01f746', '610204', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('85c3c531-0ac7-4d6b-9360-2cc4ce912fdd', '610205', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5279e2f8-5b49-4058-a826-cb0123f9d24d', '610207', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c74117d4-98f3-472d-8b0b-5b758de26e40', '610206', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bbcbcbeb-d0bc-44f9-961d-a24d713a682e', '611003', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('094d11ef-bc3b-4f57-a5b9-66107923b0a4', '611102', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2e976033-18a5-40a4-87b2-7180a4246a81', '611101', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4c1e71d3-1019-4024-ad27-6794618bce9a', '611101', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('06250c52-d30c-482e-ac53-46008dc1c7c5', '611103', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('179135a0-19d3-4919-9afc-4060a7ea6cee', '611104', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4b23548e-c95a-4bbd-8fc0-5961bfef44e9', '611106', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0274550e-e34e-4d8f-a20e-e5e7ca65b03d', '611105', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('906b4908-42df-49d6-9581-505d3362436a', '611108', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5932fcd2-9f20-4d08-ae03-d80ad3156218', '611111', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a7ef3468-9b2d-45c6-bbb7-59281ff2ab3d', '611109', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('23b069c6-2abe-4d34-abb4-0aa0fa819dfa', '611110', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ff6c23c0-2f08-40e5-a123-9ecdf747ae7d', '611112', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1879b6d2-3486-47d7-aa6f-e5eff1afc6d3', '612001', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('90e78edc-5ab4-4a56-9810-9f5395cc13a3', '612002', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1c368aba-d4aa-4e3e-8119-58e5c751955c', '612101', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('36fbfad8-9cef-46e5-ad00-af33d13b8372', '612102', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fd899b1a-d7f9-4775-aefd-acab4e014ea1', '612102', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c7030cd1-75a6-4d42-8736-241ce9fa7334', '612103', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('303f5b01-0f38-4658-af76-e6a945a90280', '612104', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e776f7aa-2ebc-46e9-9240-36fb49feb7e1', '612105', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2a98ce76-c471-4d73-8e0a-e863e7a15b15', '612106', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a5dcd424-8fca-4771-b4d3-c5e7fd7da73a', '612201', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7bf8f287-78c0-49cf-bf05-2d6e80d339a4', '612201', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d9180fd1-86bb-4629-8df8-bcdc0a0ac76f', '612201', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('efe09149-2cd1-4e28-8f64-efde4fa63d64', '612203', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c7e0116a-7cf7-45ae-a6cf-360b940ca0d3', '612202', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3329e903-3962-4521-a043-e080b41f3d35', '612204', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4b6ca2c4-61f7-401e-b36a-118bfb27c284', '612302', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d21b7bd0-21b1-41ea-a611-e213154387ef', '612301', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('11ac0be7-65db-4923-8af3-d720e7d78707', '612303', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('62cf3e06-fdb3-4fea-8215-77791b8568e4', '612402', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('886e40fb-f0ae-444b-ae9e-1903168ddb85', '612401', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fca21ebc-a60c-460d-aca0-77c472231719', '612501', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2507cca4-f30d-438c-a358-5f077ea943c4', '612502', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6337f651-dd78-459b-8e63-5ba1fd7a35af', '612503', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d621bcdc-3cb1-4885-b0db-5ac054216c02', '612504', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('da2c9161-5a26-4981-aced-3f5a9762472c', '612601', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f66d9dde-b9bd-4e61-95a2-2ed88d107c79', '612602', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f540582c-6db7-4881-904e-ee021e8593de', '612603', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5208dd1b-d9a7-4cfa-b592-25a10bf3008b', '612603', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c023ecbb-f6d7-4344-b34e-0eb8e299866e', '612604', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('83808aea-18f1-40c9-b025-ae8fff994b0a', '612605', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('37c10509-2f78-4c2c-aa49-1c648bb77f7d', '612605', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('996daf8c-b081-4579-82c3-d4c742a5448c', '612610', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b776976b-3699-4a7c-a0de-6afee3dd73b9', '612702', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('31c8c08f-eec5-4697-9805-ad36b9dbc7b0', '612701', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('985765eb-8cbd-45ac-befe-93999a5172f0', '612703', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7ce468e3-0a69-486a-ab17-b3cf536b20e4', '612801', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b518d85f-a64b-4719-a012-369c385f6e9a', '612802', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6f8c8101-179f-4e03-8f13-ab9efd6f27a7', '612802', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d8f2f22c-61b0-471d-aaab-a4ce3f363c88', '612803', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2748ee26-2d10-41d0-9999-5cbcb034d5b2', '612804', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8f8fdcfa-7d50-419b-ac27-2f7161f0d150', '612804', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cab0c0f9-dbb3-4b10-b258-b7ac019dc209', '612901', 'Ariyalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('db6e54db-194f-4820-a074-a887483503b1', '612902', 'Ariyalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('28f27560-8928-42c2-86a4-b6fbb0e577c3', '612904', 'Ariyalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f6a4a52e-c46f-432d-ba28-f4620a3971f0', '612903', 'Ariyalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('dfe3ba70-ec5b-4345-b28c-2b2249186865', '613007', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e6edcbf3-9ee4-48b0-a3f6-c1dc7ecafd86', '613008', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('83d0bf45-9243-4ae3-8555-6fd56a4281b5', '613009', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5de437de-90b9-4d5d-b9bc-2cfe54aef033', '613010', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7095059a-21e8-4be0-98ba-dc5c5070277c', '613102', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ad87dd49-2ebc-4429-bbe1-cc324e54fc29', '613101', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('dbe9aae1-4d10-4fbf-93bf-87a5ccee925c', '613105', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f356d8c4-7505-4164-a8bb-95bf10df93ea', '613103', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7bb7ba9f-569a-43fa-be70-383cab8a469f', '613104', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d151f2af-6676-42f5-a34d-a9b953d849a9', '613201', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('104e5d68-0ffa-4a80-956e-284e7e000fac', '613202', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5872ba8b-9358-4cbd-ab74-b99321a6343e', '613203', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('451f82e7-1341-41ba-9f03-e046b3c80b15', '613204', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e38af40d-4502-4357-a828-20327713cf28', '613205', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fa616156-2c3d-4591-9ecc-6bc6e1a192a2', '613301', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1f98f5c3-baeb-4974-82cf-48849b63b6df', '613303', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('274e029c-fb82-444b-88e0-154de311c501', '613401', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fa872d50-1a30-4a27-ae12-8665a020fcc9', '613402', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6e4838a4-b3ee-45da-b9f6-b7b7ab54e2f5', '613403', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a38d5f1b-4e5f-42ff-8c07-8675b20b43a3', '613501', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f68ddcfe-797c-4ab1-95e4-85b75c9ee5d5', '613502', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('980891a7-9732-4535-817b-c9df22892886', '613504', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0caa4699-0af3-43e4-8ce5-c9e0570329f6', '613503', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c0ef571c-e871-454a-822e-a876ee64a1c6', '613601', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f9eaea7c-a0ee-4918-bd19-50df192631b2', '613602', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('62c1d3fd-135a-4bc8-8718-97d7c73c8d99', '613701', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('091064f2-740a-4d61-80bc-1fe8b46214f5', '613702', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8380b424-90c2-4a87-b3fa-eabe988d7b5a', '613702', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4ae10daa-1a8a-4af7-bfb7-cf95e71756ec', '613703', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('93a2d503-c19c-4f40-a5a3-e0827f11cbdc', '613704', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bacd9e59-5132-46c1-a7e1-c665ad6f2694', '613705', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9ff50aaf-cd5f-4aff-b552-4de94f4a4cc6', '614001', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('92075c69-2067-4341-a5d8-e960403f2a42', '614017', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a8a1c6c2-d556-4f35-b208-7d910a2965c4', '614017', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('892384fd-7427-4fc6-8f86-dd82a6cccde4', '614019', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('256430b9-8960-4dd6-878c-5941b0889bbc', '614019', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c1e168d9-7c59-41d2-b730-4d8a53bbad36', '614020', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b078a2d0-7faa-4cca-8d6b-3492bff418ac', '614013', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6a6e95ee-d9f5-4d18-8207-7cddd4ca31cf', '614016', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('dcac6b74-59a7-4ffc-88de-7601fd095635', '614014', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4ccf6115-7c2d-446d-b77c-fcefb43060d1', '614015', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('17e6b8ec-a27f-4f36-9413-f9d6b882ad68', '614015', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('be812b13-aa38-41a2-9ea0-08188f91154a', '614018', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('aa3fb94d-7894-4705-a35c-2b34c1ca5a46', '614101', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a3d000b0-f19e-4c61-b442-e545a7a0b8de', '614103', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('50f6e9d1-5b00-4f73-adfe-d4c92bfe8951', '614102', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('715c72eb-8475-467e-9255-30a6097b0120', '614201', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('95feddcf-07d9-47eb-8b70-d19a1212e8cb', '614208', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e0ac22e3-3257-4616-b026-5fc6a3d41b4d', '614208', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('22153c3d-4ede-4d7c-8265-03b2dbd9c82f', '614202', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ea892621-bf5d-44b9-94f1-14b8d2c72ec6', '614207', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('53a266e6-f5d0-4d8e-b5e7-c931d0360ff3', '614210', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1b70f9e7-1136-494a-914f-6857bee198b7', '614205', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b05e6729-53a0-444d-ba59-f54ac1055ebd', '614204', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('001b6be1-34b4-43ca-acde-e012458e5ee0', '614203', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4b9d5d57-b219-4663-9449-9690986347ec', '614206', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3668386a-5f77-4cf9-b8c5-6de4d9ecaead', '614211', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e83766f2-84f7-464e-87a4-f65a2ae481b4', '614301', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('54ca5db3-3c71-4756-87ea-bfb9d06802ec', '614302', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bb144715-3970-490e-98fc-7b8d49a9c03d', '614302', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b7564e3a-3748-437f-99da-207514b2afc1', '614303', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('18cc1acc-83b1-4fe4-975a-cc371ad4d930', '614401', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b8ba4ce3-6117-4a15-8755-516be780ea9c', '614402', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d566bf88-2a22-42cb-acc8-04649cb17005', '614404', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('43b440c8-52e0-428f-9bfc-87339209645d', '614403', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e6b40a3e-127e-4ca8-a5c6-7ab6b84f2d29', '614601', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f6d4add7-3324-4f2e-ba48-4ab8192b233b', '614602', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cc04ef1a-447e-43e9-803a-ea6907b170e2', '614612', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('936cde8b-d067-4c4d-b8e6-07cd99670354', '614614', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9a460304-4cfb-4f52-92bf-819822a430c2', '614613', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ca397e00-fe50-4378-ac5f-b3c70f3fdc69', '614615', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ac7463dd-c27c-40aa-beac-3028837e7946', '614616', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f60affd9-25eb-42a7-90c8-ff7b41808ec2', '614617', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('50458520-8cad-46e6-992f-dbee9e9bd024', '614618', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e29af8d4-168c-423d-9179-ca8a39623c73', '614619', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('016e0bb8-9d1b-4b51-81cf-73aabe40a8a4', '614620', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('444bce3e-3041-4f11-8cfa-c6dec40420c5', '614621', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('32a580b0-dc54-4ace-afff-59c63bcea747', '614622', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('29780c37-9c77-4d4e-be97-823be6a20d6a', '614623', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('838222d0-0fca-4689-82b1-109da59af613', '614624', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('db40698f-ad04-4d3d-93b1-8718e9591fa0', '614625', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('58dd3b65-a700-46dd-91e8-db80da255885', '614626', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d6dfadf8-4390-432c-8fc5-849576efa36b', '614628', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('505fe3cf-a7e8-41eb-afbe-23914fef5d18', '614629', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ec7a554b-441a-4055-8a97-ca5bac09cfc7', '614630', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1e69c8c1-c74f-4cd1-86bd-3b5f9ac67ca9', '614701', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8e816c35-23e0-4d1a-9fc1-c6a46c20951e', '614702', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('329ac123-a048-4162-a421-428871d26e43', '614703', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a218659c-56b9-4f87-ba67-8fba6dd1fe6d', '614705', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5ad930e0-9d61-4314-a4a3-ae8f9cad2f92', '614706', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7892b66c-4b2c-4c31-b7d4-898d476f8222', '614704', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('89d44ce3-a89b-425e-bf5d-040980df0278', '614704', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1bc1acaf-b038-4bc8-b9e4-000536120a39', '614708', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5ffd2068-62bd-4e6d-bbc0-41064a5dae3e', '614707', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7af5b383-2866-45cf-abaa-c6dfa3665fe5', '614710', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8a40d66a-f77f-4fc0-8317-bdff53813a8f', '614711', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7ffe20ff-dbbb-4121-bf38-1a8771709490', '614711', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8e32897c-61e2-4833-b36e-720df3be145a', '614713', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b404d165-fbbd-4439-a33b-f1c2d62e5bf4', '614712', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('19b0855e-407b-4cce-b01f-8bedc15a536e', '614714', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4f8c16ca-fc73-4a67-a1a4-52598531eaaa', '614715', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f3835242-f7bf-49a6-af27-986a72eb12b2', '614716', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('52a57a78-c2fa-4bac-b2d6-bf9128cf6262', '614716', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('de13f907-533d-4181-8d35-d54042ac7ee3', '614717', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('31a79f41-ef2b-4fdc-8c13-f5ec977bbad3', '614723', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e090a631-e135-4bbd-bc8c-4f560c4519a4', '614738', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e04e4d14-e46f-4b18-b72e-14234088b46e', '614801', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('20db474d-f254-4671-b339-c838d03f43fe', '614802', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('755f9729-7791-45fb-8193-8644ca1f7abf', '614803', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1a21b263-8110-49f6-88b1-57eccb838beb', '614804', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('78c61e30-e8d8-4f5a-874f-e5d89ae1d15a', '614805', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4362a791-aeae-4185-a282-ab70b62aee14', '614806', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c70ef027-447f-4c4e-93ff-81a76fed0b77', '614807', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5cee0a6b-12da-48d2-a0ab-8621efa36fd4', '614808', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a16c274a-364f-48ae-bbba-354c889cddb6', '614809', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('aae28f4e-31fc-4af6-9225-8c92d95c0731', '614810', 'Nagapattinam', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f2d194e4-50a3-4adf-9600-f9dfd975007e', '614901', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d279c44b-e115-498d-ae19-499fc2a2bed6', '614902', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d4fedb06-2618-4eb8-9412-2921b6dcef47', '614902', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('561fb59e-07a7-4247-963b-9a7e18600dc1', '614903', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c7903760-4084-44bc-940d-e30cea4f524d', '614903', 'Tiruvarur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('aae77288-bff9-469f-969c-2815dd315873', '614904', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bb821e26-0e68-4360-8691-a5b55f2ed831', '614905', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c3b424b4-4d29-4436-b9b7-d880b23038a8', '614906', 'Thanjavur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6ae23795-eea0-4873-8ee7-4f5657a2271f', '620022', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('89276f1f-f54d-43b3-b56c-d8f342335ab3', '620024', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('934f0714-9bf1-4ee2-b194-ffabb7a7401e', '620025', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8d1ab5c9-0187-4d10-95d4-9cf3a825db88', '621001', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4599129c-74eb-4c1b-abfe-83119c5d6a6d', '621002', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a217c682-bc0f-4521-9a7d-664d191b1bae', '621003', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5458ce27-ce01-467a-a157-ffe412e6bddd', '621004', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5684c247-9499-41ed-9441-dbfdd5d7eca4', '621005', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6a171973-3364-404a-bd2e-83e345b51047', '621007', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c010572c-07e1-4f1d-bca5-dfd26a9aba29', '621006', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('04d510f8-8bf2-41ff-a3eb-a5542697c4ab', '621008', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('557f3790-78b6-47e7-9eb5-876d9567a903', '621009', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('068bbfe8-fdc8-41cc-9bce-10ad7d7f7489', '621010', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a23efb21-fda4-4ef4-8ad5-a253e37f3cb4', '621011', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('47e72727-4ca0-4d3c-8667-33cb16d3c88c', '621012', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4ffc8662-9735-4092-a5db-3689127f3ac1', '621014', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5c7bfec5-f4a8-4d08-add8-1e790aa76bb3', '621102', 'Perambalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('23a2eec8-3bb4-4d71-9807-63215cdbff17', '621101', 'Perambalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ed615a68-439b-4b7f-9afb-5b7401849cc1', '621101', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d70fa060-5326-4ed4-8508-d08371fa1be8', '621103', 'Perambalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cd11bae7-5ef4-4395-9aff-3af997f89ffd', '621105', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('dbe1eea0-4489-45d0-8ad2-7736983ee976', '621106', 'Perambalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7ee9fcda-21a6-4f8f-b551-ed1b61298ea5', '621104', 'Perambalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c96c7185-b923-4abc-88b7-884cd4260d46', '621104', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3cd94375-9189-46fe-a961-8389208ec197', '621107', 'Perambalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('85de6711-28d6-4607-9dbf-264bf809ad4b', '621108', 'Perambalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('66cc84b1-01ec-4509-b5b9-f7a8a823bc17', '621109', 'Perambalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('46eccfbe-c321-4aad-a7fc-68161af0f74b', '621110', 'Perambalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('639bcd05-5aef-49ce-954b-a8687769546d', '621110', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('dd2db20f-c9f6-4bbb-a7d0-f7685f4b5781', '621110', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4c1c8d1c-7f5d-4e89-8a9c-803d00a8c4ee', '621111', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('60ddfc14-b55f-466d-9e7d-deae3efecf9a', '621112', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c6922b2c-8942-4f27-85fa-35794032f827', '621113', 'Perambalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6bb3bc29-a0f5-4d61-b7b5-8919c9150b82', '621116', 'Perambalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e4f32090-687b-4d4a-a264-c789b57f6e23', '621114', 'Perambalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('345a8f60-a395-4dd9-9830-dd17ea5c72ab', '621115', 'Perambalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('11b19547-6664-48a2-9433-395d2156be8f', '621117', 'Perambalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('483d42fc-b9a7-4296-8dee-f766fdd2c206', '621118', 'Perambalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1a036a7f-c979-4daf-8639-55b08631d3c6', '621133', 'Perambalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('457e8706-3f7d-4590-a37e-263ccbd8ef23', '621203', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a48a1810-8e39-4b06-915e-db491b8c7465', '621202', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('af74e917-a46f-4bea-a62a-8967e2778c73', '621204', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('88c94d37-06bc-4506-b4e1-2c20cd161a78', '621206', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('29875c28-157f-4ab3-b00f-97cc8f943677', '621205', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3fccbc13-9c40-455c-b9c3-85bafd288a7a', '621209', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fb29711d-a42a-443c-ac5b-9dbebbf8cd3e', '621208', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c579a5ff-f5ef-4e0b-a303-e858ae515588', '621207', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e1130cc7-d286-47e5-ad1e-8a76a2cbb6c3', '621210', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cd30dae3-0669-4659-8e8c-c7b669a3d9cf', '621211', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('207c7ad4-e719-47f2-ae28-3fe9594a3394', '621212', 'Perambalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('02ce8d82-0db2-4e05-879f-65f653acbc0a', '621214', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('02db67e1-beba-470b-983b-11d58c8e2931', '621213', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('37c267b7-bfe0-4e65-a49d-58e25798e133', '621215', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('286e53ef-f20a-4c07-96bb-4cd1dbe188db', '621215', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ad9845b1-0a41-4cec-a013-32831ba1743d', '621216', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9c882c05-4cf0-4bc3-959c-a596515c6cfd', '621218', 'Ariyalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2c071c3a-d67d-4508-ad34-4cc0fdcfeee4', '621218', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9f913df2-efee-4c31-99ad-3d03fb4f45f6', '621217', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5b6a309a-a26c-4dfd-a4c5-9e7aee945c69', '621219', 'Perambalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4a9299d7-02d0-408d-aa04-a861f1789148', '621220', 'Perambalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0e753e61-3e76-4e80-9182-7b4fb148217a', '621301', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f4e67449-a9ca-4e55-a07a-94731b570e77', '621302', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4d0a6a11-ca97-4bf1-9e77-89fcf023c57b', '621305', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a09c18cb-f41d-4c93-8238-582cd411dbef', '621305', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fd506b2c-dbeb-477e-8bef-9a20ce2b16a9', '621306', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c0c91210-80da-45b9-9135-9b3adc1e38ad', '621306', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('06244667-6284-47c5-a00d-c024ac713a40', '621307', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0ae74d92-e65d-4593-9aab-3c9e8bc5944e', '621308', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('834d45fa-2f3e-43eb-b5df-b080aa19cce3', '621308', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8747478e-17ff-4012-80c8-f19459054b44', '621308', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cf2b2309-a777-401c-94ee-d23f897946ff', '621310', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d761f321-c0bf-438f-a8e8-5e9744e9cde3', '621311', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ee369be4-e6b2-4bfe-88f3-a12a5b672cf4', '621311', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f9c8a632-6fad-432f-a27b-6e6608d81a96', '621312', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0e4a5306-6a52-4d3e-80a4-0e07f1edcf11', '621312', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('14cd3841-18e2-4e2e-8ec3-eef0cb0a6ddf', '621313', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ea48b2eb-40ef-42ed-82d4-6e3c51628f5a', '621314', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('df9f8a12-f766-4239-8e5c-a079f9b0e31f', '621315', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a021b037-3cdd-4e8e-8c14-565288bab08c', '621315', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('aa621fae-bc25-4db3-84f8-37bcab626379', '621316', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('62c15fb9-0ce3-4bd0-ba9f-4951341f066c', '621601', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('37fc88ed-5573-435d-9bff-a983a93aeaa7', '621651', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('dce9152c-adef-48f2-9514-4142c6fc4584', '621651', 'Ariyalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e0065511-3993-4d25-b6a1-38cc0a295892', '621652', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('00eae449-8d83-4b2d-b221-67fb17579351', '621653', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('341bdf8d-9fa6-4ffa-93fa-2abcfc3bd932', '621653', 'Ariyalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a9fd08ee-803d-4e6a-be6c-9bbf57977703', '621701', 'Ariyalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ba6474f8-414f-4758-add8-aeb19a89d03f', '621703', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5c101dc3-f487-42b7-ac1a-2a61fb1e0ef2', '621702', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0691be19-ee15-45e2-bc0f-6cf040cf802a', '621706', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7542c238-31f1-44a1-8038-513f8feac78d', '621707', 'Ariyalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('28c2b67a-55a3-4427-be75-6fbf5d689836', '621708', 'Perambalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2fbebe52-f5af-4ba3-8514-38f1dca6a339', '621709', 'Ariyalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6a34d004-8f8e-481f-9b68-1cb2b8054b4b', '621710', 'Ariyalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e2e79fd7-756e-4c75-a768-8cedec8c34f6', '621711', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fde0d39e-a51c-4175-94af-604997dc1f74', '621712', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b74ab47e-67be-4c98-b0f4-cfa2cc10f30e', '621713', 'Ariyalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('11177464-d7e8-4a1e-903f-2258c745b650', '621713', 'Perambalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('346ed231-398e-43ec-86a2-78d833ce4ed0', '621714', 'Ariyalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cb4f1bbd-8696-4dbb-9528-328df9e7fd46', '621716', 'Perambalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cc371382-2f17-4647-908a-a45f512e5509', '621715', 'Ariyalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0f8cd94b-414a-4985-ae2b-589357f46e64', '621715', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('32a35e06-9b8a-4d04-b941-bc141c3bfdb6', '621717', 'Perambalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8e7a1cb8-beb4-4bc9-bb42-0a3131c7f756', '621718', 'Ariyalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6943b169-db8a-440f-96f7-1e2b0af83b9f', '621719', 'Ariyalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('dc9977ec-688b-486d-a87a-a88a4ae4fab0', '621722', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c687f45a-23b3-4130-87a0-65d212500924', '621729', 'Ariyalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('dc8331fd-c8aa-4a30-86ea-9a90c84ae02a', '621730', 'Ariyalur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('614edb39-c15c-4724-aaed-0107efb6993c', '622005', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a3ea012c-c95c-4001-aa7e-da8f05384a94', '622004', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d3261a69-531b-410c-b448-e5437ae06287', '622101', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('28a9b5ea-4d5a-489a-a513-e3b590697c84', '622102', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2fb076db-311e-4eb3-8379-f78f573eb0ac', '622103', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('00567e9a-878d-4409-8dc9-d5d677e7d7d7', '622104', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c1cc4247-bba7-40a5-9a15-1ab16f70ac52', '622201', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f320b11f-347f-4463-b6c4-8169bf9d830e', '622202', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('da6f0b26-b879-43fe-b3e0-217f6bd0c243', '622203', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a9cb75d9-2d4f-47a7-a5de-1c96309641ed', '622204', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9ef1011d-f438-4a69-a37d-16c8431f329d', '622209', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('58fa7360-757c-402b-a571-ebdb7b2d71a5', '622301', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('143dc267-b847-4a81-bfe0-3b00ae717f05', '622303', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('395ce91b-f597-417e-8367-d2fd4db38b38', '622302', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8f5a456b-b856-4b59-9e58-d0d135bf6848', '622304', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('22c0701b-ea88-4eed-84d8-fd9c10cf4997', '622401', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ecd75cbb-03d6-4a67-8491-dd94fe0971e0', '622402', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0da522af-ecde-4a6c-b196-a6f51f610293', '622403', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e96c1c7f-85eb-442a-93c8-c407a82ee904', '622404', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('280cc951-ce42-4c10-be98-11660ddf9722', '622407', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('db689e09-974f-4f68-86b8-6bd8ba78e9a3', '622408', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('858d79cd-f948-4a15-8455-cadb46e2bd51', '622409', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fce9c501-e709-4ac8-a4a0-810cb263edfa', '622411', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b70fe6c5-10d0-468c-b6e2-18858329c5db', '622412', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6b473d93-0e0a-4381-9bcb-0756d59020d8', '622422', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6e306102-b082-4779-836f-e76f274f9d1a', '622502', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('24468105-cc31-4d02-b74a-886b0cb4ecf6', '622501', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('66999ea5-7b4f-4ee3-9463-8754066b932d', '622503', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3e2ca087-ec4d-47da-a0d3-f05faafcbfa4', '622504', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0df8ec37-45e3-49e9-884f-321bc322f43b', '622505', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5cf16ee3-6eb1-4082-84b8-1cf1c378b1a2', '622506', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('26ed43e4-5910-4aaf-a745-fcda6b12170a', '622507', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c41fd2ad-b676-4d89-a95a-9f5fb5f817ec', '622515', 'Pudukkottai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('db636668-b486-43bf-81e5-243815dbc4dc', '623115', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('86e73522-79e1-4136-9021-b6333eebe385', '623120', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1555313f-79b5-4218-ae0e-cf497904b321', '623135', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e811ddce-b642-4820-9592-19a4da3cb39c', '623308', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('acd0df96-1d0a-4cbe-a2d2-83bddab09fba', '623315', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0a5d4545-3d1c-4be3-b648-f26c79b150e8', '623402', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('64d634d9-43de-4f57-b918-97fdd46c83bc', '623402', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9e867e26-12ab-455d-974f-3269923e00c8', '623401', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3a67507a-709f-4d49-bd20-08afdcee5de8', '623401', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1872fa0e-2931-4f09-b409-2f43a78e0fd0', '623403', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8f17c5f9-c74b-4e3e-981f-7a3bd40a792b', '623404', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fb0fedc7-5a1a-4420-a26a-d26cbb236c71', '623406', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ad0d3ad0-1e81-45d9-ad93-93a910a8fac8', '623407', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('39bb4d9e-fc52-466b-b07c-a65ce11c4b8b', '623409', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e3fa6bbf-bb64-4d55-a25a-24dabac33cf4', '623504', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('394d1769-471b-4f25-8613-fc911a25af7c', '623503', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4adcde88-44d0-4a23-9273-4bf9df5c4655', '623512', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('38396960-f983-4442-acd0-a28b70f60ca7', '623513', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7a0d703d-39a6-4fcb-8241-3cb52cc882f8', '623514', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a5ed16f5-057c-44d4-8296-5954d0f03fe8', '623515', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('915bcaa6-6ea9-4469-9317-ba2cd2229c34', '623516', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2f2d7745-be8e-4225-90c5-7ef572d2443a', '623517', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6cba45f6-fe43-439e-b9b8-ee032b203d42', '623518', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('be3362b4-aa7a-4a03-b593-56a97178f321', '623519', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f7d64aef-ddc3-4f37-8955-eb7c894b4bcc', '623520', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6fc76789-3de9-4bbf-b449-02c34d627f3d', '623521', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e1818fc3-d7ab-412c-a8e8-b05b2d7c9865', '623523', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('aaec6fee-288d-449b-9201-ca0e4b36b863', '623524', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9555987b-1465-46c6-ac49-622e7c83dfda', '623522', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('761b75b9-ce31-49a1-be03-0c7573b0cb81', '623525', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c0359a01-2edc-4c5f-baf7-551e8341412d', '623528', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('72a1cc3d-ddd3-421e-a54e-c412871c9526', '623532', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c0a7cbd7-5dcf-4bee-bd81-d85b35b8dace', '623527', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7d992cda-3c05-4d27-b950-525e66308f42', '623529', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d1424cd1-8b7a-4de8-a3e3-b7ca2bbc991e', '623531', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('57c68c4b-bd0b-4399-9a2e-e18d97c16403', '623533', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1f1928d6-861b-42fe-b090-a15913b670e5', '623530', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6415489f-05cc-438f-b780-47997121f565', '623526', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e14004d2-fc28-44c6-bc75-bc6d468ea055', '623534', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f8c2e099-d4d7-4ce9-aa48-4daae636617b', '623536', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('895a402e-e4ca-4388-a021-1c116ed1a740', '623537', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ee33e02d-5654-4847-a54b-a96c2d3677b1', '623538', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9069a151-cc76-40a9-aac4-d36477869db1', '623566', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7b18a29d-5cb4-4186-a595-c7686f59d71e', '623601', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('304561cb-17e0-4792-ad32-67ab48a81f25', '623603', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c5083dbd-ca10-4ffa-872d-19fdc648f990', '623604', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('75d9f0ec-8c9d-4fe2-b504-88b3126f6fc6', '623605', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('901a2e2a-af82-4940-b1b6-56258892f7f1', '623608', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1ac1316a-68bf-4410-9a19-92c62d4fd628', '623701', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('355d414b-dda4-4ab9-8c5c-76fe1fd6e677', '623701', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5b3ef5aa-73e2-433e-b8ae-66655ca71a30', '623703', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('95b286b1-dbc3-48ef-a0cb-abed282c3bb9', '623705', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('46def9aa-6e9c-4985-a767-8bf70d94ef34', '623706', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('803a6104-ac6f-4586-8a20-93e31a18c490', '623707', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('aeacf6ff-7f99-438d-b609-2cb81df623bb', '623708', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('67193c3e-a07c-41ef-a019-75f9399533dc', '623712', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ad569aa8-1ea0-4435-b22d-90ff98dcdaa5', '623711', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('71a3d68a-ee8a-4b7d-b777-08c1a18806fe', '623704', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('024b3915-c0ae-4734-a330-5d8412109320', '623806', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('59de024c-401b-4478-aa80-60b7d587be5c', '624005', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7c84beb3-1cf4-4aa6-b953-851648b24a6f', '624004', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bde3c245-1a0c-4717-9827-5480c79a877f', '624101', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d28230f8-d021-43e4-bcb6-6ed1982869d1', '624103', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cb823b14-593e-4ac7-ab9d-8c24c7ba34a5', '624201', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('693c262a-d5ee-46ae-9923-1d5bbab57fa7', '624202', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('23c8e4f6-dcce-4871-a034-8e32ac7d5f29', '624210', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1ae9b6fb-4e76-43ac-a28d-abe25ca7a62e', '624211', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('12efb3c3-7045-489b-be6b-9a37c3c59406', '624208', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5dd820ba-bf0a-4f0e-a16a-dc2f993f4f53', '624206', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9253b1e2-f4fb-454e-a92d-bd6f3fa4354c', '624204', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('79ec90b6-dbd6-4b4c-b057-a0792eb92347', '624212', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f8823704-af6f-46bf-9367-871c331a897d', '624215', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c3ee61ba-6d3a-4c02-8a3b-743d9d57abcb', '624216', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8678d76f-6721-4efd-a256-95cf553e38ae', '624220', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ecc863d9-87cd-4074-aa23-6e41a4e1f556', '624219', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b8683edf-7a73-454b-9bf2-34b4fdd813ea', '624301', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('93636230-1982-4ede-ae11-d61344944116', '624302', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ef4c1257-ad39-4383-aad3-bbb2d2156cb8', '624303', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('22da8e76-1ab6-4fa0-8da0-41318d2e98a8', '624307', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9e637d4d-737e-4d6d-9949-7caf897e8b49', '624308', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4bf0c76d-4e40-4bf8-93b1-a8edbe8fd4df', '624306', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7fa4bf9b-9546-43c1-8f88-e2d1a161b190', '624304', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0f579960-de84-4b3b-ab81-428300f27bd9', '624402', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0d358fbc-b79a-4780-8c27-1040397aa32c', '624401', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e9b1dcb9-1ede-489c-8825-4edd68fd3a70', '624403', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7f93c54f-6dfe-493a-b40c-a210d19cede4', '624601', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3bb99e8f-c8ff-4f66-a6ee-7c1b4dc15a2f', '624610', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2fc30060-1cd5-4312-af11-105badb8edbf', '624612', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b720d1ab-4091-467c-bb90-f213e9d42d68', '624613', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7873fd2d-578a-4376-860d-9adfec68d0f9', '624615', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c024ec17-db30-49c0-971c-3c71d7aa931e', '624614', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4fb255db-c49a-40c8-b143-e0e69a120c0d', '624616', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('50521253-8793-4ffc-98ad-3b52b4d76864', '624617', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cd43bfe0-fc52-461f-a9c2-5f38a54216a3', '624619', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8c3c0cb8-1454-4091-b432-0dcee97d8c9b', '624618', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e1a68a20-bc21-48c5-af28-1226a0069dc1', '624620', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1e0bc79f-fcdc-4a2a-b560-c52a51800099', '624621', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ccd4419a-3bcc-45cf-bd82-dd5e79a901e2', '624622', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('85549656-3501-4ff2-94c0-a389bce03b89', '624622', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bb9ee82f-d1f0-4ff6-a7cb-bb3b57a6acb4', '624701', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7048d134-6b1f-4c5f-9830-fe72f4f5c15d', '624703', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5884e1c7-0dce-4535-99d7-f069b6140cb9', '624702', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8e237a46-6cb0-4974-8ed4-4801f4592fce', '624704', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8413919a-5c63-4380-b6bf-aead51765e45', '624705', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f36c3730-9531-4a1e-beef-0470bddf0821', '624706', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('59318ccd-5db9-449a-966e-0d7e42978b1c', '624707', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0c403bfe-aebc-42a4-9e33-5b98f8dd33ea', '624709', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bda20df8-b535-4ba2-9125-8d6f5aac6eaa', '624708', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6267a426-9ad1-4b6f-b6f6-3d8b6e277d02', '624710', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4298dd36-51f2-426c-b951-84dedc09b19f', '624711', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4f961cb1-0613-4a29-b259-4c10df95d990', '624712', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('73b023b8-590d-4e5a-aa92-dc70af342c31', '624801', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('276fca0f-7f5d-4803-9740-91c23fad54b3', '624802', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d8d4f1bd-6e06-4766-a7fc-b7c59beb92b3', '625022', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8bfbbcd8-3fe7-4647-aed7-e10de16b1ade', '625023', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3db6f780-b341-4a27-9a7c-e4d56d0e5120', '625101', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ea8372bc-284f-4023-abc0-3e58213e0cfe', '625102', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('162df969-09cb-4bb4-a2f7-121376c6c12b', '625103', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8b98521a-1332-4145-9cf9-b7253715334e', '625106', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5ac3f2fb-64c4-4fb0-b260-358e6eda6579', '625105', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('35b2cc77-7025-42dd-afb4-e9bfcefb4d9c', '625104', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e1085752-7b52-40e1-b5dc-665b80528a62', '625107', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('03664e5b-d476-4d7c-b45f-ab8ea1a36657', '625108', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fd8e5b69-39e8-443f-8eba-3a6c51a84a08', '625109', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1ed78cf1-b066-4796-83b6-cfec82da9839', '625110', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7e55c350-6fb9-466c-8e97-5317ca102788', '625122', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6a585b26-77e0-460f-a647-b7e28b01db8a', '625501', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('68418c52-c828-47fe-8a14-0df40d3fdcf7', '625503', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('581e6f11-35bb-4007-848f-a51c52876fe8', '625512', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('aa1e3fe7-a033-4391-84fc-ee3ceadda1f5', '625513', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c0221ba0-311b-47ac-a1e8-840cebf34b29', '625514', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e69ae3a7-0a8c-481f-a0a5-3612c9231926', '625515', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c2723134-41d9-4d02-9f5b-0185d000ed87', '625516', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0ddde16f-2fb3-4642-9afd-b158b81bff1f', '625517', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('978b8ac3-a73c-488d-a4c0-bc71ecbfb0f7', '625518', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('dfc36291-3437-47be-bee0-86efb6d3a0fc', '625519', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2368931f-26d9-4860-b9a7-2715777b4cc2', '625520', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a065fc60-49cc-43d3-9489-fedd784d2430', '625521', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c2a4edce-c733-4dd5-b756-402778226fae', '625522', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('04d8ae2f-9586-437d-a645-3c391908b054', '625524', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4de7a37b-143c-4930-9d5c-fe5389530f3d', '625523', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3abcc7de-f184-489a-a04f-23ce4613fb2d', '625527', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7de7e0c8-d53b-4b85-8a7d-115694e13334', '625527', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f77ec8fb-84ac-40d9-9260-0c2ebb5ee05e', '625525', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ff8cc2ff-cb5e-4ee7-8889-67a9463b3688', '625526', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d53e10c7-86d3-414f-8ec8-86999de4d34b', '625528', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fb30d4b5-8848-4589-97b8-e2523e90c8f7', '625529', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('48003ddd-943e-4369-861d-70aa727e4fc1', '625530', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bfdd99ca-224f-450b-9d25-0df215b88553', '625531', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8c1fb8fa-a009-47bf-b558-5fc59501fe66', '625532', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cb893360-b7fd-4632-8461-b92a69ae047e', '625533', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5b7c7210-f434-48c7-9acb-675ce86fbe0b', '625534', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6219cd36-9ae1-4e95-ab3c-54f1aeee5aab', '625535', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cd7813c9-a0c6-4652-ae72-675d5026da7c', '625536', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f22af57a-5fab-4feb-8ed4-f2865a275643', '625537', 'Madurai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9eaae821-04fe-4d46-902b-75d36c783035', '625538', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f808e745-9d95-4358-897c-a34a8c210f68', '625540', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fad2fce1-2818-415d-930d-3c1b074b16a9', '625556', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('75f07691-c61e-4323-b2cf-360c997db18b', '625562', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2441d26b-9c97-4934-8fc6-e8ffee339f9d', '625579', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('62948fdc-b58b-41f8-82b7-08783bf00cbe', '625582', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('94e7aecc-71b5-48d6-8286-bd0c01170098', '625601', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5dc770b7-96b9-4b01-bd6f-627682c4de95', '625602', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('46289326-efdd-4115-8c63-2b45eb2049ef', '625603', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4ec87aeb-2dc5-4b2e-9910-82c6c0bc51cb', '625604', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bbe6d3d4-d3dc-4bf3-a0f1-b6d3ca5a0430', '625605', 'Theni', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7170ce8f-4816-40b5-bbd9-39844d3f7747', '626003', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('85245951-a5ae-46a1-a8bd-0f161882d9ca', '626004', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4db5dd28-8814-48bb-9f57-ba7fb2a03866', '626005', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e9cafd2a-61c1-4f41-a3a5-df4f56ceef3c', '626101', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('28e734ea-716f-4b14-8c67-d1bd412c3e57', '626102', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c2a414cf-e8b3-47c3-b085-1a9e36ba42bd', '626104', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ea984848-ab1b-496f-ba50-e95d4075efa1', '626103', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ec9ac18e-6b6c-45d9-b525-a3a2aee3e8f2', '626105', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0eabe15e-237e-4602-b90f-ef17cb7a4cac', '626106', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a2b148d6-5718-4635-a64a-b55d313489a7', '626107', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('088c7faa-9706-4bfe-b429-67a996cfe2d2', '626108', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2dcc667e-2b17-4fe6-a13e-c9cc0a05634f', '626109', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9350cd18-2106-46b0-9ffa-24ce68e77924', '626110', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0bfad64a-8a96-40d1-8087-1de70b3d906a', '626111', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('999b589b-e283-41ae-a257-c85e740ab841', '626112', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1de265de-f455-4d4e-bb4f-e4106af548ce', '626113', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f7269cb7-b68d-4880-98a4-6b4af1bac04f', '626114', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c47b0633-a21e-40b2-bb4f-fc4540029243', '626115', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fd609539-19c8-44d6-a720-a0769b062154', '626116', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4c68e115-bbcc-405b-9010-adbf601fe131', '626117', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e5ff9abe-4190-4087-a4d6-951960d21a00', '626119', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('81ee6c70-17f6-41f8-9df2-b2e79f40ef3b', '626118', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5c18d800-a17d-4977-acd1-70ca2abce912', '626121', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0f648362-3c40-46f4-a013-3d90843eeea4', '626122', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('812da928-d34f-431f-91e2-f5ced5cf3907', '626123', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2de72db0-6f0e-4a76-a114-7fc2b24391bc', '626124', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('96ef06b5-be15-4510-b6c6-e6bc53e44e47', '626125', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6fb069c6-b106-413e-8da6-7ae3fc4ac214', '626126', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('87febf13-51ca-4aac-8ac1-dea3565d865b', '626127', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fa17bac0-868e-4dc2-aec8-1f6bbe699e48', '626129', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0ecc0c99-c4d8-43a4-aeda-46c12d1c70d7', '626128', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1ef9ecbb-549a-47e5-9de7-4f996b1b8681', '626130', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2a11e014-dcff-435a-a854-5f26bf793cb6', '626131', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4c44a2eb-34b7-49b3-88af-9800b5743785', '626132', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('eeeb56d5-f3e7-4093-b7ce-be572a19b903', '626133', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f3fcb40b-ae98-4d16-a77b-9210baa5666b', '626134', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a77a8905-ad78-4eec-b675-f42746366f0c', '626136', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('772f8687-26c1-4fb8-b0d0-5308796a1a1d', '626135', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f3adf694-e371-450a-9034-215ac32b49fd', '626137', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('56a4ade2-8ade-42ff-b312-6a176a1bdae2', '626138', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ef5afb49-d2c7-4097-bd09-4bb642fa70f3', '626139', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b92f0e01-32d2-41b4-b4b9-7b7bfef324bf', '626140', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ebddaa62-3d9d-43a9-b4cf-09a2453a2c9d', '626141', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('02158b66-f0f1-49f6-806f-40f320a0e694', '626142', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('11747a3e-77c9-44af-80c1-bfcc12098170', '626149', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d6b64082-8172-4494-ba37-997e11eb1e7f', '626188', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('274334ab-3e9f-4778-bcdc-43bb793aa2de', '626189', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('00cf50c1-05cb-4821-868e-357c09de448c', '626202', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('484790b8-f524-48e6-a28c-a2a302453443', '626202', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b8fe4593-aed8-405a-935e-8703e09ac862', '626201', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('58850644-0580-4d62-ac72-e30d8cd3a05d', '626203', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('55b46f70-e726-484a-8240-f8af54e66371', '626205', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7745e880-c53e-4f23-9e19-234ec6cd32c3', '626205', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('dd8df014-25a2-442e-8a84-a8211c349e7d', '626204', 'Virudhunagar', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cbebc0cf-a8b5-4988-acbb-dc7575170b18', '627011', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('dc5bd834-f8eb-438c-b5ad-2a178b21e754', '627101', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e713cc60-efd1-40e8-8131-5d9a6b03b105', '627103', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2b7aefe7-7bae-41e8-b89c-ba172b7ec199', '627102', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('efb7edd6-85c3-4261-bc08-a486609d5de3', '627104', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8ef9a47c-b59b-422e-8a0f-1fe17465ea78', '627105', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cef660be-b429-4ebb-ad96-01f406877179', '627106', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6c1d3c22-9a62-4b0b-b322-de32c2b895e4', '627109', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('be1e459d-37a4-4eae-abd1-d215c499c4e5', '627107', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0afb7992-616b-4e04-b6b2-38ccebf16e5c', '627108', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8d49f3f4-6f20-49a2-84f5-0c511b5c86ea', '627110', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0f4b7f99-c7b7-42b3-a9a1-8a5d10e69bb2', '627112', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9ea4964a-da4f-4476-8935-b70cb036d287', '627111', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1eb02242-83c6-4763-89b9-b49a01baf92b', '627113', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2bd3a3bb-2690-4431-a7b7-9f3797f59925', '627114', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f6ef1751-d780-463f-9b26-11b83b1ddd47', '627115', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e5108b9f-a074-4343-97b4-7835b0e5e190', '627116', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4f0ae646-da40-4c75-8924-d2601104937d', '627117', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f2a17ea0-f3d8-4e01-9958-effaee1c7bf0', '627119', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('09f97957-406d-41a4-a017-58b8b64ea042', '627118', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e9f5caab-6a5f-46ad-aeb8-61657c312c01', '627120', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('adfb4908-66b6-44ea-a468-09bd921f41dd', '627127', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b8fe6e5c-a0d4-409d-a2bc-4cb0bde27389', '627131', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ae1c9144-ed8c-4325-a945-8f50299b148b', '627133', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3ce83cab-1b40-413e-a6cc-78aeba44e660', '627151', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a6d273fa-d89a-4cfc-b5dc-191de0f11e64', '627152', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6dbe5e87-7173-4b0c-8604-606d8a7bf5d8', '627201', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2d9900f3-4910-4924-8058-8196195cbe2f', '627202', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('637ec79b-925c-4a6b-a806-9735afca2c55', '627351', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('01bc339b-6d89-4b43-8787-ff909ae30a34', '627352', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f96d35b2-6bd0-47d8-995d-e6d4309ddb0a', '627353', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b90e75a1-9054-4761-89ac-b426621e5142', '627355', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c047a120-07c0-458f-b7bb-f2383a3c4393', '627354', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('75b39d20-36ef-47c8-9020-0dcde5cc8052', '627358', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('84db8f36-7f3e-4cbe-8434-b33b44266ae1', '627356', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a8d7305b-15a3-487b-b370-999823bcb8f3', '627357', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c33bd24e-7c87-43a1-a2c6-8c306e8dc07c', '627359', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f1714431-7100-4b9c-9142-f8c10fb92450', '627401', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('33e452f2-0ff6-494e-b0ed-e9bdc66f1fdf', '627412', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('89159dd4-2a85-4ffe-a345-05b4a5c96621', '627413', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('880e17e5-cda9-4718-a964-fc2b73d6c75e', '627415', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('eb91ae06-bc41-489a-b30f-b4d29b1d55bb', '627417', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b0c4f6e4-dbcd-49cc-b570-c66bdacff614', '627414', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2838f05f-2adb-4690-ac8e-38513d031089', '627418', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('728766f5-c73f-4cea-a6a5-9860c5f43eb3', '627416', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e0023235-6548-4e2e-8416-b64b93a93d82', '627420', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('060a3559-a4c0-4051-b597-c1b089a772d5', '627421', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('06247763-4a6e-4f92-8dbc-b8752013bb6f', '627422', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4a5e2aef-df92-49dc-86fa-15e0e3be4651', '627423', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('98fd7b27-448d-4bbc-aee6-734d32e12b03', '627426', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c6d45841-2aff-4bf6-aeac-bb5e7394157e', '627425', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4cb791f3-ac6e-42ee-8197-828e246cedcb', '627424', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('66f0f3e1-b5eb-42b7-8bbe-c1b5f4e8e058', '627428', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7da814fc-66e4-4c2b-84d3-24d4309ab97a', '627427', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1ac4d460-82dd-4bb4-852f-4347d39bee45', '627451', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('162cfb42-8275-44fa-b5ab-f09bc012d009', '627452', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c7579713-ec55-449e-a5c4-9d38ff8aa0a3', '627453', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b57f46cb-67f0-4810-afc7-30ea40a94573', '627501', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cc8d1891-cd09-430c-a3ca-281d7c63f51a', '627502', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3f24fdcc-d54c-4543-86e7-0b5b422c1d39', '627601', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('038b16fa-5859-4c7e-8d5a-b9170607ef8c', '627602', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c048d13f-972e-4719-a9a5-3b2e4d902fb4', '627603', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('086d7e91-f19f-4b43-88ec-558280cd0183', '627604', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('91a5d423-c35c-46f5-86be-a1c9a25522ed', '627651', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6ac74f7f-dc67-4262-87b2-8dc14d861d3c', '627652', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2e7ed26e-c65d-4566-b932-e22094089ec7', '627654', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('71b00c5f-41f7-4b6f-96ae-55a2bec3c346', '627657', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1a48eab2-1deb-495a-9fc8-5f688ca94754', '627659', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e9ada2dd-3060-4980-bd75-6cf5a3c564b1', '627713', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('012cbb24-b0ef-4514-b0a0-b555b12a1db9', '627719', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4f5a3b8f-3132-4e35-a4bf-58a911e5ce5d', '627751', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1509252b-799d-465a-bea4-b6732ff46655', '627754', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e408b199-87ec-4ab7-911c-78f9a0206c3b', '627753', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('13f28029-9b53-47da-bcb8-839ec20cd7ca', '627755', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f6c44985-38a4-4cd0-aeef-200234c7f2df', '627756', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('636feb8f-6b77-4401-8880-7b73ac6f8e53', '627757', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('06a11cc6-d775-4fcc-a57f-d3dfb80cb661', '627758', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('248cba1b-011d-438d-90e7-e84eab07cd3a', '627758', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b573fd47-abad-48cd-ba23-1dac6771b678', '627760', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b12988f7-a789-4222-b138-e0f7a6d88e39', '627759', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('96a08cfb-a9d8-4cbc-ae50-9eb303493c7e', '627761', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('da0cb68c-e762-421e-a696-46b2647ddf52', '627764', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('117bf07f-ab6e-43d1-8754-bdc33d557a8a', '627802', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9152dd72-c126-46ce-a641-cd3af6536bb5', '627803', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ab184e77-89e7-42c2-99bb-84cf4ad25901', '627805', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('09927e40-97ba-49a6-8af1-75713535bfa9', '627804', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('08295f6f-2021-4199-9c30-83bfd261680a', '627806', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ff226946-550d-42a5-a950-5397198399a3', '627809', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2624855e-5cfc-48f2-a6b8-f8c37c29323b', '627808', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8406d332-7b2d-4111-820e-02c68bbd3d89', '627807', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('80f1e774-aa80-46b3-971e-6396c8176a61', '627811', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0caae3f4-741c-428c-aedc-4f4b599cd950', '627813', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('884349e0-18fc-4efc-99d9-1998975222e0', '627812', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6c2616aa-97e5-4bf8-9e60-c33b7b8b5d64', '627814', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1d9af873-9118-4d95-80c8-5b2ad98ef6ea', '627818', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0f3a5800-fcd6-43f2-819a-4b4e3e047e93', '627851', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d900f115-394a-4a86-bf63-eda290ba0e10', '627852', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1abd48e8-16fc-4387-8064-658c079d4b00', '627853', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a150d58a-0da9-487d-8894-82ebf9744f24', '627855', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('943cbb62-d13f-4381-a704-cc38dc49c48e', '627855', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('58a79cdc-24d8-420f-9258-03495238f431', '627854', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1a4e9840-c1e8-4507-bc12-d883b4e14570', '627856', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8cadb645-478a-4805-8e5e-14f9e0fc99b2', '627857', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9700a95a-9cd4-4708-a322-3b68944ef446', '627858', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ef780ad8-f12b-4524-81ea-6e396bba17ca', '627859', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3e00dddd-7829-463d-9ac6-a2608c0ee1d5', '627860', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('36a856c4-8b9d-40a3-9a66-951222df164e', '628001', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('00a4303b-7689-4c9a-a885-654ac39e7b89', '628002', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cab89fca-51d8-4be4-a101-bf9034310b5b', '628004', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('be457ad5-263f-4990-a277-e32351d9f983', '628003', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1c42b18a-770e-4d24-b689-acf723d09add', '628005', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('aef328d7-1915-4e52-9a19-744cf29f2b2c', '628006', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7da72572-bb86-4ea1-80b8-3eaa1d29d30e', '628007', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7d7e2264-6dc3-4c05-a35c-c8827475f68e', '628008', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('95188c30-70c2-4b1c-abfe-c02b1e465c1e', '628101', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0ee5bf31-81a2-4611-a5d8-1f09a4d99cb2', '628102', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b1c91cd6-46e7-4da7-b604-7985bb971a4e', '628103', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('345c72f7-c00a-4de4-9f6f-930f6a24b058', '628104', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('41b0d3dd-8880-40e8-85bb-412a90f4f839', '628105', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('96f30deb-8c75-4837-b48c-242276a856ce', '628151', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7a6363a0-b182-4a27-8742-fe8699244ec6', '628152', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0297f898-a3c5-4838-91b1-a8f05ef899fb', '628201', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f9578841-2c0e-496d-a7a2-6d587d7b79b7', '628202', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('152a658e-00a9-486c-a945-4648e195a2e5', '628203', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('82cdb2e4-4610-437f-9e82-af279d7aed88', '628204', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c073ba3f-9347-4428-b0ef-18f1223ea332', '628205', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('42102265-132f-42ef-825a-77e133b3752e', '628206', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6521f4d5-a7ae-483c-b143-94df2cb99175', '628207', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3700e6d9-3ca8-478f-8895-5cbaa3b31585', '628209', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fb03ec69-85ee-4bac-82f3-d85b99fd2e14', '628210', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0416132a-9eb9-48f3-b6aa-9c03b452abca', '628208', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d1c60bd4-9f52-4a91-9617-8d3369bcfae7', '628211', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e6ea1693-c5b0-4165-99e1-4de5d3588ca9', '628212', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b019c529-aa8b-4be8-8d04-87217c9d0103', '628213', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('27f41995-66df-4c84-8302-3e8f6bc7bbab', '628215', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2ac24fde-9350-4239-97c9-9830e672218b', '628216', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('39e53dc5-9d3c-4c49-813e-4172ab1ec017', '628217', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('32d960aa-aa80-41df-a8d2-7f71471f2223', '628219', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9039738f-4107-4c11-b6e1-e34817ca42d4', '628218', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0eafc4d3-5209-4862-8d4c-c5d4ea8fd72a', '628229', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b302dfcd-7d0b-4d8a-adc4-1826d523387b', '628251', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0d611a23-d340-464a-9676-755230adc195', '628252', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('dc590029-71b5-4884-bc6d-03772db66999', '628301', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('babee3f9-6a8b-4d0b-86ac-edef10363dca', '628302', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e6453fd8-0a65-4bb3-ad2b-ee9c6f24f36b', '628303', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8edcacf3-f6f4-4dc0-9edf-68e9dc124c42', '628304', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('27747eb8-e2aa-457c-afe7-97e6595ffb7f', '628402', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('740d65e6-e2a5-4bf6-a008-c90f1177d4ce', '628401', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2e8a80d7-9650-4853-a9d8-290bf1de51ed', '628502', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bd967984-7e03-49cc-b699-852fdf3ff352', '628502', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('617dab68-9489-4c92-8e29-ee086a5ec84f', '628501', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6ad5afe7-e952-4897-a4f3-a6c72abc62cc', '628503', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('de903e3c-56d7-4a40-8e40-b1d8e0fddb70', '628552', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('13f89580-a690-42e6-aed6-b5b1b1f5812e', '628552', 'Tirunelveli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('658e9f45-abfc-4e12-829e-3c0de7d25c5a', '628601', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f278a153-8582-46be-9f1a-df0554269090', '628612', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0c67a505-c2d6-4fc4-87da-9e958170968c', '628616', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('16e3c5fd-2205-4d1a-ae2e-342b184b1910', '628614', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6e360f44-f653-47f3-9a1b-0ea3b2d9b1ce', '628613', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0ec8fc9f-48dd-48f6-857c-4151cf5fea02', '628615', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f38b83ab-cd1a-4493-9c4c-d6efc1811d59', '628617', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2e0f6bdf-fba1-4ffc-9717-350f85a3dc51', '628618', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('16315b34-f3f7-4cbd-a72d-e4889652339d', '628619', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('042a2149-5e27-41ae-9092-c6c94c65e2ea', '628621', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b0299c6a-2628-430d-8546-7f7b1ff9dd19', '628620', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('99b016a2-dc60-41c5-9de5-3d2360da8796', '628622', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f0d1f7ce-09cf-4cb5-b741-8dc774f8a011', '628623', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8ab10d01-fb29-4aac-9da0-4395b5d9bee0', '628656', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a94889a1-234c-4645-859b-f0b796723a05', '628653', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6fdf050a-960f-4cf3-94a2-9a3971669f46', '628701', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('47431af0-2727-41a5-91cc-6a8aecb2db65', '628702', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c006b58d-45c2-4bfd-b85c-6b6618d32a93', '628704', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a835198f-1c9b-4f1c-9899-075135b15d2a', '628703', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('186fa494-7376-4399-9da2-1a4731c7fee0', '628712', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f019fddd-d387-4e41-aace-e1d5ff7d9c10', '628714', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4cc60fa5-6b6f-4b4a-88a9-26bf861227d1', '628716', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0aee0a96-2c8a-4deb-929a-47cc50e4bd1a', '628718', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e899f87d-a797-4490-b1be-922b20ec30d4', '628720', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e343f874-f48c-4d0a-bc3c-d2076e98b22a', '628721', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('df2945e0-c7d7-45ec-aed7-3e56dc3df96f', '628722', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7a4ac375-da8e-456a-95b5-d798027ce72d', '628751', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d11a1a9d-ad2d-434d-8894-63cf39e92246', '628752', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('91d8be36-df40-477b-b88e-fa05c0501b98', '628753', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d3d25444-96cc-4f46-92b2-d7323eed69d8', '628802', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a853d931-89f8-452e-9d28-28250850a9ee', '628801', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('df012a53-b147-43ec-97b7-9195fcea82ed', '628809', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0b55a38f-4111-4ee3-bb0a-04a671b6cef1', '628851', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('585dfd7e-c8f6-44f5-a329-e3fccfd1a733', '628901', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fb625b3b-d8fa-424b-8dc9-7dab6f5dda8c', '628902', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9c1c3e83-6168-412c-867b-081d33672bf8', '628903', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('00e96a3e-88b9-4a58-a5ed-9f3a5560cd59', '628904', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9c05dddd-7bb7-4e2a-bdc7-3af0e4fb6d90', '628905', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3049a08f-9900-487a-adf6-dbdb919ec7a6', '628906', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('704aefb5-cc7c-4780-818d-faa02dd05ea7', '628907', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f0ba9777-a84d-4e13-89cd-5d6d3b86e8bf', '628908', 'Tuticorin', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('16d7c21c-7ad1-4f17-8f5a-261d96b828ee', '629001', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bb121583-14c4-4c17-b3f8-53fec2d6d41f', '629002', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5d170e36-6ef1-4af3-8236-db884586c7a9', '629003', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8363d368-4b2f-478c-8e9f-7f5ad51e053a', '629004', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('705e07dd-485a-41fa-b3f9-fe1037be1590', '629101', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('60383580-f505-48cb-8d6a-3d176db9b201', '629102', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('579679ee-3211-4950-98d6-c67886d87fb1', '629151', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6e5cebec-2f17-4570-add7-4178dd190045', '629152', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7cd4bc0e-5f66-437b-a4af-0aa43062c9ad', '629153', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f8db102d-ca4c-4caa-8d9c-4c50a00341e7', '629154', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9aa8149f-1165-47b4-a367-537932df1391', '629155', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e191e0e5-b104-4b62-95ed-55be9b01abdb', '629156', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f667964e-25a5-437b-a7a1-0f88fe8445c4', '629157', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e3d4f7e3-a7fe-4640-83af-5f68fd816402', '629158', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4e168cb6-f904-4ba6-901a-fd086eddcd63', '629159', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('55a2dc3c-e82a-4911-b180-bf511cd0cd14', '629160', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9247ad8c-7532-4a12-9838-3d398cf913a6', '629162', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e6f43206-6663-4686-975f-29c659e4f905', '629161', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ecc6707e-4225-4c1f-8fd2-2629d4bf333e', '629163', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4f8b4fee-9c5b-460a-a991-bbcac3e53f80', '629164', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5cd47d9c-4c5b-49a7-864c-89d057919ede', '629166', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8867ea46-7a65-41c5-9107-4ce0f4c5c3fd', '629167', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('741eee86-efa8-491c-b60f-c535a5b04303', '629165', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3ffe7594-08f9-4dc6-ac00-14b5703ec4cf', '629168', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e486c841-66ba-487d-aebb-5ebe62390e77', '629170', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9aaadcd8-a0e7-4c3b-975a-6d1443e3dcf6', '629169', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5c5cf1e3-4f47-48f9-bf17-ad978fe67ba8', '629171', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('49782771-e937-4551-baf8-9b5ab2e387f6', '629172', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('db4c60f7-b82f-4e71-98fc-52dd12740d85', '629173', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('68cf48be-bbbc-4bca-9142-cf91e4bf0333', '629174', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a94e9047-85e1-4346-b73b-73ac34a6ad6f', '629177', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d696c7b9-ac91-499c-abd6-abb3a75e2e82', '629175', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3a29912c-04a4-40b8-99b2-79548ddaf058', '629176', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e62bee9c-93c8-4f80-90b0-a36d5e5f977b', '629178', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('df95a93c-727b-45cb-a601-c41f06222444', '629179', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9ac8df66-8b8c-4e70-89a8-f4cbce0f6f34', '629180', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ae0cbc7b-9239-49dc-a7eb-144646daddf3', '629193', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e981c263-9889-4196-97dc-affb2f1ede4b', '629201', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3b35f240-c7ff-4864-9168-dd57f03c0efc', '629202', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('747a784f-cd8a-4cfb-942a-70912fb7d4b1', '629203', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e330a4f1-6e1c-478f-a7cb-0088318e862f', '629204', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('75fb01b9-19c0-4319-9a66-11980ea8ef31', '629252', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9f4807e6-523e-4281-9261-6d9225bb033e', '629251', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3f4229f6-b8e7-4918-b175-f40dc325fcbf', '629301', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4f14fc3b-0db5-41ce-b4a2-6a11baffb45d', '629302', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d5bb3485-48c9-4ca9-9d99-f1b90fb03c38', '629401', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bba8ebfe-7073-4525-8ec7-92d16f9e4c92', '629402', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6d0b18bb-20a5-4497-8d0c-a0d55fcd7d69', '629403', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fb59a104-6e2e-48cd-ba33-7f7d741bf46d', '629501', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('51ffe63e-ea11-4ccc-8c1f-bf478960b182', '629502', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('13503ef3-6262-46b7-a004-81e5b583cd4e', '629601', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9a7c0cd3-fddd-42e1-808c-935f31f95eca', '629602', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c2e39141-3837-428f-818d-bbd6a52e1bbb', '629702', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0146a20a-fd4c-404b-bec7-8952c334deaf', '629701', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2df17358-7842-4a3d-b569-896611f72be9', '629703', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bbdb0233-c885-41f2-a347-4697178005a7', '629704', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bb9b27b3-37ad-40c2-bd94-9048882dcf30', '629801', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('45afc93a-2aeb-4f35-ac34-996963b0950d', '629802', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c20ca384-896f-4cf0-8891-1840541851a9', '629803', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0534d5b2-3982-4450-95bc-21c0a8309054', '629804', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ff5a65e2-4dba-4eab-9e8b-b0d8681f63b5', '629809', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fdf9f39a-6b7b-428f-94f5-760aa253a02a', '629810', 'Kanyakumari', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f3654c47-15f3-4eda-a55e-5b1860c4a241', '630003', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f5355059-5203-4ffd-bece-195a4ceca858', '630004', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('85b5b7c4-ddd7-4304-a04e-698480cb23c7', '630005', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6e55ee97-f473-4102-be62-f7a32de58fed', '630006', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7fedc9ef-d7ea-49b5-9be0-91894359121f', '630101', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1939abdb-0aa2-4430-9e8f-1389f0d82913', '630102', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3f3fd6b6-ca90-44ce-96f4-9a9a6f09fb1c', '630103', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('073c09a9-c4d4-4610-962c-d70dc9c2aee6', '630104', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1bc8f548-9a6e-4385-ac23-855268e09fc5', '630105', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bd4ea65c-e272-4200-85bc-77b4186564b8', '630106', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('23208542-33df-49ae-9c09-a0f0a28b7d87', '630108', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c0a8aad6-1607-4d9f-bb6a-56b6d1035c91', '630107', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f6a0ca1b-0ad3-4681-8632-a1e4337840a8', '630201', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fd08fd8d-fdf3-4bc0-9343-50d3dcf89d89', '630202', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('42600b66-6f3d-43da-aa38-c7df4adb4481', '630203', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('dc699e67-0df2-422f-baaa-804c6c22d3e9', '630204', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e805b927-0239-4427-b9e1-76e080575724', '630205', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f182bbd4-aa31-4652-bd7c-6b888920ccfd', '630207', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('63cda69b-1c0a-4bbf-9773-2ef1878026df', '630206', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cc76a5db-e951-46d8-8f72-487205c786cc', '630208', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0a9e72dd-df8e-47d3-a212-e5180bdaa54a', '630210', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e15936d2-8c14-4a45-97f9-8349f44cbb0f', '630211', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('23ce0bfe-b133-4165-b463-1a7d4e664996', '630212', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4c2bde66-9f3f-485d-9c01-045f52663964', '630301', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d575ac63-979b-4178-80a0-3bd8e0574480', '630302', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('85b207d2-293e-4b68-8dbf-726469c1d7ce', '630303', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a55e6fd9-23af-4520-9e71-cc899715487f', '630305', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1f4a3fc3-8138-46b1-8768-4f38a768216c', '630307', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c41af376-4041-46f5-8e88-d20f10388fc7', '630306', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f2e79633-e6b5-4811-a10d-76f186e76c5b', '630311', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cdc2c5ab-29a5-48ad-b8f5-f98dc7e2a781', '630312', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e589d9f5-abe5-4e79-8a4b-9b5d81fe7a74', '630312', 'Ramanathapuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('08d15b85-3248-41f7-8d5c-ace8b4645ea9', '630309', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('14bd419b-c310-4fa4-b2b9-c570ee98994f', '630314', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('473ec190-346a-477d-afa0-3a6f9cca02dd', '630313', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('53af9a67-1324-44c2-a858-f4dae9279a84', '630321', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('db41449e-3fb0-46f6-9398-a67bafb504c9', '630405', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('383d0ec0-84f0-43a8-ae75-171b6ca4223f', '630408', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('84002df9-a9e2-49e9-a912-58d3a2921794', '630410', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f23281fd-39a8-4b44-adb9-de093791cf50', '630411', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('01141ba9-cb95-4510-bad7-959c5ac3f97f', '630501', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f103e98a-ccdd-4b42-b87c-820fde68e95b', '630502', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0ad0e8e2-6c51-4194-9839-46ab51f383fb', '630551', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a5a402c8-38a8-4652-af6c-e768ea22f3d2', '630552', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3c22b8e4-f89d-41bb-a0f8-687c96e2098e', '630553', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b2db9d78-ef8b-4f6a-9f33-1014afd177aa', '630554', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0f38f0cd-bb1f-4c08-aaa6-dace17ab8c92', '630555', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('12285ba6-9502-49fb-b87f-aa201bed397a', '630557', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f65fb362-6b0a-4c04-9fce-6e20e89ec885', '630556', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('75fd4083-81c9-4ddf-923b-bb07fc7e148e', '630558', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('340f359e-d542-410c-a395-399aab109f1b', '630559', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a43d6e18-8421-4381-ab53-a1ad47714fa3', '630562', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9c514cab-feee-49be-971a-0857c1231c6e', '630561', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2beaf288-ba4e-45df-a1b3-eb319f2555cb', '630566', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c49dfef4-8ee1-4d88-82f6-0f0d57ad89b2', '630602', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('33579829-be2e-481a-b404-3c15fce0f55c', '630606', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('20116639-0fde-442f-914c-ff447349af10', '630609', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('51cc78d9-c81e-48f2-b2b1-bdce552c7701', '630610', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8fe73a27-5ef9-4ca4-9fb1-b2d0374d3fba', '630612', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('24890651-15e6-4d7f-9774-d050a8584d82', '630611', 'Sivaganga', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3db073f6-4213-4c5d-9ef7-9ff40891184c', '631001', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fad5a665-c20c-47c8-89c9-7681d4eda6d5', '631002', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7ee32b1b-202c-42db-a8b1-9f8015541de5', '631004', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('56531089-4ead-4ab2-a116-e20b8de1aea4', '631003', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e5d33dbf-e48f-4a2b-94e7-b633e9541bb9', '631005', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7529c9fb-196a-44fc-8d56-92b41e4438f2', '631006', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('729ac957-75b0-4e39-8c23-687e3abb02af', '631051', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('08e5104d-9733-42a8-abc3-6264498737bf', '631052', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('46190a30-03b0-4aac-a3ba-badab7943097', '631101', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('002edc7b-256f-41da-965c-eccfc6688ecb', '631102', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('61ddb388-552d-43d9-b1a0-5f162fe6ade7', '631151', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('303288b6-3e10-49e1-842b-643448bd8b1a', '631152', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d5ecaa3e-26b5-47ad-8850-cd2a9e893454', '631203', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5674d866-97c2-403b-94ff-94c4ddb7c254', '631201', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e48efd51-64ea-4912-8f63-391d9eda0b25', '631202', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f0e90281-9a68-4f09-b808-efa2d9abc947', '631202', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('904d93ae-3153-4e02-970f-635ec23b49a9', '631207', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8c72705a-9666-4b0a-b115-f4800fb6c670', '631206', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b813c1a3-be10-4454-95d3-44766b35870b', '631204', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5eb11848-6be2-4b87-9c33-c7678685a222', '631205', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('795a4286-cfb4-4c64-a642-0e5691f9fc29', '631211', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bcf44567-79e5-48df-b9b0-dc0b240e3e02', '631208', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3193d4d2-f593-461d-8ed6-df5e0a7ea79c', '631212', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('19d90495-8243-4638-8546-30e61dc89289', '631210', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('628d667d-7cab-4602-95e2-63477a12849d', '631209', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f92c8efc-abb9-41f6-a1a1-c27712fa6bfa', '631213', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9c0d870a-a90e-4fe3-9011-29f0379cd287', '631301', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a01ac349-1c65-4634-9405-fbddd53b919d', '631302', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3ec39bbc-61c9-4122-b0b7-2120ceafecfd', '631303', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4b9dc5b8-7ea4-4ff7-8db7-ce122d59a3d0', '631304', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f7e42236-cf91-4223-b48e-f0068efcc659', '631402', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2b009f02-9410-4970-bfa1-eaed65bcbfb1', '631402', 'Tiruvallur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4ba2fb80-db33-4d77-8e6f-ee594f823062', '631501', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ebc09fa7-8c87-4dce-9ab9-cd2354ad1b14', '631502', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('846aab69-850d-491e-8516-e48096086e10', '631551', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e22d2bc2-b73c-4f06-8398-1edc53aeec02', '631552', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6ccf186c-9b5f-4df4-bd09-1179de4c2d74', '631553', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7dbcebb6-00ac-4269-a12a-3fbf63875e8c', '631561', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('622c533b-b560-43dc-8be2-63c39cb98c3f', '631601', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d055ae48-2516-4592-b92b-49bbb3a13523', '631604', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('11f4b1b6-777c-49b1-8fc4-66f7f19eb01a', '631603', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f73c5ff5-ceb1-4461-acd2-570f723067f0', '631606', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9d68eee2-fcf6-4ead-95f0-0e96babaff74', '631605', 'Kanchipuram', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b4171cc5-4ac1-4b30-b701-5cfcc0453d94', '631701', 'Tiruvannamalai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c7ea0b30-f66e-4ae9-9641-7aa54c41ccee', '631702', 'Tiruvannamalai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('449a0503-8eb5-4a0b-bd8a-676af0f7140b', '632055', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0761a222-71e5-4e3f-829f-9e2cf2f443d4', '632057', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5be3ef10-7595-4a1c-8cd1-d1b10bfa6762', '632059', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('58adc7f5-9584-4fd7-be4a-50b64f1956e8', '632058', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1e2e8153-3529-4760-8014-645ed2276357', '632101', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2c07bea6-b344-41c1-b24e-27f28d4a28e5', '632102', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e4cfd6db-23db-4a64-92f5-8d9d00f13882', '632103', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('79070c8d-e456-437a-a282-813b4e90b17d', '632104', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1dbbfdc1-2578-483d-91a8-e5b559b4b23a', '632105', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d8d55eba-f56f-40ce-8f61-5f72badbd359', '632106', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0b2d7fa8-3723-4813-981b-371b9b886e24', '632107', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6e853c4d-e85d-4726-9812-585f284e6c22', '632114', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9a2717ff-fbd5-4a45-af2b-670861a8fa45', '632113', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fad57e16-9d38-413c-81b0-d7ad93cb1a46', '632115', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('068371ac-c01b-47f1-8b8a-d2082a74d879', '632201', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c2a140bb-feca-4871-ba7b-4454fca5b6d9', '632202', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('94a95000-4150-4c7f-8461-672d68ab5063', '632204', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e7a3c057-f4a0-4a36-999c-349523c01b28', '632203', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('83328bcc-1508-4a28-8c43-33361eed99c7', '632209', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c55178af-e16a-4911-bb22-8cfbcfde5ca0', '632301', 'Tiruvannamalai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('48e9542e-4bcb-4f23-8a9a-d9fe19b191a4', '632313', 'Tiruvannamalai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('504d8c60-ed67-4125-a323-221e96cf399e', '632312', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('703ba44a-5bb9-43ef-ad7c-f4c72a0fbc0a', '632312', 'Tiruvannamalai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9fd99cc5-7dba-43a1-a144-7272b58ad82a', '632311', 'Tiruvannamalai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('dffe891c-136f-4365-a8f0-5be0f289fbad', '632311', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c039fc71-dea1-4411-ab3c-6c955e0769ac', '632314', 'Tiruvannamalai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('441ed658-8668-428c-aea9-217012c9a6f5', '632315', 'Tiruvannamalai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5a94d4de-e90d-4578-8071-ca5debe2891a', '632316', 'Tiruvannamalai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d26688bc-9486-4ef4-8b53-0921950274ac', '632317', 'Tiruvannamalai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3dbc3bac-78fc-4bad-91c8-46eac8f18ca1', '632319', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6b54fd64-46e7-486f-a441-a6d69acc975f', '632319', 'Tiruvannamalai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4c99bbc9-fb9c-4490-8a53-1812af3db1ad', '632318', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1a10e0bc-25a7-432c-a796-b3e01d89acbe', '632326', 'Tiruvannamalai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ae98edff-e4d9-405e-9362-4a5212d73b13', '632403', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9208efed-66b2-41a1-a087-2228d9b4b946', '632401', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('53384a3c-e948-4f36-991a-5a411500b1c1', '632404', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('39b9a371-d63e-4de4-a8af-0fc7bef77e8d', '632405', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('72401e09-c5e8-430a-be04-a40baa70ca55', '632406', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d4b7319e-a793-407b-bc05-f5a727ae555f', '632503', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1b82093b-c80e-4b6f-9e22-9f24d24f5267', '632502', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e4dfce57-c4dc-442c-94ed-5c147b0e3f7a', '632501', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c853e971-3933-428f-9ae5-ad7bdbc9a5ae', '632504', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('998aa64d-ef1f-4257-8a6b-567db7c515a2', '632505', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2f48e2df-cfba-4e8e-82a6-977f07610587', '632506', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ea5043db-ccf4-4fe2-babc-1c904fe5b78e', '632508', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fa76012c-ab55-448e-bdfe-aefd4223570f', '632507', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('476285d3-4c9e-4194-b1d2-0c37edf6db00', '632507', 'Tiruvannamalai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ac7577a2-3086-4496-826d-2c5491f45db9', '632510', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('170ca596-5d9f-4f48-9f5e-12e2e71d9847', '632509', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('aa02115d-f1b5-4a0c-b980-db230848b1cc', '632512', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('28ba3f47-2ff2-4ea3-ad2a-c66b3aa93d65', '632512', 'Tiruvannamalai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3b12a7d5-f639-46f7-a888-d603a498ccfb', '632511', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('509fc632-c887-464d-adb5-665f08e5c62c', '632511', 'Tiruvannamalai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('eeb21d6a-8deb-4d22-ba41-96e126d6ba17', '632513', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b0a29837-387e-4a1a-b457-67bd38a2cfbb', '632514', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e60c5898-39d8-4d32-83d8-eccfd754919c', '632515', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2674d65b-20a3-48d2-aa87-50fed36e4462', '632518', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1a033633-47dd-40a6-ac25-b86ef5a7cea6', '632517', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5af8265e-714d-4c5a-b745-9309376354c0', '632516', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1d3b4033-4b00-4d5c-b93d-278c20125883', '632519', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ec76a504-9620-4dbc-8829-670cb0d53847', '632520', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('de9b49b8-c30a-4544-9851-ba1f57d7e8cb', '632521', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d6749570-f28d-4134-bd6c-9df01b3ea137', '632531', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a8072124-eef1-450c-8959-ad4162f53cc4', '635001', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cc517ddb-62fb-4f23-b7e1-3c8dbb44f9a5', '632601', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0ca99519-6ce5-4df6-903f-4656f959e31c', '632602', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('518623c3-8422-42a0-a77c-e5b000e4bf04', '635002', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('effb7dce-8618-4cad-ad29-b1601d74a681', '638457', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('48fa3cac-82c3-47c2-982e-5ed44b2ddbbb', '635101', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('099d6320-8238-416a-8a5b-f9cb221b2951', '635102', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('412693cc-fca6-4bd6-9ee8-8c1336b7e32b', '635103', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('05f1307a-86c8-4577-8c4c-a89ffe68e057', '635104', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cb58fee2-1595-490c-b41f-639aa578bb26', '635105', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a7abd1a9-c986-48d6-a62a-5c3e40ee1d2c', '635106', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('759d47cd-5288-4483-b6dd-4964afafc704', '635107', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4ccce0a2-9053-4372-96be-a82d776b4af2', '635108', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4870d61e-6288-4884-a722-c944c6ce2075', '635109', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1dcb0230-7440-430c-a80e-8dca6b1c4b3a', '635110', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f74d9134-5c7f-4b50-967a-21d06475f2c0', '635111', 'Dharmapuri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a50f2a48-6819-47f4-958d-0230988cabf1', '635111', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9d53ecc3-9c7e-4aa0-9872-1f1fb1129783', '635112', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c3ce8a81-f7ca-4d21-ac75-c56bd224f12b', '635113', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0a270f09-0610-469c-995d-87bd5ffc0467', '635114', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a6a59c98-7f64-47f3-8085-e48507373cdb', '635115', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8b18c26e-003d-4b6d-a0be-ead07345af15', '635116', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a344c29f-7b7b-4cf3-8cfc-2fca43bc074c', '635117', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('52319598-de22-4c41-a87d-d1e031e16d7d', '635118', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c1dfe406-6f0a-4382-94dc-20ece3f3fea4', '635119', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c9fec6a5-b2c0-48b5-9645-cddbed7b690c', '635121', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('10f0a38c-3bf4-4430-9e45-12857017b5bf', '635120', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('27e401d5-606e-431d-bd12-81c43052fd8d', '635122', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5a52b3aa-57d2-4f4f-a30a-39c5a5c337c8', '635123', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('51f79f48-b44c-487a-83f5-7f1113cd4e69', '635124', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fb8a8a55-1987-4728-b0bb-16d54854fdcf', '635126', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('08bce768-1961-4545-8d3a-4b1e6395f614', '635201', 'Dharmapuri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a514382e-fd31-4914-95a7-9632530dcee7', '635202', 'Dharmapuri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9db8d18d-bd93-4774-a5b4-c754978b6634', '635203', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('86b3ded7-4370-4f07-b6f3-e15b5610091e', '635204', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4946e180-ceb8-483e-bbb2-aefaf60228b4', '635205', 'Dharmapuri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d6b83ad6-0cc5-4dd6-b1b7-23cc97695a73', '635206', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('83e6df5f-a364-4451-bd74-96859355a2e1', '635207', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('04cb6f21-b0ff-402e-877b-53d76e66d2f2', '635301', 'Dharmapuri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8b9af681-72cc-49bc-975f-b30fd7e4b568', '635302', 'Dharmapuri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f1b9cff8-3324-4510-bad9-88ac78fc271f', '635303', 'Dharmapuri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ebd952d6-4d5a-44de-9c89-d6f8b0600ad9', '635304', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('900d794b-b1c6-4d95-a23c-5a2a13491065', '635305', 'Dharmapuri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b680b6d7-42bd-4a7a-9b1b-c5f9f53a1bf7', '635307', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0b8b3a7d-fcab-479d-8537-4ec2fb33ffe5', '635306', 'Krishnagiri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d70b99fc-392b-42d4-bd71-cc1ef0cc86cb', '635601', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d8315a6a-c8a9-4a89-899c-e6877d40af4f', '635602', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c36eabae-7968-4a77-8ed7-b0c71b825011', '635651', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3b98e4ae-7902-48c3-b91b-ce0f91e2842f', '635652', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fe51fadc-c456-4406-902b-a55c78fea727', '635654', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6861f950-edfc-47e6-bffc-b093b3f25363', '635653', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('11a76f43-76e3-4996-8890-a2e9474ddef8', '635655', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('35b88a0f-43ff-4a75-9bf6-b8aeb622eb1c', '635702', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d588af13-f1e8-4a57-a3de-5fc779f2d400', '635701', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('93fc4ec3-e246-44c9-a4ed-b6f44514de5c', '635703', 'Tiruvannamalai', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('643e3200-3bf2-4dc1-9ac8-e941f63512df', '635703', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('65d0760a-bcd1-465a-978d-01745f304dfc', '635710', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f4a7368d-a43f-450a-bfa6-06112e570de7', '635751', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('27752fee-196f-4d44-9d30-dabf7fc75152', '635752', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5cabc0ec-bc4b-47b4-9d6c-9c56f7c12dbf', '635754', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8eb24409-6e4a-40b9-b7de-bc621e54d146', '635801', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3d54e162-f559-4a6b-9bff-342b833ffd6e', '635804', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('938264d8-94df-4233-8c88-109c56474949', '635802', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c1aa71fe-8fcc-44be-a3a7-7fc219aaf878', '635803', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e9d48417-03fd-4652-b462-5d0ef92b2595', '635806', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9d6c257a-aec4-4f92-88d7-a3322b818303', '635805', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1f2b6882-6b3d-4f08-bbeb-72b7b9949419', '635807', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e54d6b95-2f11-4297-99c5-0b0c01bc6012', '635808', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8334921c-f23e-4f4f-970c-de3d31dde5bd', '635809', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9e38ce11-4884-42cc-aa7e-92b664828e75', '635810', 'Vellore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e7fa96c7-1ed2-4aea-ac85-6e5888ab2ec0', '636001', 'Dharmapuri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8018ea9a-dd89-4246-9f07-97a0619bc683', '636030', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('29fce1dc-9c12-43e2-ac32-4b85b05ef3bf', '636101', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c6e323d5-4be0-4c0c-a904-e94f73be55e6', '636102', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('612c35a5-5801-4e56-b7cc-def135aa3f82', '636103', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('03039668-93c9-4473-ae33-a91e1022d7c9', '636104', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9ba352b4-85ad-48ba-aa49-5fe37a37e173', '636105', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('db8e96ec-aff1-47c4-a00b-3dd9a24efd29', '636106', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a9ffcdd3-beff-47b2-b7d8-912e62fa42e7', '636108', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5f711941-7a6f-47ba-a580-e6e72b39ee86', '636107', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b4a1b5ef-2ed1-4486-a9b1-d9bd27e2b37c', '636110', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('86362854-5182-48d4-b870-57df9d7d6e2e', '636109', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fc356547-0929-48c3-b93f-e9402a5c8ca8', '636111', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d157462b-b167-4134-b9e1-5a2372ac61dc', '636112', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6586aa91-877d-4e00-8183-61197d52be0e', '636113', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('46a46a64-0cd3-4757-86ec-5e5c6dd139d0', '636113', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6cb19a59-6fb7-4164-8a8c-7b2abef93076', '636114', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bb044500-2279-4805-a1de-d357b0e6c058', '636115', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6fd4816d-eef3-4476-a055-002c0a40dcb8', '636116', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('97badf3e-db2c-45b2-850f-adfe0a9caf5c', '636117', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e9bdc28c-9df8-4954-bec3-18cfd6494e57', '636118', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('02e7611e-d6f6-403b-b4c4-0a899c4bba77', '636118', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('eef61738-82e1-4fab-a60b-f99add152656', '636119', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7c1b7ce4-6a1d-4f4e-bc90-deeefd4f118b', '636121', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a16c226d-c187-4337-9021-c18895b42dc9', '636122', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('621038ab-c816-4e2e-905e-34dfa7dcfc88', '636138', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7e550ca9-b051-4b82-bcfa-a8fb9c25432f', '636139', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('92113b2d-3a17-4963-ae26-16708f6f3ef4', '636140', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9434072b-ba10-47b3-94b9-0594fd224c6d', '636141', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d904d175-8386-42d8-a769-d41e6f665384', '636142', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2748c6a2-c781-4444-b3b5-4d71f9a74c21', '636142', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('976764f4-980d-41f1-8da8-29ef8d7d1085', '636201', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('abe6abda-5666-4e8a-8055-51e959e75d4f', '636202', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ee7865a2-72e7-4c0d-8488-b6b53387a96f', '636202', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e40f4d79-fbc9-4fc6-a20c-954c2cb88417', '636204', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a12ab59c-ec77-4cd5-8112-70095e345d78', '636203', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('715c2a04-e83b-4a09-b4fe-0c5093beba3f', '636301', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c056852c-5571-4d53-981c-37f15efaa9b0', '636303', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('dc3281d1-c0de-47d6-99ed-066ee61b8f31', '636302', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d7fa185f-1946-4d2c-926e-4ab244b7c6b3', '636304', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e93f7942-0f78-4a78-ba56-d2360a8a9639', '636306', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('278582e8-9a74-4b77-ae43-ae2971e88ea5', '636307', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d5f87827-0b54-4826-8735-8f462854ed3f', '636305', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7eb44828-9c9f-4053-9693-1673e4025d92', '636308', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('04827c49-5c07-4abb-af56-aa0bdd27ace2', '636309', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8d682f5f-20c4-4234-a2a1-5866b706229f', '636351', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('52bf9598-9331-457e-b6a1-e8ae59bd5fa8', '636352', 'Dharmapuri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6a8d9966-63bb-40db-b843-c7aca125fccc', '636401', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fc326f8c-99f4-49bb-b99b-f21c341b6956', '636402', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bd2e69e5-20bb-4834-b9f0-a84f171c4afe', '636404', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('43bd0f79-32c3-4b0c-bfac-ee8f805af208', '636403', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9c16afc0-4758-4d2f-9c92-d1dad0bcce93', '636406', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('56ede1ba-bc81-4f3f-b89d-3f8a07eab2a5', '636451', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('787df609-d923-42e3-9ece-066caa52946c', '636452', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('888fecc1-b918-44d1-8088-b8738b29ee8f', '636454', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5f146c35-f4e5-4428-8b79-a5172ed274fe', '636453', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('48dc25a1-3d29-46c2-9bef-49e08bf73f47', '636458', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6b87bb40-a66d-4cdc-b96c-7b4228c7e7d1', '636457', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c5768d12-8e25-47af-b7e8-d1f8eac4c887', '636455', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f55a1d02-8483-4d85-ab54-93c1f0d87593', '636456', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8837bcd5-e7d3-4360-b343-0b51833fc115', '636501', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('00d626ea-6c62-453a-ae4b-c84a79ebf2d3', '636503', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('20295866-7231-4478-a964-b5804385d6a8', '636502', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('49b16ede-ec23-4cfc-891c-a7f44b018002', '636601', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('34426c6e-cafe-4184-b325-6756f50e4e4b', '636602', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2c79343c-bbca-45e3-a777-a66cd6508389', '636701', 'Dharmapuri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f17d2034-6292-41ae-b2f1-4e291ae8c48d', '636704', 'Dharmapuri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0277ac49-2bb8-4081-a6a4-fd033bf22544', '636705', 'Dharmapuri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f896b383-a561-4b49-b7ca-19c701b274bc', '636803', 'Dharmapuri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a1def4ae-24dd-4dab-b2ae-5ff8e2addfe7', '636804', 'Dharmapuri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0573ada3-dc92-44be-b44f-f43a007f7907', '636805', 'Dharmapuri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b7f89177-a8d8-406f-b494-d57d1b946e3f', '636806', 'Dharmapuri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d34f1c29-67a6-453b-bf43-fd9120cbcad5', '636807', 'Dharmapuri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2f8e8cff-4e1c-4154-8ec8-2a0be6b1e076', '636808', 'Dharmapuri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('779ded0e-7e7d-4a0c-9ea8-e661f559be76', '636809', 'Dharmapuri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('772af40d-724a-4a9c-befd-f049973bd54b', '636810', 'Dharmapuri', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c4a1e512-f1b2-455a-8595-995e76785eeb', '637014', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('200f9825-5318-4f71-92d1-00019cf8f427', '637013', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('60804a42-75fd-43f5-ba66-9397e836f133', '637015', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6a4e140b-0595-49de-8f22-ac80c32ca036', '637017', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9341a6f9-2e1d-444d-b237-048d09cb8666', '637019', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a6355fe9-182f-469c-a43b-5eda8dff52ab', '637018', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('47814d37-6aa2-4f82-894b-b63b9789ad70', '637020', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5ce0fb5a-aa95-4245-a105-9ae1a07b7c23', '637021', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1624a477-dddf-46c7-82fc-5bada5ab1b01', '637101', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0ce3e9bd-9682-4d5f-81d2-935296bc2866', '637101', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b0005d66-c51c-42c3-b324-1fbde595fe8a', '637102', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6cade7ee-770b-46cd-bccb-1c674d30e640', '637102', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('16b4cd1f-2342-49a4-b22b-0ffb36dfafe9', '637103', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d229fcfa-e0da-4eae-b096-10ee244e4cc5', '637103', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('08b1b3c3-dd42-48c2-a068-a9293aa1772a', '637104', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('85f283ff-42a2-4f8e-8dcb-d5aa48565f74', '637104', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('28021e33-08a9-4eb9-a4d8-cc2d58b07de7', '637105', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1d258ece-b2f2-41f2-8370-2eb27083fd82', '637105', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c6743ef1-99b4-4164-aa43-32647982557e', '637107', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('594ba71e-182b-4bd9-9d3e-9fe045314ba1', '637107', 'Salem', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('927c120d-bf78-4743-abbf-7e8f28254334', '637201', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2cf565ff-9207-4b50-9a28-1d5e51a51e6d', '637202', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3cc1a1e8-64be-443a-b976-5844920c8ac7', '637203', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d6ef6fd1-2e7a-4eeb-8ade-9fb625d9ac30', '637204', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('be2b30c2-a92a-41c7-b044-4841531a9b91', '637205', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('36f46799-0760-44ef-98fe-3153197adbf2', '637206', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1bd37dcb-efb6-4ba2-b013-e380813b15c4', '637207', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fea48f29-f870-4fc5-806a-305d17b78802', '637208', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fa892373-eebd-4cbb-85e4-74bf073ca269', '637209', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('93f2bd3d-84c8-47b0-903c-77509cba2fc2', '637210', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('64ff3ef5-3b52-4ab2-9092-012d4356dd93', '637211', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('24898edb-7d24-47bc-91ab-92653347be8e', '637212', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7d808ef9-9870-4af9-8970-5382874bb7ee', '637213', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9c14f6f1-277d-4b99-9bbd-7800c5c61570', '637214', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('20016201-c13f-4eb9-a790-9270f66cd3d7', '637215', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('db8c6f3f-bf59-4d78-bc6a-3b03b9adf65f', '638006', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('afcb5a4d-9f68-413d-9987-0af71a422bfb', '638007', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1bfb1a7e-e8c1-499d-8246-164eb39e013d', '638008', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c3413110-b432-4579-b487-5e286d6c1c1b', '638051', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('46e1c2eb-6c13-445d-a1df-d69338cba15a', '638052', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('01b515ea-125c-4b61-bb31-9afce3b58707', '638053', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('21d38508-b89e-4554-be1c-7d00417c4287', '638054', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c72e91c7-e979-422e-a095-0c08d5c1242d', '638055', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e830a77a-2ad9-4a41-bc20-3f01d21f1fb6', '638056', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('efc1c6c8-51b6-4f6a-a8f1-e237e3379394', '638057', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e900b18c-d57a-448b-a290-c7b26ef85251', '638101', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f4842313-7e05-4935-801d-01d991a92d45', '638102', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2803717c-c381-495c-84d0-58fc97c85a72', '638103', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0a3a8ec5-2150-4c22-9333-cb38bf0fd488', '638103', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c3858622-584b-4ea8-9475-7f116cce9f03', '638104', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('79032598-a70f-4789-9cf2-5ccafd0c6ed9', '638105', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('93751a62-2ead-4c66-a3b1-089be7c36378', '638108', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f786426f-18c8-4774-91b3-9f243bdb6137', '638106', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('34df2959-86ba-44a5-829f-64a45e30f4d0', '638107', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ed3ea76d-e315-49a2-8e69-d22e2859a183', '638109', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('08e79d3d-db79-47bc-8256-99dac06b50a0', '638111', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a7f43f95-7aab-41e7-af88-06babecf1f57', '638110', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a1caeed7-be40-4ec7-bc0e-0d2bd31ff518', '638112', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ac1cb440-1e04-4675-aff9-a6f2974aa0f6', '638115', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8a3560e9-cba3-430e-b3f4-d1e5f6d71808', '638116', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1be03d51-ba1a-4e28-8223-109888538b6c', '638151', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('146ed56e-ffa8-4cfa-b6e7-6174d2e15647', '638151', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('aeaabf79-786b-4467-be4f-8376ba2c2245', '638152', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7f7c38e4-cabb-4dc6-8ff5-d294821e5f56', '638153', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2cc1b7a1-7847-45ea-866e-79f9d5a715a7', '638154', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3bbd95ab-8fec-44c8-a165-a4a288c482a6', '638181', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7dc6fc7d-c223-4590-8a3b-eafbcda85602', '638182', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f4ae5d84-8715-4464-a1e0-1e201cd633f6', '638183', 'Namakkal', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9d939638-8355-4270-9376-ca7ee39268cf', '638301', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('89cc4dc0-6a5d-4897-8b53-0fb3ec1dc073', '638311', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('434c4209-d7f6-4c38-9c9a-07fa2917ed5a', '638312', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8c96f903-2396-47e7-a1c0-9d1188900168', '638313', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3455cee2-b93c-4af4-b0af-3d547e963e49', '638314', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('73ae848f-7ef4-4cff-bf8c-3d0fd19a9f4f', '638315', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2daba427-9df8-4ad0-bf05-46ac08fd290d', '638316', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('991e973f-1301-4c2b-9bf9-c1693b5a4b65', '638401', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('43e6c7b6-5ddc-41c7-b9bb-c0cc7df383c8', '638402', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8e5c8a27-3b57-48a0-a70c-6777158d231e', '638402', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('300a9555-6b94-4b29-839f-30054741085c', '638453', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d3730d67-22db-4aef-b381-1db07c49949d', '638452', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('41696afa-5b1a-49c0-aa1c-f7ee202681bf', '638451', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c6577e09-1d41-48fb-a3eb-83e29b28982a', '638454', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('19f3a923-7933-4f4b-a858-71b1b4ad89ae', '638456', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('39b57444-eff8-4b75-8d44-d45e378d68cf', '638455', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4c28004b-b3ee-4465-96ce-fa14ed919111', '638458', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d117863b-ceea-4686-9569-c4f4cdc9edef', '638458', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('43fe20dd-728b-48cb-9d68-9bf0ba77bfe0', '638459', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8f0e8603-ab10-47f0-80ab-1488021f45f6', '638460', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b2af0d10-3f46-4c02-a6e1-36d6b1edc4d9', '638461', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('28bc639a-4f6b-4543-bead-34322cec2484', '638462', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5b0260dd-f392-4c04-b84c-ffb4ad0746d7', '638462', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2bbf33ed-ddba-4b16-a145-93e841829f8e', '638476', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8d5fb9a8-eb64-41d7-bcd7-8547c5015214', '638501', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('23988081-bf2d-4086-bae6-7ef9b560dd7a', '638502', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c8d5f11a-603f-453b-b397-5c2c6dacf2a8', '638503', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2f9f05d6-db77-4ba3-9ed2-69dd0aaf6289', '638504', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('84ddcb54-b314-46a1-90c1-7cc814901af3', '638505', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('85d91cc6-f54e-4e18-8299-0399035b8606', '638506', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a482d490-8502-403d-aeae-62932253df52', '638656', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ce5e5e59-c023-4381-8dbf-6b42b2207a6d', '638657', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a6fa924a-530c-464c-8fcf-2c58d5f6f5e6', '638660', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('34277085-3302-4fcf-95e1-f7f2ad9a9d8b', '638661', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bf3a85f8-35e1-4030-aa4e-0250f39cf91d', '638672', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('13c23721-ef21-4a37-97de-241704d4af89', '638673', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cad2967d-d9df-42ba-88dc-56f1b21889dc', '638702', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8f2bc937-78a1-41d9-a151-7a46028365f5', '638701', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f0b778a4-717c-4f0c-b3f4-d2df2b7b9bfa', '638703', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('005b39c2-588a-459b-b386-e1ec73af2008', '638706', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('be6adfcd-31f1-4536-ba3a-a98de8275148', '638751', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('866689ec-2b67-4cb0-87a5-df428811523f', '638752', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4dca63d9-7ed3-4e4a-9aca-039b382e73c7', '638812', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5fa86881-9f03-47fe-9a54-64f0cb9b3353', '639008', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('492acae9-ef09-4912-821d-c657f1e986a2', '639101', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6e161520-8be8-4a5f-8a65-875c5f7ee503', '639102', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a8f41ddb-b51f-45fc-84a7-726010ba55af', '639103', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f0e3d92d-5c81-4aea-a37d-e3fc59f49107', '639104', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('802b1812-0887-49a7-9519-37a9fc7bdf55', '639105', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5e87ff79-7040-4c9c-b7c6-0f9c03fae1c4', '639107', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8a6b8464-3fda-4ae7-9795-5222078e1d2b', '639108', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b5d1396b-3d4b-4e25-ae0e-d34700395762', '639109', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f300c043-4c70-455b-bef3-d0e6c0297e9a', '639110', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('97431ddd-d94b-4467-91b2-05b994d44763', '639111', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('87202d10-d437-42ad-847e-45333c1b01de', '639112', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('394c8371-cc2a-4358-bd5b-5e67736b4318', '639113', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9e34514b-5d6c-4aaf-b504-ac20b81340c0', '639114', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('00543f05-b1d5-4c66-8539-a156064f8649', '639116', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a5ff2a4a-9668-436c-8736-ffc8cf8f1a09', '639115', 'Tiruchirappalli', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8e7bf177-bbae-456d-be07-dd8de76f4674', '639117', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6301f807-2016-4a63-9670-2b0b93e68bd1', '639118', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6af74a71-9a0c-4f44-8cf0-0e1ba3d77040', '639119', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('40410d34-60b6-4d38-9855-8eb9acaeed4c', '639120', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('894c47e4-1786-4823-8b57-1e370c84806e', '639136', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c49fcfad-f2e6-41b4-9ddd-a59a0e455058', '639201', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9b61ccc4-6e6b-4e91-84f9-8822c30ce86e', '639201', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b557f8ec-0a73-418a-9c2c-5ee4e345440e', '639202', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9951fb03-f57a-4581-b310-86e3b497cf8a', '639202', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5ff7c211-6f61-4653-ae25-afc3be9aa023', '639203', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f1608ef8-9b75-422b-a229-50599472b58c', '639203', 'Dindigul', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1b61199a-e40d-4087-8fc8-9df1163f07e0', '639205', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6fdd62f9-67fa-4928-9d42-501d121032a7', '639206', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6e9964c2-cf03-4ec8-957c-1468925cc7d2', '639207', 'Karur', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ce33aee9-cfbe-458e-ac4a-140a46aa7bbd', '641021', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('96058ccc-6fae-4f3d-9f38-51eb0172da32', '641031', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('289e3ba3-0155-4b7c-852e-c811eaa0b08c', '641035', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f8362e18-e869-4c22-8c3f-49c9b9f0e89b', '641039', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1b912aa8-67af-468d-b958-4b173b52ecc5', '641038', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('86d08c2e-7869-4526-9554-84e9690055ea', '641041', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b3033a68-97f0-47c6-b33c-2e67cfc0bc9d', '641043', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('23afdfd7-2e6c-487c-a3cd-e25f76a1cbd9', '641042', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5695ee22-ca6e-4339-8f81-d40ce1f7c422', '641045', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fe5ead98-016d-492f-a51a-dba71a53fed8', '641044', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a954801f-7c41-47cc-bd91-98705947c00a', '641046', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6ff477da-aa17-402e-b973-bf43a45dd082', '641047', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('485186e5-dc8d-4543-a4b1-01a3eb3794c6', '641048', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1a5eb6aa-f2ff-44d1-9d41-5756842a2103', '641049', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('d27661e7-cb78-482b-a853-2ada89065dcc', '641050', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('89ae24c2-2952-45f7-becb-e4602747545e', '641062', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b7f06c89-a0eb-48b4-b274-fe1222baf24c', '641101', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('719d4883-b2b3-48c6-b300-afacc55b674b', '641103', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7c1beea8-4b19-4bac-8c8c-94c6ad7c2573', '641104', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ad0b9e12-7397-4e1d-92af-0ece8d0311ce', '641105', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3b6fe89a-53aa-47ca-8e78-cffa2c865eb1', '641107', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5fa6b175-d5ee-4384-8493-521d6b9d0521', '641108', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('af1b517d-ff50-41b9-94f2-3f2ad4d1acc1', '641109', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bfc8f2d4-ed5b-4d39-adde-e4e13b0023ee', '641110', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('495ee2b8-281c-4756-8257-0071d2fc24aa', '641111', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('03e21ea2-8685-49ad-875d-4d0d2d365b89', '641112', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('20cc2501-ee11-4913-a4cb-1e500182f2da', '641113', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('25ff5e3c-8f82-45e2-9704-5bde9728f65e', '641114', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7145c882-2753-48b4-a691-6fe8660d1077', '641201', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bf09b8f4-77f1-4f0f-be2b-1f215f4cfc06', '641202', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3d9ba82e-4689-420b-b4b6-cae28569ce37', '641301', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f1251fc0-6e20-4fbe-b56b-b66ff7e83aa0', '641302', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e1ba6bf6-ee5e-4703-8ca2-3228d3219cfd', '641305', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c459f909-a936-4751-aa19-751eb0fca74d', '641401', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('75935e16-1d26-4199-8a7a-c474c431e707', '641402', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e8d1e8bf-d3d6-45aa-a2ea-16fe16a47e9c', '641407', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a79be483-cada-4aaa-9b1e-d82abdf07874', '641601', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8eeaf741-cf81-4081-b7ce-7b60eed7608a', '641602', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('eb5e01d4-5374-4590-b75f-b0e2e5190331', '641604', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('872e482a-1992-4a73-a9ef-91ae8d0e9e61', '641605', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b58889fc-25fa-465a-bcd0-0d505ce23d6b', '641605', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8861fc7d-2537-46c4-98f7-4d3c77c10229', '641603', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('653b56d9-0562-4048-8e4c-3c6f3d9826c3', '641606', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('74de8161-0c0d-4dfb-901a-22c9e8288775', '641607', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('95f7344c-db80-4989-9271-a1fa9cda262c', '641607', 'Erode', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8e8fd818-27e6-4d16-81ce-5e985b8b3293', '641652', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('9b3e4538-f286-45b1-983a-d360bf808bc9', '641654', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('0ba5b8e1-6eef-446e-b979-159635909831', '641653', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c006411b-d52c-4d1b-9296-eafe49dad2f7', '641655', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6778dfa0-8580-4908-ac95-35cbd8740440', '641658', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e4d09474-8de7-4eba-a164-34318b43a6f7', '643001', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4ab74ed2-1845-46c7-a52a-d92395ff65d8', '641659', 'Coimbatore', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3b3c12cb-a897-461b-8008-f8d062a3008a', '643002', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('83ea6b31-de15-4fc5-8827-1fa7d7604eeb', '643003', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bdc4bf0f-d280-4408-836b-d7947a1da5d5', '643004', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('f9de69a9-50cf-4a10-b33b-97faee71aa6c', '643005', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('a9ac597d-b220-46d6-becb-7c6b65f5349f', '643006', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2500499b-0632-4aa5-9ae9-4b2156cc1097', '643007', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('098affb9-4fe2-493c-a863-c7b4e8b4743e', '643101', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('43456f22-d126-4aab-b8ff-34b6ebeea403', '643103', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4339b7dc-5d27-41e8-893b-e0427032af58', '643102', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c4695010-9bab-4a83-bd2f-278989540137', '643105', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('66ca6a9a-3798-4b26-90cf-6e092056cb54', '643201', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('63d525ce-84b0-4f24-b5bc-ae6b35798d20', '643202', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4233df55-4a53-49dd-a233-18c6ab2cbf9b', '643203', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5a46a958-2990-4123-a077-f0f2cbb454b3', '643204', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b5f3a9cd-57db-47df-9163-5df9766ff568', '643205', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8ffd2bac-bf59-4d24-8f2c-163577772361', '643206', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('ffa43402-de54-4e51-a71b-d2566e02777d', '643207', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8e71430d-7370-4339-9342-5bf6e65afbed', '643209', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('5f8bd9d9-bc6a-4af3-bbe2-402d8466f4ef', '643211', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('bf42dd07-18c2-4b18-a49e-183532d63e34', '643212', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fffcbf80-25be-4f5f-8ec5-abc284b57fff', '643213', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('4bd4b068-57fa-4f6e-90f7-d3c3a2fa1420', '643214', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7adde4f7-0c3e-4c93-a0c2-aa4df50daf32', '643215', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1b50d129-9e46-49cc-bd2e-6349ebb4eea6', '643216', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('e8a19f70-0d1b-49e6-ac43-18be16f2844a', '643217', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('caf9b039-3615-42c1-98a6-d82e4fbf7d1a', '643218', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('24053a1c-6d1c-4831-9406-f32851cb48fe', '643219', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('c7943b03-73eb-48af-967a-f6edf8443a35', '643220', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('757139e2-7754-4c56-8670-91a36d8e5b81', '643221', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b67f535a-9a45-47fb-a416-16e59b3a4e29', '643223', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('90af2823-1609-4fb7-ac80-aba3d0049b74', '643224', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('cbc60cdd-03d2-403e-ad34-bd87ba567064', '643225', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('fb3d5e18-d661-45c9-9b28-fb0ca4b58960', '643226', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('6fa8e485-e27d-4356-ac74-60a812e98d08', '643228', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8a9c1c7b-995f-466f-bffe-a7240670d2a2', '643231', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('1cca1a55-f0fa-4658-91cc-9d755ba156a0', '643233', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('b2cc4b41-b070-4645-9e85-bd4035b74b1c', '643237', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('3dc57dbb-3590-4adf-9997-b0ae25cfe1eb', '643236', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('2d063212-7e50-4a43-a0db-3064dd64d1cd', '643238', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('7adad76a-f2b9-4dc9-a74b-179aa98e8518', '643239', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('741aa6ef-2ebd-4824-b80b-048953dba1cd', '643240', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('41e035d4-ee0b-40cf-88b7-99c741c3d6d0', '643241', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('8a3b7fcf-02e0-407a-9450-7469632046bb', '643242', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('98a5f972-9439-4048-8109-7f5426616882', '643243', 'Nilgiris', 'Tamil Nadu');
INSERT INTO masters.pincodes (id, code, city, state) VALUES ('86bcba38-58d8-4db1-8df8-fa8ee97ba15a', '643253', 'Nilgiris', 'Tamil Nadu');


--
-- TOC entry 4005 (class 0 OID 46593)
-- Dependencies: 245
-- Data for Name: qualifications; Type: TABLE DATA; Schema: masters; Owner: postgres
--

INSERT INTO masters.qualifications (id, name) VALUES ('b8a0799a-d4c9-4512-ae22-b8de5b2ec866', 'B.Ed. (Bachelor of Education)');
INSERT INTO masters.qualifications (id, name) VALUES ('f69a05ef-bdcf-488c-8e36-367699e09049', 'M.Ed. (Master of Education)');
INSERT INTO masters.qualifications (id, name) VALUES ('7188cf24-a2fe-43c8-a1cf-c6dd3ae0c869', 'D.El.Ed. (Diploma in Elementary Education)');
INSERT INTO masters.qualifications (id, name) VALUES ('d1e1d498-9bce-4333-8a5e-402f1f4ef28f', 'B.El.Ed. (Bachelor of Elementary Education)');
INSERT INTO masters.qualifications (id, name) VALUES ('9f8b64d4-b9ac-4d01-8ab1-161f2be5aeb3', 'B.A.');
INSERT INTO masters.qualifications (id, name) VALUES ('79611698-3e8c-4fab-b62c-51db7b153589', 'M.A.');
INSERT INTO masters.qualifications (id, name) VALUES ('e9c908f6-9828-48ca-b05d-5ba8d985a33b', 'B.Sc.');
INSERT INTO masters.qualifications (id, name) VALUES ('ef97c172-396d-47bb-8e18-50ae02a0f7b9', 'M.Sc.');
INSERT INTO masters.qualifications (id, name) VALUES ('d039f883-48a6-426e-92f4-77b661f4117e', 'B.Com.');
INSERT INTO masters.qualifications (id, name) VALUES ('a95fbaa9-b252-47a5-9e47-4c7f9b01258c', 'M.Com.');
INSERT INTO masters.qualifications (id, name) VALUES ('b0593fcc-7861-4ba0-940d-cf3a0da09144', 'B.Tech.');
INSERT INTO masters.qualifications (id, name) VALUES ('ca3913ea-78a2-4e17-b77c-574063286497', 'M.Tech.');
INSERT INTO masters.qualifications (id, name) VALUES ('5359eb48-3196-4710-ae8c-e578ba80a61d', 'MBA');
INSERT INTO masters.qualifications (id, name) VALUES ('c89e0077-e811-4a0e-8877-13602435dd17', 'MCA');
INSERT INTO masters.qualifications (id, name) VALUES ('f7bf454e-ff95-40be-9b9f-b01b9837d478', 'BCA');
INSERT INTO masters.qualifications (id, name) VALUES ('4a7c5ec1-522f-4da2-a507-fca82b31ea48', 'Ph.D.');
INSERT INTO masters.qualifications (id, name) VALUES ('31d88958-29b8-4363-86d7-493f19a01360', 'M.Phil.');
INSERT INTO masters.qualifications (id, name) VALUES ('7d63b4ee-c827-409e-b6d2-f0edd373acbe', 'B.P.Ed. (Bachelor of Physical Education)');
INSERT INTO masters.qualifications (id, name) VALUES ('97a9f3bb-1260-472f-9e50-f3d8c4fc3105', 'M.P.Ed. (Master of Physical Education)');
INSERT INTO masters.qualifications (id, name) VALUES ('4f465c79-053f-4518-ad01-9db555474cd7', 'Diploma in Teacher Education');


--
-- TOC entry 4006 (class 0 OID 46597)
-- Dependencies: 246
-- Data for Name: relationship_type; Type: TABLE DATA; Schema: masters; Owner: postgres
--

INSERT INTO masters.relationship_type (id, name, description) VALUES ('8187a1f0-c330-488d-bb6a-73e2e9c760e5', 'Father', 'Biological or adoptive father');
INSERT INTO masters.relationship_type (id, name, description) VALUES ('f13aee0d-21cf-4f92-9fd9-111bad25fc98', 'Mother', 'Biological or adoptive mother');
INSERT INTO masters.relationship_type (id, name, description) VALUES ('463cd413-361f-42cb-937f-6d064850c4b9', 'Guardian', 'Legal guardian');
INSERT INTO masters.relationship_type (id, name, description) VALUES ('e95ed54c-b595-49b1-b5e2-58e0f4f38d49', 'Grandfather', 'Paternal or maternal grandfather');
INSERT INTO masters.relationship_type (id, name, description) VALUES ('6af4f981-97a5-4f35-a20c-89793a4b1a81', 'Grandmother', 'Paternal or maternal grandmother');
INSERT INTO masters.relationship_type (id, name, description) VALUES ('cf1af08d-0b99-4039-9980-bba132463c6d', 'Uncle', 'Paternal or maternal uncle');
INSERT INTO masters.relationship_type (id, name, description) VALUES ('a4a1054c-e3d3-4289-b599-9e9562c39017', 'Aunt', 'Paternal or maternal aunt');
INSERT INTO masters.relationship_type (id, name, description) VALUES ('da5e2b6a-5ff3-40d3-919a-e3f5a383646c', 'Elder Sibling', 'Older brother or sister');
INSERT INTO masters.relationship_type (id, name, description) VALUES ('76760ab0-af43-427b-9a41-6b5a3f25eec9', 'Step Father', 'Step father');
INSERT INTO masters.relationship_type (id, name, description) VALUES ('2bb4785d-87fc-4f95-9709-b654123b7b66', 'Step Mother', 'Step mother');
INSERT INTO masters.relationship_type (id, name, description) VALUES ('ae08e70c-a5a7-49eb-9b05-46c4804056b0', 'Foster Parent', 'Foster parent or caretaker');
INSERT INTO masters.relationship_type (id, name, description) VALUES ('b78ca855-b170-4b00-b7d7-16585c0c2880', 'Other', 'Other relationship');


--
-- TOC entry 4007 (class 0 OID 46601)
-- Dependencies: 247
-- Data for Name: sections; Type: TABLE DATA; Schema: masters; Owner: postgres
--

INSERT INTO masters.sections (id, name) VALUES ('12db1a72-5b80-4231-8b7f-17c16e76a2cc', 'A');
INSERT INTO masters.sections (id, name) VALUES ('33ae2095-1342-4fa0-8980-f62efc49d628', 'B');
INSERT INTO masters.sections (id, name) VALUES ('6e9e72a2-ef24-475b-b8ce-c2b4dceeafa4', 'C');
INSERT INTO masters.sections (id, name) VALUES ('aa067070-991d-499d-8bd2-87be17c91025', 'D');
INSERT INTO masters.sections (id, name) VALUES ('37b70689-24eb-4410-998a-7cc2d5b8e42e', 'E');
INSERT INTO masters.sections (id, name) VALUES ('2b15b0c9-cfaf-4c9b-9e6a-b495092c0abd', 'F');


--
-- TOC entry 4008 (class 0 OID 46605)
-- Dependencies: 248
-- Data for Name: subjects; Type: TABLE DATA; Schema: masters; Owner: postgres
--

INSERT INTO masters.subjects (id, name) VALUES ('005c1e93-7753-45cc-a2c8-94fb0f42020e', 'Tamil');
INSERT INTO masters.subjects (id, name) VALUES ('606cb45a-7c9b-4ed7-bc22-bf8aacdf68a2', 'English');
INSERT INTO masters.subjects (id, name) VALUES ('c6f0c294-2d01-4b08-8904-31148f837cee', 'Hindi');
INSERT INTO masters.subjects (id, name) VALUES ('e4bcd6de-6226-400a-8ffc-ca2d34a984b6', 'Mathematics');
INSERT INTO masters.subjects (id, name) VALUES ('724720c3-c16b-40d2-9808-be3eb3fe31be', 'Science');
INSERT INTO masters.subjects (id, name) VALUES ('e78700a2-b592-4097-90c7-336cee85ab34', 'Social Science');
INSERT INTO masters.subjects (id, name) VALUES ('62566938-f1cc-4891-926d-e82f01238816', 'Physics');
INSERT INTO masters.subjects (id, name) VALUES ('48124e60-2687-4cf3-8362-746f536774fe', 'Chemistry');
INSERT INTO masters.subjects (id, name) VALUES ('798bc8ed-c650-45d5-a676-4305959f49c1', 'Biology');
INSERT INTO masters.subjects (id, name) VALUES ('437f1f34-d6d9-4fb7-b9f2-d76454e4ddea', 'History');
INSERT INTO masters.subjects (id, name) VALUES ('268e9bb3-157f-48f6-bf9a-b74709b731d3', 'Geography');
INSERT INTO masters.subjects (id, name) VALUES ('87b0b815-2a84-4b8d-883c-c21cbb586716', 'Economics');
INSERT INTO masters.subjects (id, name) VALUES ('7cd3858c-683c-4f50-84b9-e3f2dbba1f81', 'Civics');
INSERT INTO masters.subjects (id, name) VALUES ('21f9eb19-a562-439e-942f-c9a60b0f4cfa', 'Computer Science');
INSERT INTO masters.subjects (id, name) VALUES ('72b22741-63ff-4c85-adb6-dd956ed01dc0', 'Information Technology');
INSERT INTO masters.subjects (id, name) VALUES ('ea0b1d26-d898-4fa0-8586-e68fa1377a4b', 'Business Mathematics');
INSERT INTO masters.subjects (id, name) VALUES ('612a0722-7024-4f18-8dab-9189bfd41396', 'Accountancy');
INSERT INTO masters.subjects (id, name) VALUES ('5c5b5569-1f4e-46fc-be78-d846d13a9395', 'Commerce');
INSERT INTO masters.subjects (id, name) VALUES ('6740c2e4-3843-4385-9112-fec6da4b67ca', 'French');
INSERT INTO masters.subjects (id, name) VALUES ('ae4c335d-877d-41a5-a523-5aac872b44c1', 'Sanskrit');
INSERT INTO masters.subjects (id, name) VALUES ('1f75cf93-f96b-41b8-aa24-dafd2879a648', 'Physical Education');
INSERT INTO masters.subjects (id, name) VALUES ('5ccb6ef8-ebe0-4367-ac57-5b7a24d8ef4e', 'Art & Craft');
INSERT INTO masters.subjects (id, name) VALUES ('8afd487e-e444-4ecc-9e18-93d17c79bff6', 'Music');
INSERT INTO masters.subjects (id, name) VALUES ('42ea5add-79ca-43ce-8295-900c6c137be3', 'Moral Science');
INSERT INTO masters.subjects (id, name) VALUES ('96f6fc83-17c6-4fa8-b009-e834176d8fbc', 'Environmental Science');
INSERT INTO masters.subjects (id, name) VALUES ('11a04d5c-10ad-4da3-8797-5dd0d644dd62', 'General Knowledge');


--
-- TOC entry 4009 (class 0 OID 46609)
-- Dependencies: 249
-- Data for Name: address; Type: TABLE DATA; Schema: parents; Owner: postgres
--



--
-- TOC entry 4010 (class 0 OID 46617)
-- Dependencies: 250
-- Data for Name: application_document; Type: TABLE DATA; Schema: parents; Owner: postgres
--



--
-- TOC entry 4011 (class 0 OID 46625)
-- Dependencies: 251
-- Data for Name: emergency_contact; Type: TABLE DATA; Schema: parents; Owner: postgres
--



--
-- TOC entry 4012 (class 0 OID 46631)
-- Dependencies: 252
-- Data for Name: onboarding_application; Type: TABLE DATA; Schema: parents; Owner: postgres
--



--
-- TOC entry 4013 (class 0 OID 46639)
-- Dependencies: 253
-- Data for Name: parent; Type: TABLE DATA; Schema: parents; Owner: postgres
--



--
-- TOC entry 4014 (class 0 OID 46647)
-- Dependencies: 254
-- Data for Name: parent_address; Type: TABLE DATA; Schema: parents; Owner: postgres
--



--
-- TOC entry 4015 (class 0 OID 46653)
-- Dependencies: 255
-- Data for Name: parent_contact; Type: TABLE DATA; Schema: parents; Owner: postgres
--



--
-- TOC entry 4016 (class 0 OID 46659)
-- Dependencies: 256
-- Data for Name: parent_student; Type: TABLE DATA; Schema: parents; Owner: postgres
--



--
-- TOC entry 4017 (class 0 OID 46666)
-- Dependencies: 257
-- Data for Name: student; Type: TABLE DATA; Schema: parents; Owner: postgres
--



--
-- TOC entry 4018 (class 0 OID 46674)
-- Dependencies: 258
-- Data for Name: teacher_class_sections; Type: TABLE DATA; Schema: teachers; Owner: postgres
--



--
-- TOC entry 4019 (class 0 OID 46679)
-- Dependencies: 259
-- Data for Name: teacher_languages; Type: TABLE DATA; Schema: teachers; Owner: postgres
--



--
-- TOC entry 4020 (class 0 OID 46684)
-- Dependencies: 260
-- Data for Name: teacher_subjects; Type: TABLE DATA; Schema: teachers; Owner: postgres
--



--
-- TOC entry 4021 (class 0 OID 46689)
-- Dependencies: 261
-- Data for Name: teachers; Type: TABLE DATA; Schema: teachers; Owner: postgres
--



--
-- TOC entry 3599 (class 2606 OID 46699)
-- Name: audit_event_type audit_event_type_name_key; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.audit_event_type
    ADD CONSTRAINT audit_event_type_name_key UNIQUE (name);


--
-- TOC entry 3601 (class 2606 OID 46701)
-- Name: audit_event_type audit_event_type_pkey; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.audit_event_type
    ADD CONSTRAINT audit_event_type_pkey PRIMARY KEY (id);


--
-- TOC entry 3603 (class 2606 OID 46703)
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- TOC entry 3613 (class 2606 OID 46705)
-- Name: invite invite_invite_token_hash_key; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.invite
    ADD CONSTRAINT invite_invite_token_hash_key UNIQUE (invite_token_hash);


--
-- TOC entry 3615 (class 2606 OID 46707)
-- Name: invite invite_pkey; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.invite
    ADD CONSTRAINT invite_pkey PRIMARY KEY (id);


--
-- TOC entry 3617 (class 2606 OID 46709)
-- Name: invite_status invite_status_name_key; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.invite_status
    ADD CONSTRAINT invite_status_name_key UNIQUE (name);


--
-- TOC entry 3619 (class 2606 OID 46711)
-- Name: invite_status invite_status_pkey; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.invite_status
    ADD CONSTRAINT invite_status_pkey PRIMARY KEY (id);


--
-- TOC entry 3772 (class 2606 OID 47135)
-- Name: management_user management_user_email_key; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.management_user
    ADD CONSTRAINT management_user_email_key UNIQUE (email);


--
-- TOC entry 3774 (class 2606 OID 47137)
-- Name: management_user management_user_phone_key; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.management_user
    ADD CONSTRAINT management_user_phone_key UNIQUE (phone);


--
-- TOC entry 3776 (class 2606 OID 47133)
-- Name: management_user management_user_pkey; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.management_user
    ADD CONSTRAINT management_user_pkey PRIMARY KEY (id);


--
-- TOC entry 3778 (class 2606 OID 47139)
-- Name: management_user management_user_username_key; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.management_user
    ADD CONSTRAINT management_user_username_key UNIQUE (username);


--
-- TOC entry 3623 (class 2606 OID 46713)
-- Name: otp otp_pkey; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.otp
    ADD CONSTRAINT otp_pkey PRIMARY KEY (id);


--
-- TOC entry 3625 (class 2606 OID 46715)
-- Name: otp_type otp_type_name_key; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.otp_type
    ADD CONSTRAINT otp_type_name_key UNIQUE (name);


--
-- TOC entry 3627 (class 2606 OID 46717)
-- Name: otp_type otp_type_pkey; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.otp_type
    ADD CONSTRAINT otp_type_pkey PRIMARY KEY (id);


--
-- TOC entry 3630 (class 2606 OID 46719)
-- Name: password_history password_history_pkey; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.password_history
    ADD CONSTRAINT password_history_pkey PRIMARY KEY (id);


--
-- TOC entry 3632 (class 2606 OID 46721)
-- Name: permission permission_pkey; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.permission
    ADD CONSTRAINT permission_pkey PRIMARY KEY (id);


--
-- TOC entry 3636 (class 2606 OID 46723)
-- Name: role role_name_key; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.role
    ADD CONSTRAINT role_name_key UNIQUE (name);


--
-- TOC entry 3640 (class 2606 OID 46725)
-- Name: role_permission role_permission_pkey; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.role_permission
    ADD CONSTRAINT role_permission_pkey PRIMARY KEY (id);


--
-- TOC entry 3638 (class 2606 OID 46727)
-- Name: role role_pkey; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.role
    ADD CONSTRAINT role_pkey PRIMARY KEY (id);


--
-- TOC entry 3646 (class 2606 OID 46729)
-- Name: session session_access_token_hash_key; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.session
    ADD CONSTRAINT session_access_token_hash_key UNIQUE (access_token_hash);


--
-- TOC entry 3648 (class 2606 OID 46731)
-- Name: session session_pkey; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.session
    ADD CONSTRAINT session_pkey PRIMARY KEY (id);


--
-- TOC entry 3650 (class 2606 OID 46733)
-- Name: session session_refresh_token_hash_key; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.session
    ADD CONSTRAINT session_refresh_token_hash_key UNIQUE (refresh_token_hash);


--
-- TOC entry 3634 (class 2606 OID 46735)
-- Name: permission uq_permission; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.permission
    ADD CONSTRAINT uq_permission UNIQUE (resource, action);


--
-- TOC entry 3642 (class 2606 OID 46737)
-- Name: role_permission uq_role_permission; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.role_permission
    ADD CONSTRAINT uq_role_permission UNIQUE (role_id, permission_id);


--
-- TOC entry 3657 (class 2606 OID 46739)
-- Name: user user_email_key; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth."user"
    ADD CONSTRAINT user_email_key UNIQUE (email);


--
-- TOC entry 3659 (class 2606 OID 46741)
-- Name: user user_phone_key; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth."user"
    ADD CONSTRAINT user_phone_key UNIQUE (phone);


--
-- TOC entry 3661 (class 2606 OID 46743)
-- Name: user user_pkey; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth."user"
    ADD CONSTRAINT user_pkey PRIMARY KEY (id);


--
-- TOC entry 3780 (class 2606 OID 47160)
-- Name: chain chain_name_key; Type: CONSTRAINT; Schema: management; Owner: postgres
--

ALTER TABLE ONLY management.chain
    ADD CONSTRAINT chain_name_key UNIQUE (name);


--
-- TOC entry 3782 (class 2606 OID 47158)
-- Name: chain chain_pkey; Type: CONSTRAINT; Schema: management; Owner: postgres
--

ALTER TABLE ONLY management.chain
    ADD CONSTRAINT chain_pkey PRIMARY KEY (id);


--
-- TOC entry 3663 (class 2606 OID 46745)
-- Name: management_table management_table_chain_id_branch_id_key; Type: CONSTRAINT; Schema: management; Owner: postgres
--

ALTER TABLE ONLY management.management_table
    ADD CONSTRAINT management_table_chain_id_branch_id_key UNIQUE (chain_id, branch_id);


--
-- TOC entry 3665 (class 2606 OID 46747)
-- Name: management_table management_table_pkey; Type: CONSTRAINT; Schema: management; Owner: postgres
--

ALTER TABLE ONLY management.management_table
    ADD CONSTRAINT management_table_pkey PRIMARY KEY (tenant_id);


--
-- TOC entry 3667 (class 2606 OID 46749)
-- Name: blood_group blood_group_name_key; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.blood_group
    ADD CONSTRAINT blood_group_name_key UNIQUE (name);


--
-- TOC entry 3669 (class 2606 OID 46751)
-- Name: blood_group blood_group_pkey; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.blood_group
    ADD CONSTRAINT blood_group_pkey PRIMARY KEY (id);


--
-- TOC entry 3671 (class 2606 OID 46753)
-- Name: classes classes_name_key; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.classes
    ADD CONSTRAINT classes_name_key UNIQUE (name);


--
-- TOC entry 3673 (class 2606 OID 46755)
-- Name: classes classes_pkey; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.classes
    ADD CONSTRAINT classes_pkey PRIMARY KEY (id);


--
-- TOC entry 3675 (class 2606 OID 46757)
-- Name: contact_type contact_type_name_key; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.contact_type
    ADD CONSTRAINT contact_type_name_key UNIQUE (name);


--
-- TOC entry 3677 (class 2606 OID 46759)
-- Name: contact_type contact_type_pkey; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.contact_type
    ADD CONSTRAINT contact_type_pkey PRIMARY KEY (id);


--
-- TOC entry 3679 (class 2606 OID 46761)
-- Name: document_type document_type_name_key; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.document_type
    ADD CONSTRAINT document_type_name_key UNIQUE (name);


--
-- TOC entry 3681 (class 2606 OID 46763)
-- Name: document_type document_type_pkey; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.document_type
    ADD CONSTRAINT document_type_pkey PRIMARY KEY (id);


--
-- TOC entry 3683 (class 2606 OID 46765)
-- Name: genders genders_name_key; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.genders
    ADD CONSTRAINT genders_name_key UNIQUE (name);


--
-- TOC entry 3685 (class 2606 OID 46767)
-- Name: genders genders_pkey; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.genders
    ADD CONSTRAINT genders_pkey PRIMARY KEY (id);


--
-- TOC entry 3687 (class 2606 OID 46769)
-- Name: grade grade_level_academic_year_key; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.grade
    ADD CONSTRAINT grade_level_academic_year_key UNIQUE (level, academic_year);


--
-- TOC entry 3689 (class 2606 OID 46771)
-- Name: grade grade_pkey; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.grade
    ADD CONSTRAINT grade_pkey PRIMARY KEY (id);


--
-- TOC entry 3691 (class 2606 OID 46773)
-- Name: languages languages_name_key; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.languages
    ADD CONSTRAINT languages_name_key UNIQUE (name);


--
-- TOC entry 3693 (class 2606 OID 46775)
-- Name: languages languages_pkey; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.languages
    ADD CONSTRAINT languages_pkey PRIMARY KEY (id);


--
-- TOC entry 3695 (class 2606 OID 46777)
-- Name: onboarding_status onboarding_status_name_key; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.onboarding_status
    ADD CONSTRAINT onboarding_status_name_key UNIQUE (name);


--
-- TOC entry 3697 (class 2606 OID 46779)
-- Name: onboarding_status onboarding_status_pkey; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.onboarding_status
    ADD CONSTRAINT onboarding_status_pkey PRIMARY KEY (id);


--
-- TOC entry 3699 (class 2606 OID 46781)
-- Name: pincodes pincodes_code_city_key; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.pincodes
    ADD CONSTRAINT pincodes_code_city_key UNIQUE (code, city);


--
-- TOC entry 3701 (class 2606 OID 46783)
-- Name: pincodes pincodes_pkey; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.pincodes
    ADD CONSTRAINT pincodes_pkey PRIMARY KEY (id);


--
-- TOC entry 3703 (class 2606 OID 46785)
-- Name: qualifications qualifications_name_key; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.qualifications
    ADD CONSTRAINT qualifications_name_key UNIQUE (name);


--
-- TOC entry 3705 (class 2606 OID 46787)
-- Name: qualifications qualifications_pkey; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.qualifications
    ADD CONSTRAINT qualifications_pkey PRIMARY KEY (id);


--
-- TOC entry 3707 (class 2606 OID 46789)
-- Name: relationship_type relationship_type_name_key; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.relationship_type
    ADD CONSTRAINT relationship_type_name_key UNIQUE (name);


--
-- TOC entry 3709 (class 2606 OID 46791)
-- Name: relationship_type relationship_type_pkey; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.relationship_type
    ADD CONSTRAINT relationship_type_pkey PRIMARY KEY (id);


--
-- TOC entry 3711 (class 2606 OID 46793)
-- Name: sections sections_name_key; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.sections
    ADD CONSTRAINT sections_name_key UNIQUE (name);


--
-- TOC entry 3713 (class 2606 OID 46795)
-- Name: sections sections_pkey; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.sections
    ADD CONSTRAINT sections_pkey PRIMARY KEY (id);


--
-- TOC entry 3715 (class 2606 OID 46797)
-- Name: subjects subjects_name_key; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.subjects
    ADD CONSTRAINT subjects_name_key UNIQUE (name);


--
-- TOC entry 3717 (class 2606 OID 46799)
-- Name: subjects subjects_pkey; Type: CONSTRAINT; Schema: masters; Owner: postgres
--

ALTER TABLE ONLY masters.subjects
    ADD CONSTRAINT subjects_pkey PRIMARY KEY (id);


--
-- TOC entry 3719 (class 2606 OID 46801)
-- Name: address address_pkey; Type: CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.address
    ADD CONSTRAINT address_pkey PRIMARY KEY (id);


--
-- TOC entry 3722 (class 2606 OID 46803)
-- Name: application_document application_document_pkey; Type: CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.application_document
    ADD CONSTRAINT application_document_pkey PRIMARY KEY (id);


--
-- TOC entry 3724 (class 2606 OID 46805)
-- Name: application_document application_document_tenant_id_application_id_document_type_key; Type: CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.application_document
    ADD CONSTRAINT application_document_tenant_id_application_id_document_type_key UNIQUE (tenant_id, application_id, document_type_id);


--
-- TOC entry 3726 (class 2606 OID 46807)
-- Name: emergency_contact emergency_contact_pkey; Type: CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.emergency_contact
    ADD CONSTRAINT emergency_contact_pkey PRIMARY KEY (id);


--
-- TOC entry 3731 (class 2606 OID 46809)
-- Name: onboarding_application onboarding_application_pkey; Type: CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.onboarding_application
    ADD CONSTRAINT onboarding_application_pkey PRIMARY KEY (id);


--
-- TOC entry 3736 (class 2606 OID 46811)
-- Name: parent_address parent_address_pkey; Type: CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.parent_address
    ADD CONSTRAINT parent_address_pkey PRIMARY KEY (id);


--
-- TOC entry 3738 (class 2606 OID 46813)
-- Name: parent_address parent_address_tenant_id_parent_id_address_id_key; Type: CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.parent_address
    ADD CONSTRAINT parent_address_tenant_id_parent_id_address_id_key UNIQUE (tenant_id, parent_id, address_id);


--
-- TOC entry 3740 (class 2606 OID 46815)
-- Name: parent_contact parent_contact_pkey; Type: CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.parent_contact
    ADD CONSTRAINT parent_contact_pkey PRIMARY KEY (id);


--
-- TOC entry 3742 (class 2606 OID 46817)
-- Name: parent_contact parent_contact_tenant_id_parent_id_contact_type_id_value_key; Type: CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.parent_contact
    ADD CONSTRAINT parent_contact_tenant_id_parent_id_contact_type_id_value_key UNIQUE (tenant_id, parent_id, contact_type_id, value);


--
-- TOC entry 3734 (class 2606 OID 46819)
-- Name: parent parent_pkey; Type: CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.parent
    ADD CONSTRAINT parent_pkey PRIMARY KEY (id);


--
-- TOC entry 3744 (class 2606 OID 46821)
-- Name: parent_student parent_student_pkey; Type: CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.parent_student
    ADD CONSTRAINT parent_student_pkey PRIMARY KEY (id);


--
-- TOC entry 3746 (class 2606 OID 46823)
-- Name: parent_student parent_student_tenant_id_parent_id_student_id_key; Type: CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.parent_student
    ADD CONSTRAINT parent_student_tenant_id_parent_id_student_id_key UNIQUE (tenant_id, parent_id, student_id);


--
-- TOC entry 3749 (class 2606 OID 46825)
-- Name: student student_pkey; Type: CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.student
    ADD CONSTRAINT student_pkey PRIMARY KEY (id);


--
-- TOC entry 3751 (class 2606 OID 46827)
-- Name: teacher_class_sections teacher_class_sections_pkey; Type: CONSTRAINT; Schema: teachers; Owner: postgres
--

ALTER TABLE ONLY teachers.teacher_class_sections
    ADD CONSTRAINT teacher_class_sections_pkey PRIMARY KEY (id);


--
-- TOC entry 3753 (class 2606 OID 46829)
-- Name: teacher_class_sections teacher_class_sections_tenant_id_teacher_id_class_id_sectio_key; Type: CONSTRAINT; Schema: teachers; Owner: postgres
--

ALTER TABLE ONLY teachers.teacher_class_sections
    ADD CONSTRAINT teacher_class_sections_tenant_id_teacher_id_class_id_sectio_key UNIQUE (tenant_id, teacher_id, class_id, section_id);


--
-- TOC entry 3755 (class 2606 OID 46831)
-- Name: teacher_languages teacher_languages_pkey; Type: CONSTRAINT; Schema: teachers; Owner: postgres
--

ALTER TABLE ONLY teachers.teacher_languages
    ADD CONSTRAINT teacher_languages_pkey PRIMARY KEY (id);


--
-- TOC entry 3757 (class 2606 OID 46833)
-- Name: teacher_languages teacher_languages_tenant_id_teacher_id_language_id_key; Type: CONSTRAINT; Schema: teachers; Owner: postgres
--

ALTER TABLE ONLY teachers.teacher_languages
    ADD CONSTRAINT teacher_languages_tenant_id_teacher_id_language_id_key UNIQUE (tenant_id, teacher_id, language_id);


--
-- TOC entry 3759 (class 2606 OID 46835)
-- Name: teacher_subjects teacher_subjects_pkey; Type: CONSTRAINT; Schema: teachers; Owner: postgres
--

ALTER TABLE ONLY teachers.teacher_subjects
    ADD CONSTRAINT teacher_subjects_pkey PRIMARY KEY (id);


--
-- TOC entry 3761 (class 2606 OID 46837)
-- Name: teacher_subjects teacher_subjects_tenant_id_teacher_id_subject_id_key; Type: CONSTRAINT; Schema: teachers; Owner: postgres
--

ALTER TABLE ONLY teachers.teacher_subjects
    ADD CONSTRAINT teacher_subjects_tenant_id_teacher_id_subject_id_key UNIQUE (tenant_id, teacher_id, subject_id);


--
-- TOC entry 3764 (class 2606 OID 46839)
-- Name: teachers teachers_pkey; Type: CONSTRAINT; Schema: teachers; Owner: postgres
--

ALTER TABLE ONLY teachers.teachers
    ADD CONSTRAINT teachers_pkey PRIMARY KEY (id);


--
-- TOC entry 3766 (class 2606 OID 46841)
-- Name: teachers teachers_tenant_id_mobile_key; Type: CONSTRAINT; Schema: teachers; Owner: postgres
--

ALTER TABLE ONLY teachers.teachers
    ADD CONSTRAINT teachers_tenant_id_mobile_key UNIQUE (tenant_id, mobile);


--
-- TOC entry 3604 (class 1259 OID 46842)
-- Name: idx_audit_metadata_gin; Type: INDEX; Schema: auth; Owner: postgres
--

CREATE INDEX idx_audit_metadata_gin ON auth.audit_log USING gin (metadata);


--
-- TOC entry 3605 (class 1259 OID 46843)
-- Name: idx_audit_suspicious; Type: INDEX; Schema: auth; Owner: postgres
--

CREATE INDEX idx_audit_suspicious ON auth.audit_log USING btree (tenant_id, created_at DESC) WHERE (is_suspicious = true);


--
-- TOC entry 3606 (class 1259 OID 46844)
-- Name: idx_audit_tenant_time; Type: INDEX; Schema: auth; Owner: postgres
--

CREATE INDEX idx_audit_tenant_time ON auth.audit_log USING btree (tenant_id, created_at DESC);


--
-- TOC entry 3607 (class 1259 OID 46845)
-- Name: idx_audit_user; Type: INDEX; Schema: auth; Owner: postgres
--

CREATE INDEX idx_audit_user ON auth.audit_log USING btree (user_id) WHERE (user_id IS NOT NULL);


--
-- TOC entry 3608 (class 1259 OID 46846)
-- Name: idx_invite_email; Type: INDEX; Schema: auth; Owner: postgres
--

CREATE INDEX idx_invite_email ON auth.invite USING btree (email) WHERE (email IS NOT NULL);


--
-- TOC entry 3609 (class 1259 OID 46847)
-- Name: idx_invite_phone; Type: INDEX; Schema: auth; Owner: postgres
--

CREATE INDEX idx_invite_phone ON auth.invite USING btree (phone) WHERE (phone IS NOT NULL);


--
-- TOC entry 3610 (class 1259 OID 46848)
-- Name: idx_invite_status; Type: INDEX; Schema: auth; Owner: postgres
--

CREATE INDEX idx_invite_status ON auth.invite USING btree (status_id);


--
-- TOC entry 3611 (class 1259 OID 46849)
-- Name: idx_invite_tenant; Type: INDEX; Schema: auth; Owner: postgres
--

CREATE INDEX idx_invite_tenant ON auth.invite USING btree (tenant_id);


--
-- TOC entry 3767 (class 1259 OID 47147)
-- Name: idx_management_user_chain_id; Type: INDEX; Schema: auth; Owner: postgres
--

CREATE INDEX idx_management_user_chain_id ON auth.management_user USING btree (chain_id);


--
-- TOC entry 3768 (class 1259 OID 47145)
-- Name: idx_management_user_email; Type: INDEX; Schema: auth; Owner: postgres
--

CREATE INDEX idx_management_user_email ON auth.management_user USING btree (email) WHERE (email IS NOT NULL);


--
-- TOC entry 3769 (class 1259 OID 47148)
-- Name: idx_management_user_locked; Type: INDEX; Schema: auth; Owner: postgres
--

CREATE INDEX idx_management_user_locked ON auth.management_user USING btree (locked_until) WHERE (locked_until IS NOT NULL);


--
-- TOC entry 3770 (class 1259 OID 47146)
-- Name: idx_management_user_phone; Type: INDEX; Schema: auth; Owner: postgres
--

CREATE INDEX idx_management_user_phone ON auth.management_user USING btree (phone) WHERE (phone IS NOT NULL);


--
-- TOC entry 3620 (class 1259 OID 46850)
-- Name: idx_otp_active; Type: INDEX; Schema: auth; Owner: postgres
--

CREATE INDEX idx_otp_active ON auth.otp USING btree (user_id, expires_at) WHERE (is_used = false);


--
-- TOC entry 3621 (class 1259 OID 46851)
-- Name: idx_otp_user; Type: INDEX; Schema: auth; Owner: postgres
--

CREATE INDEX idx_otp_user ON auth.otp USING btree (user_id);


--
-- TOC entry 3628 (class 1259 OID 46852)
-- Name: idx_pwd_history_user; Type: INDEX; Schema: auth; Owner: postgres
--

CREATE INDEX idx_pwd_history_user ON auth.password_history USING btree (user_id, created_at DESC);


--
-- TOC entry 3643 (class 1259 OID 46853)
-- Name: idx_session_live; Type: INDEX; Schema: auth; Owner: postgres
--

CREATE INDEX idx_session_live ON auth.session USING btree (user_id, expires_at) WHERE (revoked_at IS NULL);


--
-- TOC entry 3644 (class 1259 OID 46854)
-- Name: idx_session_user; Type: INDEX; Schema: auth; Owner: postgres
--

CREATE INDEX idx_session_user ON auth.session USING btree (user_id);


--
-- TOC entry 3651 (class 1259 OID 46855)
-- Name: idx_user_email; Type: INDEX; Schema: auth; Owner: postgres
--

CREATE INDEX idx_user_email ON auth."user" USING btree (email) WHERE (email IS NOT NULL);


--
-- TOC entry 3652 (class 1259 OID 46856)
-- Name: idx_user_locked; Type: INDEX; Schema: auth; Owner: postgres
--

CREATE INDEX idx_user_locked ON auth."user" USING btree (locked_until) WHERE (locked_until IS NOT NULL);


--
-- TOC entry 3653 (class 1259 OID 46857)
-- Name: idx_user_phone; Type: INDEX; Schema: auth; Owner: postgres
--

CREATE INDEX idx_user_phone ON auth."user" USING btree (phone) WHERE (phone IS NOT NULL);


--
-- TOC entry 3654 (class 1259 OID 46858)
-- Name: idx_user_role; Type: INDEX; Schema: auth; Owner: postgres
--

CREATE INDEX idx_user_role ON auth."user" USING btree (role_id);


--
-- TOC entry 3655 (class 1259 OID 46859)
-- Name: idx_user_tenant; Type: INDEX; Schema: auth; Owner: postgres
--

CREATE INDEX idx_user_tenant ON auth."user" USING btree (tenant_id);


--
-- TOC entry 3783 (class 1259 OID 47161)
-- Name: idx_chain_id; Type: INDEX; Schema: management; Owner: postgres
--

CREATE INDEX idx_chain_id ON management.chain USING btree (id);


--
-- TOC entry 3720 (class 1259 OID 46860)
-- Name: idx_address_tenant_id; Type: INDEX; Schema: parents; Owner: postgres
--

CREATE INDEX idx_address_tenant_id ON parents.address USING btree (tenant_id);


--
-- TOC entry 3727 (class 1259 OID 46861)
-- Name: idx_emergency_contact_student; Type: INDEX; Schema: parents; Owner: postgres
--

CREATE INDEX idx_emergency_contact_student ON parents.emergency_contact USING btree (student_id);


--
-- TOC entry 3728 (class 1259 OID 46862)
-- Name: idx_onboarding_application_student; Type: INDEX; Schema: parents; Owner: postgres
--

CREATE INDEX idx_onboarding_application_student ON parents.onboarding_application USING btree (student_id);


--
-- TOC entry 3729 (class 1259 OID 46863)
-- Name: idx_onboarding_application_tenant; Type: INDEX; Schema: parents; Owner: postgres
--

CREATE INDEX idx_onboarding_application_tenant ON parents.onboarding_application USING btree (tenant_id);


--
-- TOC entry 3732 (class 1259 OID 46864)
-- Name: idx_parent_tenant_id; Type: INDEX; Schema: parents; Owner: postgres
--

CREATE INDEX idx_parent_tenant_id ON parents.parent USING btree (tenant_id);


--
-- TOC entry 3747 (class 1259 OID 46865)
-- Name: idx_student_tenant_id; Type: INDEX; Schema: parents; Owner: postgres
--

CREATE INDEX idx_student_tenant_id ON parents.student USING btree (tenant_id);


--
-- TOC entry 3762 (class 1259 OID 46866)
-- Name: idx_teachers_tenant_id; Type: INDEX; Schema: teachers; Owner: postgres
--

CREATE INDEX idx_teachers_tenant_id ON teachers.teachers USING btree (tenant_id);


--
-- TOC entry 3838 (class 2620 OID 47149)
-- Name: management_user trg_management_user_updated_at; Type: TRIGGER; Schema: auth; Owner: postgres
--

CREATE TRIGGER trg_management_user_updated_at BEFORE UPDATE ON auth.management_user FOR EACH ROW EXECUTE FUNCTION auth.set_updated_at();


--
-- TOC entry 3837 (class 2620 OID 46867)
-- Name: user trg_user_updated_at; Type: TRIGGER; Schema: auth; Owner: postgres
--

CREATE TRIGGER trg_user_updated_at BEFORE UPDATE ON auth."user" FOR EACH ROW EXECUTE FUNCTION auth.set_updated_at();


--
-- TOC entry 3839 (class 2620 OID 47162)
-- Name: chain trg_chain_updated_at; Type: TRIGGER; Schema: management; Owner: postgres
--

CREATE TRIGGER trg_chain_updated_at BEFORE UPDATE ON management.chain FOR EACH ROW EXECUTE FUNCTION auth.set_updated_at();


--
-- TOC entry 3784 (class 2606 OID 46868)
-- Name: audit_log audit_log_event_type_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.audit_log
    ADD CONSTRAINT audit_log_event_type_id_fkey FOREIGN KEY (event_type_id) REFERENCES auth.audit_event_type(id);


--
-- TOC entry 3785 (class 2606 OID 46873)
-- Name: audit_log audit_log_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.audit_log
    ADD CONSTRAINT audit_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth."user"(id) ON DELETE SET NULL;


--
-- TOC entry 3786 (class 2606 OID 46878)
-- Name: invite invite_invited_by_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.invite
    ADD CONSTRAINT invite_invited_by_user_id_fkey FOREIGN KEY (invited_by_user_id) REFERENCES auth."user"(id);


--
-- TOC entry 3787 (class 2606 OID 46883)
-- Name: invite invite_status_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.invite
    ADD CONSTRAINT invite_status_id_fkey FOREIGN KEY (status_id) REFERENCES auth.invite_status(id);


--
-- TOC entry 3788 (class 2606 OID 46888)
-- Name: invite invite_target_role_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.invite
    ADD CONSTRAINT invite_target_role_id_fkey FOREIGN KEY (target_role_id) REFERENCES auth.role(id);


--
-- TOC entry 3835 (class 2606 OID 47168)
-- Name: management_user management_user_chain_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.management_user
    ADD CONSTRAINT management_user_chain_id_fkey FOREIGN KEY (chain_id) REFERENCES management.chain(id);


--
-- TOC entry 3836 (class 2606 OID 47140)
-- Name: management_user management_user_tenant_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.management_user
    ADD CONSTRAINT management_user_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES management.management_table(tenant_id);


--
-- TOC entry 3789 (class 2606 OID 46893)
-- Name: otp otp_otp_type_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.otp
    ADD CONSTRAINT otp_otp_type_id_fkey FOREIGN KEY (otp_type_id) REFERENCES auth.otp_type(id);


--
-- TOC entry 3790 (class 2606 OID 46898)
-- Name: otp otp_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.otp
    ADD CONSTRAINT otp_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth."user"(id) ON DELETE CASCADE;


--
-- TOC entry 3791 (class 2606 OID 46903)
-- Name: password_history password_history_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.password_history
    ADD CONSTRAINT password_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth."user"(id) ON DELETE CASCADE;


--
-- TOC entry 3792 (class 2606 OID 46908)
-- Name: role_permission role_permission_permission_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.role_permission
    ADD CONSTRAINT role_permission_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES auth.permission(id) ON DELETE CASCADE;


--
-- TOC entry 3793 (class 2606 OID 46913)
-- Name: role_permission role_permission_role_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.role_permission
    ADD CONSTRAINT role_permission_role_id_fkey FOREIGN KEY (role_id) REFERENCES auth.role(id) ON DELETE CASCADE;


--
-- TOC entry 3794 (class 2606 OID 46918)
-- Name: session session_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.session
    ADD CONSTRAINT session_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth."user"(id) ON DELETE CASCADE;


--
-- TOC entry 3795 (class 2606 OID 46923)
-- Name: user user_role_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth."user"
    ADD CONSTRAINT user_role_id_fkey FOREIGN KEY (role_id) REFERENCES auth.role(id);


--
-- TOC entry 3796 (class 2606 OID 47163)
-- Name: management_table management_table_chain_id_fkey; Type: FK CONSTRAINT; Schema: management; Owner: postgres
--

ALTER TABLE ONLY management.management_table
    ADD CONSTRAINT management_table_chain_id_fkey FOREIGN KEY (chain_id) REFERENCES management.chain(id);


--
-- TOC entry 3797 (class 2606 OID 46928)
-- Name: address address_tenant_id_fkey; Type: FK CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.address
    ADD CONSTRAINT address_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES management.management_table(tenant_id);


--
-- TOC entry 3798 (class 2606 OID 46933)
-- Name: application_document application_document_application_id_fkey; Type: FK CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.application_document
    ADD CONSTRAINT application_document_application_id_fkey FOREIGN KEY (application_id) REFERENCES parents.onboarding_application(id) ON DELETE CASCADE;


--
-- TOC entry 3799 (class 2606 OID 46938)
-- Name: application_document application_document_document_type_id_fkey; Type: FK CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.application_document
    ADD CONSTRAINT application_document_document_type_id_fkey FOREIGN KEY (document_type_id) REFERENCES masters.document_type(id);


--
-- TOC entry 3800 (class 2606 OID 46943)
-- Name: application_document application_document_tenant_id_fkey; Type: FK CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.application_document
    ADD CONSTRAINT application_document_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES management.management_table(tenant_id);


--
-- TOC entry 3801 (class 2606 OID 46948)
-- Name: emergency_contact emergency_contact_student_id_fkey; Type: FK CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.emergency_contact
    ADD CONSTRAINT emergency_contact_student_id_fkey FOREIGN KEY (student_id) REFERENCES parents.student(id) ON DELETE CASCADE;


--
-- TOC entry 3802 (class 2606 OID 46953)
-- Name: emergency_contact emergency_contact_tenant_id_fkey; Type: FK CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.emergency_contact
    ADD CONSTRAINT emergency_contact_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES management.management_table(tenant_id);


--
-- TOC entry 3803 (class 2606 OID 46958)
-- Name: onboarding_application onboarding_application_status_id_fkey; Type: FK CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.onboarding_application
    ADD CONSTRAINT onboarding_application_status_id_fkey FOREIGN KEY (status_id) REFERENCES masters.onboarding_status(id);


--
-- TOC entry 3804 (class 2606 OID 46963)
-- Name: onboarding_application onboarding_application_student_id_fkey; Type: FK CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.onboarding_application
    ADD CONSTRAINT onboarding_application_student_id_fkey FOREIGN KEY (student_id) REFERENCES parents.student(id);


--
-- TOC entry 3805 (class 2606 OID 46968)
-- Name: onboarding_application onboarding_application_submitted_by_parent_id_fkey; Type: FK CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.onboarding_application
    ADD CONSTRAINT onboarding_application_submitted_by_parent_id_fkey FOREIGN KEY (submitted_by_parent_id) REFERENCES parents.parent(id);


--
-- TOC entry 3806 (class 2606 OID 46973)
-- Name: onboarding_application onboarding_application_tenant_id_fkey; Type: FK CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.onboarding_application
    ADD CONSTRAINT onboarding_application_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES management.management_table(tenant_id);


--
-- TOC entry 3808 (class 2606 OID 46978)
-- Name: parent_address parent_address_address_id_fkey; Type: FK CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.parent_address
    ADD CONSTRAINT parent_address_address_id_fkey FOREIGN KEY (address_id) REFERENCES parents.address(id) ON DELETE CASCADE;


--
-- TOC entry 3809 (class 2606 OID 46983)
-- Name: parent_address parent_address_parent_id_fkey; Type: FK CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.parent_address
    ADD CONSTRAINT parent_address_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES parents.parent(id) ON DELETE CASCADE;


--
-- TOC entry 3810 (class 2606 OID 46988)
-- Name: parent_address parent_address_tenant_id_fkey; Type: FK CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.parent_address
    ADD CONSTRAINT parent_address_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES management.management_table(tenant_id);


--
-- TOC entry 3811 (class 2606 OID 46993)
-- Name: parent_contact parent_contact_contact_type_id_fkey; Type: FK CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.parent_contact
    ADD CONSTRAINT parent_contact_contact_type_id_fkey FOREIGN KEY (contact_type_id) REFERENCES masters.contact_type(id);


--
-- TOC entry 3812 (class 2606 OID 46998)
-- Name: parent_contact parent_contact_parent_id_fkey; Type: FK CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.parent_contact
    ADD CONSTRAINT parent_contact_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES parents.parent(id) ON DELETE CASCADE;


--
-- TOC entry 3813 (class 2606 OID 47003)
-- Name: parent_contact parent_contact_tenant_id_fkey; Type: FK CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.parent_contact
    ADD CONSTRAINT parent_contact_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES management.management_table(tenant_id);


--
-- TOC entry 3814 (class 2606 OID 47008)
-- Name: parent_student parent_student_parent_id_fkey; Type: FK CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.parent_student
    ADD CONSTRAINT parent_student_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES parents.parent(id) ON DELETE CASCADE;


--
-- TOC entry 3815 (class 2606 OID 47013)
-- Name: parent_student parent_student_relationship_type_id_fkey; Type: FK CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.parent_student
    ADD CONSTRAINT parent_student_relationship_type_id_fkey FOREIGN KEY (relationship_type_id) REFERENCES masters.relationship_type(id);


--
-- TOC entry 3816 (class 2606 OID 47018)
-- Name: parent_student parent_student_student_id_fkey; Type: FK CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.parent_student
    ADD CONSTRAINT parent_student_student_id_fkey FOREIGN KEY (student_id) REFERENCES parents.student(id) ON DELETE CASCADE;


--
-- TOC entry 3817 (class 2606 OID 47023)
-- Name: parent_student parent_student_tenant_id_fkey; Type: FK CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.parent_student
    ADD CONSTRAINT parent_student_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES management.management_table(tenant_id);


--
-- TOC entry 3807 (class 2606 OID 47028)
-- Name: parent parent_tenant_id_fkey; Type: FK CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.parent
    ADD CONSTRAINT parent_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES management.management_table(tenant_id);


--
-- TOC entry 3818 (class 2606 OID 47033)
-- Name: student student_blood_group_id_fkey; Type: FK CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.student
    ADD CONSTRAINT student_blood_group_id_fkey FOREIGN KEY (blood_group_id) REFERENCES masters.blood_group(id);


--
-- TOC entry 3819 (class 2606 OID 47038)
-- Name: student student_grade_applying_id_fkey; Type: FK CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.student
    ADD CONSTRAINT student_grade_applying_id_fkey FOREIGN KEY (grade_applying_id) REFERENCES masters.grade(id);


--
-- TOC entry 3820 (class 2606 OID 47043)
-- Name: student student_tenant_id_fkey; Type: FK CONSTRAINT; Schema: parents; Owner: postgres
--

ALTER TABLE ONLY parents.student
    ADD CONSTRAINT student_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES management.management_table(tenant_id);


--
-- TOC entry 3821 (class 2606 OID 47048)
-- Name: teacher_class_sections teacher_class_sections_class_id_fkey; Type: FK CONSTRAINT; Schema: teachers; Owner: postgres
--

ALTER TABLE ONLY teachers.teacher_class_sections
    ADD CONSTRAINT teacher_class_sections_class_id_fkey FOREIGN KEY (class_id) REFERENCES masters.classes(id);


--
-- TOC entry 3822 (class 2606 OID 47053)
-- Name: teacher_class_sections teacher_class_sections_section_id_fkey; Type: FK CONSTRAINT; Schema: teachers; Owner: postgres
--

ALTER TABLE ONLY teachers.teacher_class_sections
    ADD CONSTRAINT teacher_class_sections_section_id_fkey FOREIGN KEY (section_id) REFERENCES masters.sections(id);


--
-- TOC entry 3823 (class 2606 OID 47058)
-- Name: teacher_class_sections teacher_class_sections_teacher_id_fkey; Type: FK CONSTRAINT; Schema: teachers; Owner: postgres
--

ALTER TABLE ONLY teachers.teacher_class_sections
    ADD CONSTRAINT teacher_class_sections_teacher_id_fkey FOREIGN KEY (teacher_id) REFERENCES teachers.teachers(id) ON DELETE CASCADE;


--
-- TOC entry 3824 (class 2606 OID 47063)
-- Name: teacher_class_sections teacher_class_sections_tenant_id_fkey; Type: FK CONSTRAINT; Schema: teachers; Owner: postgres
--

ALTER TABLE ONLY teachers.teacher_class_sections
    ADD CONSTRAINT teacher_class_sections_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES management.management_table(tenant_id);


--
-- TOC entry 3825 (class 2606 OID 47068)
-- Name: teacher_languages teacher_languages_language_id_fkey; Type: FK CONSTRAINT; Schema: teachers; Owner: postgres
--

ALTER TABLE ONLY teachers.teacher_languages
    ADD CONSTRAINT teacher_languages_language_id_fkey FOREIGN KEY (language_id) REFERENCES masters.languages(id);


--
-- TOC entry 3826 (class 2606 OID 47073)
-- Name: teacher_languages teacher_languages_teacher_id_fkey; Type: FK CONSTRAINT; Schema: teachers; Owner: postgres
--

ALTER TABLE ONLY teachers.teacher_languages
    ADD CONSTRAINT teacher_languages_teacher_id_fkey FOREIGN KEY (teacher_id) REFERENCES teachers.teachers(id) ON DELETE CASCADE;


--
-- TOC entry 3827 (class 2606 OID 47078)
-- Name: teacher_languages teacher_languages_tenant_id_fkey; Type: FK CONSTRAINT; Schema: teachers; Owner: postgres
--

ALTER TABLE ONLY teachers.teacher_languages
    ADD CONSTRAINT teacher_languages_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES management.management_table(tenant_id);


--
-- TOC entry 3828 (class 2606 OID 47083)
-- Name: teacher_subjects teacher_subjects_subject_id_fkey; Type: FK CONSTRAINT; Schema: teachers; Owner: postgres
--

ALTER TABLE ONLY teachers.teacher_subjects
    ADD CONSTRAINT teacher_subjects_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES masters.subjects(id);


--
-- TOC entry 3829 (class 2606 OID 47088)
-- Name: teacher_subjects teacher_subjects_teacher_id_fkey; Type: FK CONSTRAINT; Schema: teachers; Owner: postgres
--

ALTER TABLE ONLY teachers.teacher_subjects
    ADD CONSTRAINT teacher_subjects_teacher_id_fkey FOREIGN KEY (teacher_id) REFERENCES teachers.teachers(id) ON DELETE CASCADE;


--
-- TOC entry 3830 (class 2606 OID 47093)
-- Name: teacher_subjects teacher_subjects_tenant_id_fkey; Type: FK CONSTRAINT; Schema: teachers; Owner: postgres
--

ALTER TABLE ONLY teachers.teacher_subjects
    ADD CONSTRAINT teacher_subjects_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES management.management_table(tenant_id);


--
-- TOC entry 3831 (class 2606 OID 47098)
-- Name: teachers teachers_gender_id_fkey; Type: FK CONSTRAINT; Schema: teachers; Owner: postgres
--

ALTER TABLE ONLY teachers.teachers
    ADD CONSTRAINT teachers_gender_id_fkey FOREIGN KEY (gender_id) REFERENCES masters.genders(id);


--
-- TOC entry 3832 (class 2606 OID 47103)
-- Name: teachers teachers_pincode_id_fkey; Type: FK CONSTRAINT; Schema: teachers; Owner: postgres
--

ALTER TABLE ONLY teachers.teachers
    ADD CONSTRAINT teachers_pincode_id_fkey FOREIGN KEY (pincode_id) REFERENCES masters.pincodes(id);


--
-- TOC entry 3833 (class 2606 OID 47108)
-- Name: teachers teachers_qualification_id_fkey; Type: FK CONSTRAINT; Schema: teachers; Owner: postgres
--

ALTER TABLE ONLY teachers.teachers
    ADD CONSTRAINT teachers_qualification_id_fkey FOREIGN KEY (qualification_id) REFERENCES masters.qualifications(id);


--
-- TOC entry 3834 (class 2606 OID 47113)
-- Name: teachers teachers_tenant_id_fkey; Type: FK CONSTRAINT; Schema: teachers; Owner: postgres
--

ALTER TABLE ONLY teachers.teachers
    ADD CONSTRAINT teachers_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES management.management_table(tenant_id);


-- Completed on 2026-06-02 02:30:55 IST

--
-- PostgreSQL database dump complete
--

\unrestrict nkrJM2SC0KBOYHHeDWN2ewdeEa46prwFd1a6Vhh9iMequJkBx6cOPdaFLQk9yNW

