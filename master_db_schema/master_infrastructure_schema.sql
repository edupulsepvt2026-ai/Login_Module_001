-- ================================================================
-- EDUPULSE MASTER DB — INFRASTRUCTURE SCHEMA
-- Database : edupulse-master (PostgreSQL 16)
-- Schema   : infrastructure
--
-- Purpose: stores per-chain tenant database connection credentials.
-- At runtime, TenantPoolManager looks up this table on a pool-cache
-- miss to create a new pgxpool for the chain.
--
-- Design notes:
--   - One row per chain (UNIQUE on chain_id).
--   - chain_id → onboarding.chain(id): the chain must be fully
--     onboarded before a DB record is provisioned.
--   - db_password_encrypted stores the password encrypted via KMS.
--     The app layer decrypts it before building the DSN.
--   - Pool tuning (max_conns, min_conns, connect_timeout_secs) is
--     stored here so each chain can be sized independently.
--
-- Tables:
--   infrastructure.chain_database
-- ================================================================

CREATE SCHEMA IF NOT EXISTS infrastructure;

CREATE OR REPLACE FUNCTION infrastructure.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


-- ── Chain Database ───────────────────────────────────────────────
-- One row per chain. Stores the connection credentials for the
-- tenant PostgreSQL database belonging to that chain.
-- TenantPoolManager queries this table when chain_id is not yet
-- in the in-memory pool cache.
CREATE TABLE infrastructure.chain_database (
    id                   UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    chain_id             UUID         NOT NULL REFERENCES onboarding.chain(id),
    db_host              VARCHAR(255) NOT NULL,
    db_port              INTEGER      NOT NULL DEFAULT 5432,
    db_name              VARCHAR(100) NOT NULL,
    db_user              VARCHAR(100) NOT NULL,
    db_password_encrypted TEXT        NOT NULL,
    ssl_mode             VARCHAR(20)  NOT NULL DEFAULT 'require',
    max_conns            INTEGER      NOT NULL DEFAULT 20,
    min_conns            INTEGER      NOT NULL DEFAULT 2,
    connect_timeout_secs INTEGER      NOT NULL DEFAULT 5,
    is_active            BOOLEAN      NOT NULL DEFAULT true,
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT uq_chain_database        UNIQUE (chain_id),
    CONSTRAINT chk_db_port              CHECK (db_port > 0 AND db_port < 65536),
    CONSTRAINT chk_max_conns            CHECK (max_conns > 0),
    CONSTRAINT chk_min_conns            CHECK (min_conns >= 0),
    CONSTRAINT chk_min_max_conns        CHECK (min_conns <= max_conns),
    CONSTRAINT chk_connect_timeout      CHECK (connect_timeout_secs > 0),
    CONSTRAINT chk_ssl_mode             CHECK (ssl_mode IN ('disable', 'require', 'verify-ca', 'verify-full'))
);

CREATE INDEX idx_chain_database_chain_id ON infrastructure.chain_database (chain_id);
CREATE INDEX idx_chain_database_active   ON infrastructure.chain_database (chain_id) WHERE is_active = true;

CREATE TRIGGER trg_chain_database_updated_at
    BEFORE UPDATE ON infrastructure.chain_database
    FOR EACH ROW EXECUTE FUNCTION infrastructure.set_updated_at();

COMMENT ON TABLE  infrastructure.chain_database                       IS 'One row per chain. Holds tenant DB credentials for TenantPoolManager lazy pool creation.';
COMMENT ON COLUMN infrastructure.chain_database.chain_id              IS 'FK to onboarding.chain(id). Provisioned after chain onboarding is complete.';
COMMENT ON COLUMN infrastructure.chain_database.db_password_encrypted IS 'KMS-encrypted password. Decrypt before building the DSN — never use plain text.';
COMMENT ON COLUMN infrastructure.chain_database.ssl_mode              IS 'PostgreSQL sslmode: disable | require | verify-ca | verify-full. Default: require.';
COMMENT ON COLUMN infrastructure.chain_database.max_conns             IS 'pgxpool MaxConns for this chain. Tune per chain size.';
COMMENT ON COLUMN infrastructure.chain_database.min_conns             IS 'pgxpool MinConns — kept-alive connections for this chain.';
COMMENT ON COLUMN infrastructure.chain_database.is_active             IS 'False = chain suspended. TenantPoolManager refuses to create a pool for inactive records.';
