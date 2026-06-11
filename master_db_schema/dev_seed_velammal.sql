-- ================================================================
-- EDUPULSE — DEV SEED DATA
-- Story : Velammal Educational Trust onboards with 2 branches
--          Chennai (CBSE) and Madurai (State Board).
--          Full lifecycle: signup → verify → pay → invoice → refund
--
-- Run order: 01_auth → 02_onboarding → 04_billing → 004_migration → this file
-- Note: chain is inserted before management_user because management_user.chain_id
--       references onboarding.chain.id.
--
-- Fixed UUID map
-- ── Auth ──────────────────────────────────────────────────────
--  management_user : aaaaaaaa-0001-4000-8000-000000000001
--  otp (used)      : aaaaaaaa-0020-4000-8000-000000000020
--  session         : aaaaaaaa-0010-4000-8000-000000000010
--  invite          : aaaaaaaa-0030-4000-8000-000000000030
--  audit_log[1-6]  : aaaaaaaa-0040..0045-4000-8000-000000000000
-- ── Onboarding ────────────────────────────────────────────────
--  chain           : bbbbbbbb-0001-4000-8000-000000000001
--  branch Chennai  : bbbbbbbb-0002-4000-8000-000000000002
--  branch Madurai  : bbbbbbbb-0003-4000-8000-000000000003
--  regulatory[1-2] : bbbbbbbb-0010/0011-...
--  document[1-3]   : bbbbbbbb-0020/0021/0022-...
--  communication[1-2]: bbbbbbbb-0030/0031-...
--  verification[1-2] : bbbbbbbb-0040/0041-...
--  subscription[1-2] : bbbbbbbb-0050/0051-...
-- ── Billing ───────────────────────────────────────────────────
--  branch_plan[1-2]: cccccccc-0010/0011-...
--  invoice         : cccccccc-0020-4000-8000-000000000020
--  line_item[1-2]  : cccccccc-0030/0031-...
--  payment         : cccccccc-0040-4000-8000-000000000040
--  gateway_log     : cccccccc-0050-4000-8000-000000000050
--  refund          : cccccccc-0060-4000-8000-000000000060
--  credit_note     : cccccccc-0070-4000-8000-000000000070
-- ================================================================

BEGIN;


-- ================================================================
-- ONBOARDING SCHEMA — Chain (inserted first; management_user.chain_id
-- references this row so it must exist before the user is inserted)
-- ================================================================

-- ── Chain ───────────────────────────────────────────────────────
INSERT INTO onboarding.chain (
    id,
    name,
    logo_url,
    pan_number,
    gst_number,
    is_active,
    created_at,
    updated_at
) VALUES (
    'bbbbbbbb-0001-4000-8000-000000000001',
    'Velammal Educational Trust',
    'https://storage.edupulse.in/chains/velammal/logo.png',
    'VELAM1234A',                  -- sample PAN (10 chars: 5 alpha + 4 digit + 1 alpha)
    '33VELAM1234A1Z5',             -- Tamil Nadu GST (15 chars)
    true,
    '2026-05-29 11:00:00+05:30',
    '2026-05-29 11:00:00+05:30'
);


-- ================================================================
-- AUTH SCHEMA
-- ================================================================

-- ── Management User ─────────────────────────────────────────────
-- Rajesh Kumar, VP Operations at Velammal Educational Trust.
-- Password: Test@1234  (bcrypt hash stored below)
-- chain_id links him to the Velammal chain inserted above.
INSERT INTO auth.management_user (
    id,
    chain_id,
    email,
    phone,
    username,
    name,
    password_hash,
    is_active,
    is_email_verified,
    is_phone_verified,
    failed_login_attempts,
    last_login_at,
    created_at,
    updated_at
) VALUES (
    'aaaaaaaa-0001-4000-8000-000000000001',
    'bbbbbbbb-0001-4000-8000-000000000001',   -- → Velammal Educational Trust
    'rajesh.kumar@velammal.edu.in',
    '+919876543210',
    'rajesh_velammal',
    'Rajesh Kumar',
    -- bcrypt hash of 'Test@1234', cost factor 12
    '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/lewVY8rFe5OyLjLG',
    true,
    true,
    true,
    0,
    '2026-06-01 09:15:00+05:30',
    '2026-05-29 10:00:00+05:30',
    '2026-06-01 09:15:00+05:30'
);


-- ── OTP ─────────────────────────────────────────────────────────
-- Email signup OTP that Rajesh used to verify his email.
-- Raw OTP was 483921. SHA-256 hash stored.
INSERT INTO auth.otp (
    id,
    otp_type_id,
    code_hash,
    attempts,
    is_used,
    delivery_address,
    expires_at,
    created_at
) VALUES (
    'aaaaaaaa-0020-4000-8000-000000000020',
    (SELECT id FROM auth.otp_type WHERE name = 'signup_email'),
    -- SHA-256 of '483921'
    'a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3',
    1,
    true,
    'rajesh.kumar@velammal.edu.in',
    '2026-05-29 10:10:00+05:30',
    '2026-05-29 10:00:00+05:30'
);

-- Phone OTP used to verify +919876543210
INSERT INTO auth.otp (
    id,
    otp_type_id,
    code_hash,
    attempts,
    is_used,
    delivery_address,
    expires_at,
    created_at
) VALUES (
    'aaaaaaaa-0021-4000-8000-000000000021',
    (SELECT id FROM auth.otp_type WHERE name = 'signup_sms'),
    -- SHA-256 of '726184'
    'b3a8e0e1f9ab1bfe3a36f231f676f78bb28a2d0b8f0a4a20f3c4e6b2d7a9c53',
    1,
    true,
    '+919876543210',
    '2026-05-29 10:15:00+05:30',
    '2026-05-29 10:05:00+05:30'
);


-- ── Session ─────────────────────────────────────────────────────
-- Active portal session for Rajesh (7-day expiry).
INSERT INTO auth.session (
    id,
    user_id,
    access_token_hash,
    refresh_token_hash,
    ip_address,
    user_agent,
    device_fingerprint,
    expires_at,
    revoked_at,
    created_at
) VALUES (
    'aaaaaaaa-0010-4000-8000-000000000010',
    'aaaaaaaa-0001-4000-8000-000000000001',
    -- SHA-256 of raw access JWT (not stored)
    '7f83b1657ff1fc53b92dc18148a1d65dfc2d4b1fa3d677284addd200126d9069',
    -- SHA-256 of raw refresh token
    '2d711642b726b04401627ca9fbac32f5c8530fb1903cc4db02258717921a4881',
    '183.82.114.20',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/125.0.0.0',
    'fp_chrome_win10_rajesh_20260601',
    '2026-06-08 09:15:00+05:30',
    NULL,  -- still active
    '2026-06-01 09:15:00+05:30'
);


-- ── Invite ──────────────────────────────────────────────────────
-- Magic link sent to Rajesh after payment was confirmed.
-- He accepted it and set his password.
INSERT INTO auth.invite (
    id,
    management_user_id,
    status_id,
    invite_token_hash,
    resend_count,
    expires_at,
    accepted_at,
    created_at
) VALUES (
    'aaaaaaaa-0030-4000-8000-000000000030',
    'aaaaaaaa-0001-4000-8000-000000000001',
    (SELECT id FROM auth.invite_status WHERE name = 'accepted'),
    -- SHA-256 of 'this-is-dummy-token'
    'ff12a5aa4858ded35aeeb99dd4da0ada69bc66694c327337851d3383255230ff',
    0,
    '2026-05-31 23:59:59+05:30',
    '2026-05-30 10:30:00+05:30',
    '2026-05-30 09:00:00+05:30'
);


-- ── Audit Log ───────────────────────────────────────────────────
-- Six events covering the full lifecycle for Rajesh.

-- 1. Email OTP requested at signup
INSERT INTO auth.audit_log (id, user_id, event_type_id, ip_address, user_agent, metadata, is_suspicious, created_at)
VALUES (
    'aaaaaaaa-0040-4000-8000-000000000040',
    'aaaaaaaa-0001-4000-8000-000000000001',
    (SELECT id FROM auth.audit_event_type WHERE name = 'otp_requested'),
    '183.82.114.20',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/125.0.0.0',
    '{"otp_type": "signup_email", "delivery": "rajesh.kumar@velammal.edu.in"}',
    false,
    '2026-05-29 10:00:00+05:30'
);

-- 2. Email OTP verified
INSERT INTO auth.audit_log (id, user_id, event_type_id, ip_address, user_agent, metadata, is_suspicious, created_at)
VALUES (
    'aaaaaaaa-0041-4000-8000-000000000041',
    'aaaaaaaa-0001-4000-8000-000000000001',
    (SELECT id FROM auth.audit_event_type WHERE name = 'otp_verified'),
    '183.82.114.20',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/125.0.0.0',
    '{"otp_type": "signup_email", "delivery": "rajesh.kumar@velammal.edu.in"}',
    false,
    '2026-05-29 10:08:00+05:30'
);

-- 3. Application submitted
INSERT INTO auth.audit_log (id, user_id, event_type_id, ip_address, user_agent, metadata, is_suspicious, created_at)
VALUES (
    'aaaaaaaa-0042-4000-8000-000000000042',
    'aaaaaaaa-0001-4000-8000-000000000001',
    (SELECT id FROM auth.audit_event_type WHERE name = 'application_submitted'),
    '183.82.114.20',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/125.0.0.0',
    '{"chain_id": "bbbbbbbb-0001-4000-8000-000000000001", "branch_count": 2}',
    false,
    '2026-05-29 11:00:00+05:30'
);

-- 4. Magic link sent after payment confirmed
INSERT INTO auth.audit_log (id, user_id, event_type_id, ip_address, user_agent, metadata, is_suspicious, created_at)
VALUES (
    'aaaaaaaa-0043-4000-8000-000000000043',
    'aaaaaaaa-0001-4000-8000-000000000001',
    (SELECT id FROM auth.audit_event_type WHERE name = 'invite_sent'),
    NULL,
    NULL,
    '{"invite_id": "aaaaaaaa-0030-4000-8000-000000000030", "triggered_by": "payment_webhook"}',
    false,
    '2026-05-30 09:00:00+05:30'
);

-- 5. Invite accepted — password set, account active
INSERT INTO auth.audit_log (id, user_id, event_type_id, ip_address, user_agent, metadata, is_suspicious, created_at)
VALUES (
    'aaaaaaaa-0044-4000-8000-000000000044',
    'aaaaaaaa-0001-4000-8000-000000000001',
    (SELECT id FROM auth.audit_event_type WHERE name = 'invite_accepted'),
    '183.82.114.20',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/125.0.0.0',
    '{"invite_id": "aaaaaaaa-0030-4000-8000-000000000030"}',
    false,
    '2026-05-30 10:30:00+05:30'
);

-- 6. First login after account setup
INSERT INTO auth.audit_log (id, user_id, event_type_id, ip_address, user_agent, metadata, is_suspicious, created_at)
VALUES (
    'aaaaaaaa-0045-4000-8000-000000000045',
    'aaaaaaaa-0001-4000-8000-000000000001',
    (SELECT id FROM auth.audit_event_type WHERE name = 'login_success'),
    '183.82.114.20',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/125.0.0.0',
    '{"session_id": "aaaaaaaa-0010-4000-8000-000000000010", "method": "password"}',
    false,
    '2026-06-01 09:15:00+05:30'
);


-- ================================================================
-- ONBOARDING SCHEMA — Branches and downstream tables
-- (chain already inserted at the top of this file)
-- ================================================================

-- ── Branch 1 — Chennai ──────────────────────────────────────────
INSERT INTO onboarding.branch (
    id,
    chain_id,
    name,
    address,
    city,
    state,
    pincode,
    board_type,
    school_type,
    establishment_year,
    is_active,
    created_at,
    updated_at
) VALUES (
    'bbbbbbbb-0002-4000-8000-000000000002',
    'bbbbbbbb-0001-4000-8000-000000000001',
    'Velammal Vidyalaya - Chennai',
    'No. 180, Gandhi Salai, Mogappair East',
    'Chennai',
    'Tamil Nadu',
    '600037',
    'CBSE',
    'PRIVATE',
    1995,
    true,
    '2026-05-29 11:10:00+05:30',
    '2026-05-29 11:10:00+05:30'
);


-- ── Branch 2 — Madurai ──────────────────────────────────────────
INSERT INTO onboarding.branch (
    id,
    chain_id,
    name,
    address,
    city,
    state,
    pincode,
    board_type,
    school_type,
    establishment_year,
    is_active,
    created_at,
    updated_at
) VALUES (
    'bbbbbbbb-0003-4000-8000-000000000003',
    'bbbbbbbb-0001-4000-8000-000000000001',
    'Velammal Matriculation School - Madurai',
    'Survey No. 42, Theni Road, Melur',
    'Madurai',
    'Tamil Nadu',
    '625122',
    'STATE_BOARD',
    'PRIVATE',
    2003,
    true,
    '2026-05-29 11:15:00+05:30',
    '2026-05-29 11:15:00+05:30'
);


-- ── Branch Regulatory ───────────────────────────────────────────

-- Chennai (CBSE): UDISE + affiliation both required and verified
INSERT INTO onboarding.branch_regulatory (
    id,
    branch_id,
    udise_code,
    affiliation_number,
    affiliation_board,
    udise_verified,
    affiliation_verified,
    udise_raw_response,
    verified_at,
    created_at
) VALUES (
    'bbbbbbbb-0010-4000-8000-000000000010',
    'bbbbbbbb-0002-4000-8000-000000000002',
    '33150312603',          -- Tamil Nadu UDISE code (11 digits, state code 33)
    '1930452',              -- CBSE South India affiliation number
    'CBSE',
    true,
    true,
    '{
        "schoolName": "VELAMMAL VIDYALAYA",
        "udise": "33150312603",
        "state": "TAMIL NADU",
        "district": "CHENNAI",
        "management": "PRIVATE UNAIDED",
        "medium": "ENGLISH",
        "lowestClass": 1,
        "highestClass": 12,
        "totalStudents": 2840,
        "verifiedAt": "2026-05-29T07:00:00Z",
        "source": "udiseplus.gov.in"
    }',
    '2026-05-29 14:00:00+05:30',
    '2026-05-29 11:10:00+05:30'
);

-- Madurai (State Board): only UDISE required; affiliation not applicable
INSERT INTO onboarding.branch_regulatory (
    id,
    branch_id,
    udise_code,
    affiliation_number,
    affiliation_board,
    udise_verified,
    affiliation_verified,
    udise_raw_response,
    verified_at,
    created_at
) VALUES (
    'bbbbbbbb-0011-4000-8000-000000000011',
    'bbbbbbbb-0003-4000-8000-000000000003',
    '33211503201',          -- Madurai district UDISE code
    NULL,                   -- State Board — no affiliation number
    'STATE_BOARD',
    true,
    false,                  -- affiliation_verified stays false for STATE_BOARD
    '{
        "schoolName": "VELAMMAL MATRIC HSS",
        "udise": "33211503201",
        "state": "TAMIL NADU",
        "district": "MADURAI",
        "management": "PRIVATE UNAIDED",
        "medium": "ENGLISH",
        "lowestClass": 1,
        "highestClass": 12,
        "totalStudents": 1150,
        "verifiedAt": "2026-05-29T07:10:00Z",
        "source": "udiseplus.gov.in"
    }',
    '2026-05-29 14:05:00+05:30',
    '2026-05-29 11:15:00+05:30'
);


-- ── Branch Document ─────────────────────────────────────────────

-- Chennai — School Recognition Certificate (approved)
INSERT INTO onboarding.branch_document (
    id,
    branch_id,
    uploaded_by,
    document_type,
    file_url,
    file_name,
    file_size_bytes,
    mime_type,
    status,
    reviewed_by,
    rejection_reason,
    reviewed_at,
    uploaded_at
) VALUES (
    'bbbbbbbb-0020-4000-8000-000000000020',
    'bbbbbbbb-0002-4000-8000-000000000002',
    'aaaaaaaa-0001-4000-8000-000000000001',
    'school_recognition_certificate',
    'https://storage.edupulse.in/branches/bbbbbbbb-0002/docs/recognition_cert.pdf',
    'Velammal_Chennai_Recognition_Certificate.pdf',
    524288,    -- ~512 KB
    'application/pdf',
    'APPROVED',
    'aaaaaaaa-0001-4000-8000-000000000001',  -- EduPulse ops reviewed (same user for dev seed)
    NULL,
    '2026-05-29 16:00:00+05:30',
    '2026-05-29 12:00:00+05:30'
);

-- Chennai — Affiliation Certificate (CBSE, approved)
INSERT INTO onboarding.branch_document (
    id,
    branch_id,
    uploaded_by,
    document_type,
    file_url,
    file_name,
    file_size_bytes,
    mime_type,
    status,
    reviewed_by,
    rejection_reason,
    reviewed_at,
    uploaded_at
) VALUES (
    'bbbbbbbb-0021-4000-8000-000000000021',
    'bbbbbbbb-0002-4000-8000-000000000002',
    'aaaaaaaa-0001-4000-8000-000000000001',
    'affiliation_certificate',
    'https://storage.edupulse.in/branches/bbbbbbbb-0002/docs/cbse_affiliation_cert.pdf',
    'Velammal_Chennai_CBSE_Affiliation_Certificate.pdf',
    786432,    -- ~768 KB
    'application/pdf',
    'APPROVED',
    'aaaaaaaa-0001-4000-8000-000000000001',
    NULL,
    '2026-05-29 16:10:00+05:30',
    '2026-05-29 12:05:00+05:30'
);

-- Madurai — School Recognition Certificate (approved)
INSERT INTO onboarding.branch_document (
    id,
    branch_id,
    uploaded_by,
    document_type,
    file_url,
    file_name,
    file_size_bytes,
    mime_type,
    status,
    reviewed_by,
    rejection_reason,
    reviewed_at,
    uploaded_at
) VALUES (
    'bbbbbbbb-0022-4000-8000-000000000022',
    'bbbbbbbb-0003-4000-8000-000000000003',
    'aaaaaaaa-0001-4000-8000-000000000001',
    'school_recognition_certificate',
    'https://storage.edupulse.in/branches/bbbbbbbb-0003/docs/recognition_cert.pdf',
    'Velammal_Madurai_Recognition_Certificate.pdf',
    638976,    -- ~624 KB
    'application/pdf',
    'APPROVED',
    'aaaaaaaa-0001-4000-8000-000000000001',
    NULL,
    '2026-05-29 16:20:00+05:30',
    '2026-05-29 12:10:00+05:30'
);


-- ── Branch Communication ─────────────────────────────────────────

-- Chennai
INSERT INTO onboarding.branch_communication (
    id,
    branch_id,
    official_email,
    official_phone,
    whatsapp_number,
    website_url,
    email_verified,
    phone_verified,
    created_at,
    updated_at
) VALUES (
    'bbbbbbbb-0030-4000-8000-000000000030',
    'bbbbbbbb-0002-4000-8000-000000000002',
    'principal.chennai@velammal.edu.in',
    '+914426543210',
    '+914426543210',
    'https://www.velammaleducation.com/chennai',
    true,
    true,
    '2026-05-29 11:10:00+05:30',
    '2026-05-29 14:30:00+05:30'
);

-- Madurai
INSERT INTO onboarding.branch_communication (
    id,
    branch_id,
    official_email,
    official_phone,
    whatsapp_number,
    website_url,
    email_verified,
    phone_verified,
    created_at,
    updated_at
) VALUES (
    'bbbbbbbb-0031-4000-8000-000000000031',
    'bbbbbbbb-0003-4000-8000-000000000003',
    'principal.madurai@velammal.edu.in',
    '+914526123456',
    '+914526123456',
    'https://www.velammaleducation.com/madurai',
    true,
    true,
    '2026-05-29 11:15:00+05:30',
    '2026-05-29 14:35:00+05:30'
);


-- ── Branch Verification ──────────────────────────────────────────

-- Chennai — all three levels fully verified
-- L1: email+phone verified (auth.management_user flags)
-- L2: UDISE + CBSE affiliation verified
-- L3: recognition cert + affiliation cert both approved
INSERT INTO onboarding.branch_verification (
    id,
    branch_id,
    l1_status,        l1_completed_at,
    l2_status,        l2_completed_at,
    l3_status,        l3_completed_at,
    overall_status,   overall_verified_at,
    created_at,
    updated_at
) VALUES (
    'bbbbbbbb-0040-4000-8000-000000000040',
    'bbbbbbbb-0002-4000-8000-000000000002',
    'VERIFIED',  '2026-05-29 10:10:00+05:30',
    'VERIFIED',  '2026-05-29 14:00:00+05:30',
    'APPROVED',  '2026-05-29 16:10:00+05:30',
    'VERIFIED',  '2026-05-29 16:10:00+05:30',
    '2026-05-29 11:10:00+05:30',
    '2026-05-29 16:10:00+05:30'
);

-- Madurai — L1 verified, L2 NOT_REQUIRED (State Board), L3 approved
INSERT INTO onboarding.branch_verification (
    id,
    branch_id,
    l1_status,        l1_completed_at,
    l2_status,        l2_completed_at,
    l3_status,        l3_completed_at,
    overall_status,   overall_verified_at,
    created_at,
    updated_at
) VALUES (
    'bbbbbbbb-0041-4000-8000-000000000041',
    'bbbbbbbb-0003-4000-8000-000000000003',
    'VERIFIED',      '2026-05-29 10:10:00+05:30',
    'NOT_REQUIRED',  '2026-05-29 14:05:00+05:30',   -- State Board skips affiliation check
    'APPROVED',      '2026-05-29 16:20:00+05:30',
    'VERIFIED',      '2026-05-29 16:20:00+05:30',
    '2026-05-29 11:15:00+05:30',
    '2026-05-29 16:20:00+05:30'
);


-- ── Branch Subscription (onboarding intent, pre-payment) ─────────

-- Chennai — Standard plan selected, now ACTIVE after payment
INSERT INTO onboarding.branch_subscription (
    id,
    branch_id,
    plan_id,
    status,
    started_at,
    expires_at,
    payment_reference,
    created_at,
    updated_at
) VALUES (
    'bbbbbbbb-0050-4000-8000-000000000050',
    'bbbbbbbb-0002-4000-8000-000000000002',
    (SELECT id FROM billing.plan WHERE name = 'Standard'),
    'ACTIVE',
    '2026-06-01 00:00:00+05:30',
    '2026-06-30 23:59:59+05:30',
    'pay_Rzp123456789012',                            -- Razorpay payment_id post-payment
    '2026-05-29 16:30:00+05:30',
    '2026-05-30 09:05:00+05:30'
);

-- Madurai — Standard plan selected, now ACTIVE after payment
INSERT INTO onboarding.branch_subscription (
    id,
    branch_id,
    plan_id,
    status,
    started_at,
    expires_at,
    payment_reference,
    created_at,
    updated_at
) VALUES (
    'bbbbbbbb-0051-4000-8000-000000000051',
    'bbbbbbbb-0003-4000-8000-000000000003',
    (SELECT id FROM billing.plan WHERE name = 'Standard'),
    'ACTIVE',
    '2026-06-01 00:00:00+05:30',
    '2026-06-30 23:59:59+05:30',
    'pay_Rzp123456789012',
    '2026-05-29 16:35:00+05:30',
    '2026-05-30 09:05:00+05:30'
);


-- ================================================================
-- BILLING SCHEMA
-- ================================================================

-- ── Branch Plan ─────────────────────────────────────────────────
-- Authoritative billing records, created after payment.captured.

-- Chennai — Standard plan
INSERT INTO billing.branch_plan (
    id,
    branch_id,
    plan_id,
    status,
    starts_at,
    ends_at,
    cancelled_at,
    cancel_reason,
    created_at,
    updated_at
) VALUES (
    'cccccccc-0010-4000-8000-000000000010',
    'bbbbbbbb-0002-4000-8000-000000000002',
    (SELECT id FROM billing.plan WHERE name = 'Standard'),
    'ACTIVE',
    '2026-06-01 00:00:00+05:30',
    NULL,
    NULL,
    NULL,
    '2026-05-30 09:05:00+05:30',
    '2026-05-30 09:05:00+05:30'
);

-- Madurai — Standard plan
INSERT INTO billing.branch_plan (
    id,
    branch_id,
    plan_id,
    status,
    starts_at,
    ends_at,
    cancelled_at,
    cancel_reason,
    created_at,
    updated_at
) VALUES (
    'cccccccc-0011-4000-8000-000000000011',
    'bbbbbbbb-0003-4000-8000-000000000003',
    (SELECT id FROM billing.plan WHERE name = 'Standard'),
    'ACTIVE',
    '2026-06-01 00:00:00+05:30',
    NULL,
    NULL,
    NULL,
    '2026-05-30 09:05:00+05:30',
    '2026-05-30 09:05:00+05:30'
);


-- ── Invoice ─────────────────────────────────────────────────────
-- June 2026 consolidated invoice for Velammal chain.
-- Chennai ₹5,999 + Madurai ₹5,999 = ₹11,998 subtotal
-- GST 18% = ₹2,159.64  →  Total = ₹14,157.64

INSERT INTO billing.invoice (
    id,
    chain_id,
    invoice_number,
    billing_month,
    subtotal,
    tax_percent,
    tax_amount,
    total_amount,
    currency,
    status,
    due_date,
    paid_at,
    notes,
    created_at,
    updated_at
) VALUES (
    'cccccccc-0020-4000-8000-000000000020',
    'bbbbbbbb-0001-4000-8000-000000000001',
    'INV-2026-0001',
    '2026-06-01',
    11998.00,
    18.00,
    2159.64,
    14157.64,
    'INR',
    'PAID',
    '2026-06-10 23:59:59+05:30',
    '2026-06-01 09:30:00+05:30',
    'First invoice — both branches on Standard plan',
    '2026-06-01 00:01:00+05:30',
    '2026-06-01 09:30:00+05:30'
);


-- ── Invoice Line Items ───────────────────────────────────────────

-- Line item for Chennai
INSERT INTO billing.invoice_line_item (
    id,
    invoice_id,
    branch_id,
    branch_plan_id,
    description,
    quantity,
    unit_price,
    total_price,
    created_at
) VALUES (
    'cccccccc-0030-4000-8000-000000000030',
    'cccccccc-0020-4000-8000-000000000020',
    'bbbbbbbb-0002-4000-8000-000000000002',
    'cccccccc-0010-4000-8000-000000000010',
    'Velammal Vidyalaya - Chennai | Standard Plan | Jun 2026',
    1,
    5999.00,
    5999.00,
    '2026-06-01 00:01:00+05:30'
);

-- Line item for Madurai
INSERT INTO billing.invoice_line_item (
    id,
    invoice_id,
    branch_id,
    branch_plan_id,
    description,
    quantity,
    unit_price,
    total_price,
    created_at
) VALUES (
    'cccccccc-0031-4000-8000-000000000031',
    'cccccccc-0020-4000-8000-000000000020',
    'bbbbbbbb-0003-4000-8000-000000000003',
    'cccccccc-0011-4000-8000-000000000011',
    'Velammal Matriculation School - Madurai | Standard Plan | Jun 2026',
    1,
    5999.00,
    5999.00,
    '2026-06-01 00:01:00+05:30'
);


-- ── Payment ─────────────────────────────────────────────────────
-- Rajesh paid via UPI. Payment succeeded but later partially refunded.
INSERT INTO billing.payment (
    id,
    invoice_id,
    chain_id,
    gateway,
    gateway_order_id,
    gateway_payment_id,
    amount,
    currency,
    status,
    payment_method,
    payment_method_detail,
    failure_reason,
    initiated_at,
    completed_at,
    created_at,
    updated_at
) VALUES (
    'cccccccc-0040-4000-8000-000000000040',
    'cccccccc-0020-4000-8000-000000000020',
    'bbbbbbbb-0001-4000-8000-000000000001',
    'RAZORPAY',
    'order_Rzp9876543210AB',
    'pay_Rzp123456789012',
    14157.64,
    'INR',
    'PARTIALLY_REFUNDED',
    'UPI',
    '{"upi_id": "rajesh.kumar@hdfcbank", "bank": "HDFC Bank"}',
    NULL,
    '2026-06-01 09:25:00+05:30',
    '2026-06-01 09:28:00+05:30',
    '2026-06-01 09:25:00+05:30',
    '2026-06-01 10:05:00+05:30'  -- updated after refund
);


-- ── Payment Gateway Log ──────────────────────────────────────────
-- Raw Razorpay payment.captured webhook stored as-is.
INSERT INTO billing.payment_gateway_log (
    id,
    payment_id,
    event_type,
    gateway,
    raw_payload,
    received_at
) VALUES (
    'cccccccc-0050-4000-8000-000000000050',
    'cccccccc-0040-4000-8000-000000000040',
    'payment.captured',
    'RAZORPAY',
    '{
        "entity": "event",
        "account_id": "acc_EduPulse12345678",
        "event": "payment.captured",
        "contains": ["payment"],
        "created_at": 1748743680,
        "payload": {
            "payment": {
                "entity": {
                    "id": "pay_Rzp123456789012",
                    "entity": "payment",
                    "amount": 1415764,
                    "currency": "INR",
                    "status": "captured",
                    "order_id": "order_Rzp9876543210AB",
                    "invoice_id": null,
                    "international": false,
                    "method": "upi",
                    "amount_refunded": 0,
                    "refund_status": null,
                    "captured": true,
                    "description": "INV-2026-0001 Velammal Educational Trust",
                    "vpa": "rajesh.kumar@hdfcbank",
                    "email": "rajesh.kumar@velammal.edu.in",
                    "contact": "+919876543210",
                    "created_at": 1748743500
                }
            }
        }
    }',
    '2026-06-01 09:28:30+05:30'
);

-- Razorpay refund.created webhook stored as-is.
INSERT INTO billing.payment_gateway_log (
    id,
    payment_id,
    event_type,
    gateway,
    raw_payload,
    received_at
) VALUES (
    'cccccccc-0051-4000-8000-000000000051',
    'cccccccc-0040-4000-8000-000000000040',
    'refund.created',
    'RAZORPAY',
    '{
        "entity": "event",
        "account_id": "acc_EduPulse12345678",
        "event": "refund.created",
        "contains": ["refund"],
        "created_at": 1748747100,
        "payload": {
            "refund": {
                "entity": {
                    "id": "rfnd_Rzp111222333444",
                    "entity": "refund",
                    "amount": 60000,
                    "currency": "INR",
                    "payment_id": "pay_Rzp123456789012",
                    "notes": {"reason": "early_onboarding_discount_madurai"},
                    "receipt": null,
                    "acquirer_data": {"rrn": "300123456789"},
                    "created_at": 1748747000,
                    "batch_id": null,
                    "status": "processed",
                    "speed_processed": "normal",
                    "speed_requested": "normal"
                }
            }
        }
    }',
    '2026-06-01 10:05:30+05:30'
);


-- ── Refund ───────────────────────────────────────────────────────
-- ₹600 early-onboarding discount given to Velammal for Madurai branch.
INSERT INTO billing.refund (
    id,
    payment_id,
    invoice_id,
    chain_id,
    gateway_refund_id,
    amount,
    reason,
    status,
    initiated_by,
    processed_at,
    created_at,
    updated_at
) VALUES (
    'cccccccc-0060-4000-8000-000000000060',
    'cccccccc-0040-4000-8000-000000000040',
    'cccccccc-0020-4000-8000-000000000020',
    'bbbbbbbb-0001-4000-8000-000000000001',
    'rfnd_Rzp111222333444',
    600.00,
    'Early onboarding discount applied for Madurai branch — first month 10% off',
    'PROCESSED',
    'aaaaaaaa-0001-4000-8000-000000000001',  -- EduPulse ops (same as management user in dev)
    '2026-06-01 10:05:00+05:30',
    '2026-06-01 09:45:00+05:30',
    '2026-06-01 10:05:00+05:30'
);


-- ── Credit Note ──────────────────────────────────────────────────
-- Credit note issued against the ₹600 refund.
INSERT INTO billing.credit_note (
    id,
    refund_id,
    invoice_id,
    chain_id,
    credit_note_number,
    amount,
    reason,
    issued_at,
    created_at
) VALUES (
    'cccccccc-0070-4000-8000-000000000070',
    'cccccccc-0060-4000-8000-000000000060',
    'cccccccc-0020-4000-8000-000000000020',
    'bbbbbbbb-0001-4000-8000-000000000001',
    'CN-2026-0001',
    600.00,
    'Early onboarding discount — Velammal Madurai first month',
    '2026-06-01 10:06:00+05:30',
    '2026-06-01 10:06:00+05:30'
);


COMMIT;

-- ================================================================
-- QUICK VERIFY QUERIES (run these after seeding to confirm)
-- ================================================================
--
-- SELECT name, email, is_email_verified, is_phone_verified
--   FROM auth.management_user
--  WHERE id = 'aaaaaaaa-0001-4000-8000-000000000001';
--
-- SELECT c.name AS chain, b.name AS branch, b.city, b.board_type,
--        bv.overall_status
--   FROM onboarding.chain c
--   JOIN onboarding.branch b        ON b.chain_id = c.id
--   JOIN onboarding.branch_verification bv ON bv.branch_id = b.id
--  WHERE c.id = 'bbbbbbbb-0001-4000-8000-000000000001';
--
-- SELECT i.invoice_number, i.billing_month, i.total_amount, i.status,
--        li.description, li.total_price
--   FROM billing.invoice i
--   JOIN billing.invoice_line_item li ON li.invoice_id = i.id
--  WHERE i.id = 'cccccccc-0020-4000-8000-000000000020';
--
-- SELECT p.amount, p.status, p.payment_method,
--        r.amount AS refund_amount, cn.credit_note_number
--   FROM billing.payment p
--   JOIN billing.refund r      ON r.payment_id = p.id
--   JOIN billing.credit_note cn ON cn.refund_id = r.id
--  WHERE p.id = 'cccccccc-0040-4000-8000-000000000040';
-- ================================================================
