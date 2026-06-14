-- Migration: Create coresetting table for tenant credentials
-- This table is in the MASTER database only
-- It stores configuration and credentials for all tenant databases

CREATE TABLE IF NOT EXISTS coresetting (
    id SERIAL PRIMARY KEY,
    mid VARCHAR(255) NOT NULL,
    key VARCHAR(255) NOT NULL,
    value TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT coresetting_unique_mid_key UNIQUE(mid, key)
);

-- Create index for faster lookups by mid
CREATE INDEX IF NOT EXISTS idx_coresetting_mid ON coresetting(mid);
CREATE INDEX IF NOT EXISTS idx_coresetting_mid_key ON coresetting(mid, key);

-- Create trigger to auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_coresetting_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS coresetting_update_timestamp ON coresetting;
CREATE TRIGGER coresetting_update_timestamp
    BEFORE UPDATE ON coresetting
    FOR EACH ROW
    EXECUTE FUNCTION update_coresetting_updated_at();

-- ============================================
-- Sample Data: Vendor 001 (Tenant 1)
-- ============================================
INSERT INTO coresetting (mid, key, value) VALUES
('vendor_001', 'tenant_db_host', 'tenant1.example.com'),
('vendor_001', 'tenant_db_port', '5432'),
('vendor_001', 'tenant_db_user', 'tenant1_user'),
('vendor_001', 'tenant_db_password', 'tenant1_secure_password'),
('vendor_001', 'tenant_db_name', 'tenant1_database')
ON CONFLICT (mid, key) DO UPDATE 
SET value = EXCLUDED.value;

-- ============================================
-- Sample Data: Vendor 002 (Tenant 2)
-- ============================================
INSERT INTO coresetting (mid, key, value) VALUES
('vendor_002', 'tenant_db_host', 'tenant2.example.com'),
('vendor_002', 'tenant_db_port', '5432'),
('vendor_002', 'tenant_db_user', 'tenant2_user'),
('vendor_002', 'tenant_db_password', 'tenant2_secure_password'),
('vendor_002', 'tenant_db_name', 'tenant2_database')
ON CONFLICT (mid, key) DO UPDATE 
SET value = EXCLUDED.value;

-- ============================================
-- Sample Data: Vendor 003 (Tenant 3)
-- ============================================
INSERT INTO coresetting (mid, key, value) VALUES
('vendor_003', 'tenant_db_host', 'tenant3.example.com'),
('vendor_003', 'tenant_db_port', '5432'),
('vendor_003', 'tenant_db_user', 'tenant3_user'),
('vendor_003', 'tenant_db_password', 'tenant3_secure_password'),
('vendor_003', 'tenant_db_name', 'tenant3_database')
ON CONFLICT (mid, key) DO UPDATE 
SET value = EXCLUDED.value;

-- ============================================
-- Verification Query
-- ============================================
-- SELECT mid, key, value FROM coresetting ORDER BY mid, key;

-- ============================================
-- How to Add a New Tenant
-- ============================================
-- INSERT INTO coresetting (mid, key, value) VALUES
-- ('new_vendor', 'tenant_db_host', 'new_host.example.com'),
-- ('new_vendor', 'tenant_db_port', '5432'),
-- ('new_vendor', 'tenant_db_user', 'new_user'),
-- ('new_vendor', 'tenant_db_password', 'new_password'),
-- ('new_vendor', 'tenant_db_name', 'new_database')
-- ON CONFLICT (mid, key) DO UPDATE 
-- SET value = EXCLUDED.value;
