-- ================================================================
-- EDUPULSE MASTER DB — BILLING SCHEMA
-- Database : edupulse-master (PostgreSQL 16)
-- Schema   : billing
--
-- Cross-schema dependencies (same DB):
--   auth.management_user  ← refund.initiated_by
--   onboarding.chain      ← invoice.chain_id, payment.chain_id,
--                            refund.chain_id, credit_note.chain_id
--   onboarding.branch     ← branch_plan.branch_id,
--                            invoice_line_item.branch_id
--
-- Trigger: public.set_updated_at() must already exist.
--
-- Flow:
--   onboarding.branch verified → branch_plan created (billing starts)
--   billing_month tick         → invoice + line_items generated
--   chain pays                 → payment row, gateway logs
--   chain disputes / ops refunds → refund + credit_note
-- ================================================================

CREATE SCHEMA IF NOT EXISTS billing;

-- ================================================================
-- 1. PLAN
--    Master catalogue of subscription tiers.
--    branch_plan rows reference this.
-- ================================================================

CREATE TABLE billing.plan (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(50) NOT NULL,
    description     TEXT,
    price_per_month NUMERIC(10,2) NOT NULL,
    currency        VARCHAR(3)  NOT NULL DEFAULT 'INR',
    max_students    INTEGER,
    max_teachers    INTEGER,
    features        JSONB       NOT NULL DEFAULT '{}',
    is_active       BOOLEAN     NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT plan_price_positive CHECK (price_per_month > 0)
);

CREATE UNIQUE INDEX idx_plan_name_active ON billing.plan (name) WHERE is_active = true;

CREATE TRIGGER trg_plan_updated_at
    BEFORE UPDATE ON billing.plan
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

INSERT INTO billing.plan (name, price_per_month, max_students, max_teachers, features) VALUES
    ('Starter',  2999.00,   500,   50, '{"sms_alerts": false, "parent_portal": false, "reports": true}'),
    ('Standard', 5999.00,  2000,  200, '{"sms_alerts": true,  "parent_portal": true,  "reports": true}'),
    ('Premium', 11999.00,  NULL,  NULL, '{"sms_alerts": true,  "parent_portal": true,  "reports": true, "priority_support": true}')
ON CONFLICT DO NOTHING;


-- ================================================================
-- 2. BRANCH PLAN
--    One active row per branch. Created once onboarding.branch
--    reaches overall_status = 'VERIFIED' and payment flows starts.
--
--    NOTE: This replaces onboarding.branch_subscription.
--    Keep branch_subscription for the onboarding tracking view,
--    but billing.branch_plan is the authoritative billing record.
-- ================================================================

CREATE TABLE billing.branch_plan (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id     UUID        NOT NULL,    -- → onboarding.branch.id
    plan_id       UUID        NOT NULL REFERENCES billing.plan(id),
    status        VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    starts_at     TIMESTAMPTZ NOT NULL,    -- always 1st of billing month
    ends_at       TIMESTAMPTZ,
    cancelled_at  TIMESTAMPTZ,
    cancel_reason VARCHAR,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT branch_plan_status_check CHECK (
        status = ANY (ARRAY['ACTIVE', 'CANCELLED', 'EXPIRED'])
    ),
    CONSTRAINT branch_plan_start_day_check CHECK (
        EXTRACT(DAY FROM starts_at) = 1
    )
);

-- only one ACTIVE plan per branch at a time
CREATE UNIQUE INDEX idx_branch_plan_active_unique
    ON billing.branch_plan (branch_id)
    WHERE status = 'ACTIVE';

CREATE INDEX idx_branch_plan_branch ON billing.branch_plan (branch_id);
CREATE INDEX idx_branch_plan_plan   ON billing.branch_plan (plan_id);

CREATE TRIGGER trg_branch_plan_updated_at
    BEFORE UPDATE ON billing.branch_plan
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

COMMENT ON COLUMN billing.branch_plan.branch_id  IS 'FK to onboarding.branch.id — enforced at app layer (cross-schema).';
COMMENT ON COLUMN billing.branch_plan.starts_at  IS 'Branch added mid-month → 1st of next month. No proration. Enforced by check constraint.';


-- ================================================================
-- 3. INVOICE
--    One invoice per chain per billing month.
--    Aggregates all branches under the chain for that month.
-- ================================================================

CREATE TABLE billing.invoice (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    chain_id        UUID        NOT NULL,            -- → onboarding.chain.id
    invoice_number  VARCHAR(50) NOT NULL UNIQUE,     -- INV-2024-0001
    billing_month   DATE        NOT NULL,            -- always 1st of month e.g. 2024-11-01
    subtotal        NUMERIC(10,2) NOT NULL,
    tax_percent     NUMERIC(5,2)  NOT NULL DEFAULT 18,   -- GST
    tax_amount      NUMERIC(10,2) NOT NULL,
    total_amount    NUMERIC(10,2) NOT NULL,
    currency        VARCHAR(3)  NOT NULL DEFAULT 'INR',
    status          VARCHAR(20) NOT NULL DEFAULT 'DRAFT',
    due_date        TIMESTAMPTZ NOT NULL,
    paid_at         TIMESTAMPTZ,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT invoice_status_check CHECK (
        status = ANY (ARRAY['DRAFT', 'SENT', 'PAID', 'PARTIALLY_PAID', 'OVERDUE', 'VOID'])
    ),
    CONSTRAINT invoice_billing_month_check CHECK (
        EXTRACT(DAY FROM billing_month) = 1
    ),
    CONSTRAINT invoice_amounts_positive CHECK (
        subtotal >= 0 AND tax_amount >= 0 AND total_amount >= 0
    )
);

-- one invoice per chain per month
CREATE UNIQUE INDEX idx_invoice_chain_month ON billing.invoice (chain_id, billing_month);

CREATE INDEX idx_invoice_chain  ON billing.invoice (chain_id);
CREATE INDEX idx_invoice_status ON billing.invoice (status) WHERE status NOT IN ('PAID', 'VOID');

CREATE TRIGGER trg_invoice_updated_at
    BEFORE UPDATE ON billing.invoice
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

COMMENT ON COLUMN billing.invoice.chain_id      IS 'FK to onboarding.chain.id — one invoice consolidates all branches under a chain.';
COMMENT ON COLUMN billing.invoice.billing_month IS 'Always 1st of month. Unique index (chain_id, billing_month) prevents duplicate invoices.';


-- ================================================================
-- 4. INVOICE LINE ITEM
--    One row per branch per invoice.
--    "Velammal Chennai – Standard Plan – Nov 2024"
-- ================================================================

CREATE TABLE billing.invoice_line_item (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id      UUID        NOT NULL REFERENCES billing.invoice(id)     ON DELETE CASCADE,
    branch_id       UUID        NOT NULL,            -- → onboarding.branch.id
    branch_plan_id  UUID        NOT NULL REFERENCES billing.branch_plan(id),
    description     VARCHAR(300),
    quantity        INTEGER     NOT NULL DEFAULT 1,
    unit_price      NUMERIC(10,2) NOT NULL,
    total_price     NUMERIC(10,2) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT line_item_quantity_positive CHECK (quantity > 0),
    CONSTRAINT line_item_price_positive    CHECK (unit_price >= 0 AND total_price >= 0)
);

CREATE INDEX idx_line_item_invoice ON billing.invoice_line_item (invoice_id);
CREATE INDEX idx_line_item_branch  ON billing.invoice_line_item (branch_id);

COMMENT ON COLUMN billing.invoice_line_item.branch_id IS 'FK to onboarding.branch.id — denormalized here for reporting without joins.';


-- ================================================================
-- 5. PAYMENT
--    One row per Razorpay payment attempt.
--    A chain may make multiple attempts for the same invoice
--    (e.g., first attempt fails, retries succeed).
-- ================================================================

CREATE TABLE billing.payment (
    id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id            UUID        NOT NULL REFERENCES billing.invoice(id),
    chain_id              UUID        NOT NULL,      -- → onboarding.chain.id (denormalized)
    gateway               VARCHAR(30) NOT NULL DEFAULT 'RAZORPAY',
    gateway_order_id      VARCHAR(100),              -- Razorpay order_id
    gateway_payment_id    VARCHAR(100) UNIQUE,       -- Razorpay payment_id (unique per successful txn)
    amount                NUMERIC(10,2) NOT NULL,
    currency              VARCHAR(3)  NOT NULL DEFAULT 'INR',
    status                VARCHAR(30) NOT NULL DEFAULT 'PENDING',
    payment_method        VARCHAR(20),               -- UPI, CARD, NETBANKING, WALLET
    payment_method_detail JSONB,                     -- {"upi_id": "abc@upi"} or {"bank": "HDFC"}
    failure_reason        VARCHAR,
    initiated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at          TIMESTAMPTZ,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT payment_status_check CHECK (
        status = ANY (ARRAY['PENDING', 'SUCCESS', 'FAILED', 'REFUNDED', 'PARTIALLY_REFUNDED'])
    ),
    CONSTRAINT payment_method_check CHECK (
        payment_method IS NULL
        OR payment_method = ANY (ARRAY['UPI', 'CARD', 'NETBANKING', 'WALLET'])
    ),
    CONSTRAINT payment_amount_positive CHECK (amount > 0)
);

CREATE INDEX idx_payment_invoice       ON billing.payment (invoice_id);
CREATE INDEX idx_payment_chain         ON billing.payment (chain_id);
CREATE INDEX idx_payment_gateway_order ON billing.payment (gateway_order_id) WHERE gateway_order_id IS NOT NULL;
CREATE INDEX idx_payment_pending       ON billing.payment (initiated_at)     WHERE status = 'PENDING';

CREATE TRIGGER trg_payment_updated_at
    BEFORE UPDATE ON billing.payment
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

COMMENT ON COLUMN billing.payment.chain_id          IS 'Denormalized from invoice.chain_id for fast per-chain payment history without joining invoice.';
COMMENT ON COLUMN billing.payment.gateway_payment_id IS 'UNIQUE: prevents the same Razorpay payment being recorded twice.';
COMMENT ON COLUMN billing.payment.gateway_order_id  IS 'Created when Razorpay order is opened. Used to match webhook events.';


-- ================================================================
-- 6. PAYMENT GATEWAY LOG
--    Every raw webhook from Razorpay stored as-is.
--    Append-only — NEVER update or delete.
--    Critical for dispute resolution and idempotency checks.
-- ================================================================

CREATE TABLE billing.payment_gateway_log (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id   UUID        REFERENCES billing.payment(id), -- nullable: event may arrive before payment row
    event_type   VARCHAR(100) NOT NULL,   -- payment.captured / refund.created / payment.failed
    gateway      VARCHAR(30) NOT NULL DEFAULT 'RAZORPAY',
    raw_payload  JSONB       NOT NULL,
    received_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_gateway_log_payment    ON billing.payment_gateway_log (payment_id) WHERE payment_id IS NOT NULL;
CREATE INDEX idx_gateway_log_event_type ON billing.payment_gateway_log (event_type);
CREATE INDEX idx_gateway_log_received   ON billing.payment_gateway_log (received_at DESC);

COMMENT ON TABLE  billing.payment_gateway_log IS 'Append-only. Never UPDATE or DELETE rows. Used for dispute resolution and webhook replay.';
COMMENT ON COLUMN billing.payment_gateway_log.payment_id IS 'NULL allowed: Razorpay webhook can arrive before the payment row is committed.';


-- ================================================================
-- 7. REFUND
--    Initiated by EduPulse ops team via Razorpay API.
--    Each refund is against one payment + one invoice.
-- ================================================================

CREATE TABLE billing.refund (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id        UUID        NOT NULL REFERENCES billing.payment(id),
    invoice_id        UUID        NOT NULL REFERENCES billing.invoice(id),
    chain_id          UUID        NOT NULL,           -- → onboarding.chain.id (denormalized)
    gateway_refund_id VARCHAR(100) UNIQUE,            -- Razorpay refund_id
    amount            NUMERIC(10,2) NOT NULL,
    reason            VARCHAR     NOT NULL,
    status            VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    initiated_by      UUID,                           -- → auth.management_user.id (EduPulse ops)
    processed_at      TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT refund_status_check CHECK (
        status = ANY (ARRAY['PENDING', 'PROCESSED', 'FAILED'])
    ),
    CONSTRAINT refund_amount_positive CHECK (amount > 0)
);

CREATE INDEX idx_refund_payment ON billing.refund (payment_id);
CREATE INDEX idx_refund_invoice ON billing.refund (invoice_id);
CREATE INDEX idx_refund_chain   ON billing.refund (chain_id);

CREATE TRIGGER trg_refund_updated_at
    BEFORE UPDATE ON billing.refund
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

COMMENT ON COLUMN billing.refund.chain_id     IS 'Denormalized from payment.chain_id for fast chain-level refund reporting.';
COMMENT ON COLUMN billing.refund.initiated_by IS 'FK to auth.management_user.id — EduPulse ops team member who triggered the refund.';


-- ================================================================
-- 8. CREDIT NOTE
--    Issued after a refund is processed.
--    One credit note per refund (1:1).
-- ================================================================

CREATE TABLE billing.credit_note (
    id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    refund_id          UUID        NOT NULL UNIQUE REFERENCES billing.refund(id),
    invoice_id         UUID        NOT NULL REFERENCES billing.invoice(id),
    chain_id           UUID        NOT NULL,          -- → onboarding.chain.id (denormalized)
    credit_note_number VARCHAR(50) NOT NULL UNIQUE,   -- CN-2024-0001
    amount             NUMERIC(10,2) NOT NULL,
    reason             TEXT,
    issued_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT credit_note_amount_positive CHECK (amount > 0)
);

CREATE INDEX idx_credit_note_chain   ON billing.credit_note (chain_id);
CREATE INDEX idx_credit_note_invoice ON billing.credit_note (invoice_id);

COMMENT ON COLUMN billing.credit_note.chain_id IS 'Denormalized from refund.chain_id for chain-level credit reporting.';
COMMENT ON TABLE  billing.credit_note IS '1:1 with billing.refund (UNIQUE on refund_id). Issued after refund is PROCESSED.';


-- ================================================================
-- SEQUENCE: invoice_number and credit_note_number
--    Use sequences so numbers are gapless and crash-safe.
--    Format: INV-YYYY-NNNN / CN-YYYY-NNNN
--    Generate in app layer using:
--      'INV-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('billing.invoice_number_seq')::text, 4, '0')
-- ================================================================

CREATE SEQUENCE billing.invoice_number_seq     START 1 INCREMENT 1 NO CYCLE;
CREATE SEQUENCE billing.credit_note_number_seq START 1 INCREMENT 1 NO CYCLE;


-- ================================================================
-- CROSS-SCHEMA FK SUMMARY
-- (Not enforced at DB level because cross-schema FKs between
--  onboarding and billing would create a circular dependency risk
--  during migrations. Enforced at the application service layer.)
--
--  billing.branch_plan.branch_id      → onboarding.branch.id
--  billing.invoice.chain_id           → onboarding.chain.id
--  billing.invoice_line_item.branch_id → onboarding.branch.id
--  billing.payment.chain_id           → onboarding.chain.id
--  billing.refund.chain_id            → onboarding.chain.id
--  billing.refund.initiated_by        → auth.management_user.id
--  billing.credit_note.chain_id       → onboarding.chain.id
-- ================================================================
