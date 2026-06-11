-- ================================================================
-- EDUPULSE MASTER DB — DEV SEED: infrastructure schema
-- Story : Velammal tenant DB connection credentials (local dev)
--
-- Run AFTER: 01_auth → 02_onboarding → dev_seed_velammal.sql
-- (chain bbbbbbbb-0001-4000-8000-000000000001 must exist first)
--
-- Encryption : AES-256-GCM
-- Key        : SHA-256("dummy-encryption-key")  ← dev only, never production
-- Plaintext  : "postgres"
-- Decrypt    : see util/crypto.go DecryptPassword()
-- ================================================================

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
    'bbbbbbbb-0001-4000-8000-000000000001',  -- Velammal chain
    'localhost',
    5432,
    'crew_campus_vellamal_tenant',
    'postgres',
    'RPXunmaAukIyoXpquSLkBQ/E9DQl5geEBb4N/RWWq/MQzUc/',  -- AES-GCM("postgres", "dummy-encryption-key")
    'disable',   -- local dev: no TLS
    20,
    10,
    5,
    true
);
