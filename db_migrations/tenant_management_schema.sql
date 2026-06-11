-- ================================================================
-- EDUPULSE TENANT DB — MANAGEMENT SCHEMA
-- Database : edupulse-tenant (PostgreSQL 16)
-- Schema   : management
--
-- Purpose:
--   Local copy of chain and branch information synced from the
--   master DB (onboarding.chain / onboarding.branch) during
--   onboarding. Keeps the tenant DB self-contained — no cross-DB
--   joins needed at runtime.
--
-- Tables:
--   chain            — One row per school brand/group
--   management_table — One row per branch (tenant); PK is tenant_id
--
-- Cross-schema references (within this tenant DB):
--   auth.management_user.chain_id → management.chain.id
--   auth.user.tenant_id           → management.management_table.tenant_id
--   auth.invite.chain_id          → management.chain.id
-- ================================================================

CREATE SCHEMA IF NOT EXISTS management;

CREATE OR REPLACE FUNCTION management.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


-- ================================================================
-- TABLES
-- ================================================================

-- ── Chain ───────────────────────────────────────────────────────
-- One row per school brand/group (e.g. "Velammal Educational Trust").
-- Synced from master DB onboarding.chain during onboarding.
-- Primary key is used as FK anchor for management_table,
-- auth.management_user, and auth.invite.
CREATE TABLE management.chain (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name       VARCHAR(100) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_chain_updated_at
    BEFORE UPDATE ON management.chain
    FOR EACH ROW EXECUTE FUNCTION management.set_updated_at();

COMMENT ON TABLE management.chain IS 'Master record for each school chain (brand). One row per school group. Branches are in management_table.';


-- ── Management Table (Branch Registry) ─────────────────────────
-- One row per branch. tenant_id is the PK and the identifier used
-- across the entire tenant DB to scope data to a specific branch.
-- Denormalised branch info (name, city, address, contacts) is copied
-- from the master DB during onboarding for fast reads without joins.
CREATE TABLE management.management_table (
    tenant_id      UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    chain_id       UUID         NOT NULL REFERENCES management.chain(id),
    branch_id      UUID         NOT NULL,       -- → master DB onboarding.branch.id (app-layer ref)
    chain_name     VARCHAR(100) NOT NULL,
    branch_name    VARCHAR(100) NOT NULL,
    branch_city    VARCHAR(100),
    branch_state   VARCHAR(100),
    branch_address TEXT,
    branch_phone   VARCHAR(20),
    branch_email   VARCHAR(150),
    is_active      BOOLEAN      NOT NULL DEFAULT true,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT uq_management_chain_branch UNIQUE (chain_id, branch_id)
);

CREATE INDEX idx_management_chain_id ON management.management_table (chain_id);
CREATE INDEX idx_management_active   ON management.management_table (is_active) WHERE is_active = true;

CREATE TRIGGER trg_management_table_updated_at
    BEFORE UPDATE ON management.management_table
    FOR EACH ROW EXECUTE FUNCTION management.set_updated_at();

COMMENT ON TABLE  management.management_table IS 'Branch registry. One row per branch. tenant_id is the scope identifier used across all tenant DB schemas.';
COMMENT ON COLUMN management.management_table.tenant_id  IS 'Primary key and tenant scope identifier. Referenced by auth.user.tenant_id and auth.invite.tenant_id.';
COMMENT ON COLUMN management.management_table.chain_id   IS 'FK to management.chain.id. Also referenced by auth.management_user.chain_id and auth.invite.chain_id.';
COMMENT ON COLUMN management.management_table.branch_id  IS 'Reference to master DB onboarding.branch.id. Enforced at app layer (cross-DB).';
COMMENT ON COLUMN management.management_table.chain_name IS 'Denormalised from master DB for fast reads. Sync on chain name change.';
COMMENT ON COLUMN management.management_table.branch_name IS 'Denormalised from master DB for fast reads. Sync on branch name change.';
