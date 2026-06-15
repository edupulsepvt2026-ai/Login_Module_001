-- ================================================================
-- EDUPULSE MASTER DB — DEV SEED: infrastructure schema
--
-- Entry 1 : Velammal chain  (bbbbbbbb-0001-...)
-- Entry 2 : Second chain    (bbbbbbbb-0002-...)
--
-- Run AFTER: 01_auth → 02_onboarding → dev_seed_velammal.sql
-- (chains must exist in onboarding.chain before this runs)
--
-- Encryption : AES-256-GCM
-- Key        : SHA-256("dummy-encryption-key")  ← dev only, never production
-- Decrypt    : see util/crypto.go DecryptPassword()
-- ================================================================

-- ── Entry 1: Velammal chain ──────────────────────────────────
-- Plaintext password : Edupulse@2026
-- Nonce              : 000000000000000000000001

DELETE FROM infrastructure.chain_database
WHERE id = 'dddddddd-0001-4000-8000-000000000001';

INSERT INTO infrastructure.chain_database (
    id,
    chain_id,
    db_host,
    db_port,
    db_name,
    db_user,
    db_password_encrypted,
    ssl_mode,
    max_conns,
    min_conns,
    connect_timeout_secs,
    is_active
) VALUES (
    'dddddddd-0001-4000-8000-000000000001',
    'bbbbbbbb-0001-4000-8000-000000000001',  -- Second chain
    'db.hqtrzgykhejxqgsxqfkp.supabase.co',
    5432,
    'postgres',
    'postgres',
    'AAAAAAAAAAAAAAAC0E+kuTUBrioQ39JaX1SyfYQZOqZg7l6AKWoNsA==',  -- AES-GCM("Edupulse@123", "dummy-encryption-key")
    'require',
    20,
    10,
    5,
    true
);
