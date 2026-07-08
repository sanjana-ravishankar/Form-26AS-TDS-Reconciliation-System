-- ============================================================
--  Form 26AS Reconciliation Utility — MySQL Schema
--  Encoding : utf8mb4  |  Engine : InnoDB
--  Reserved words avoided in all identifiers.
-- ============================================================

USE form26as_db;

-- ─────────────────────────────────────────────────────────────
-- 1. CUSTOMER MASTER
--    Core customer registry.
--    Active columns: cust_id, cust_code, cust_name,
--                   pan_number, gstin_number, tan_number,
--                   cust_status, contact
--
--    NOTE: tan_number is NOT NULL and UNIQUE —
--          it is a unique identifier per customer.
--
--    Columns kept for future use are listed but commented out.
--    Do NOT add FK constraints for commented-out columns.
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS cust_master (
    cust_id       INT UNSIGNED  NOT NULL AUTO_INCREMENT,

    -- Identity
    cust_code     VARCHAR(20)   NOT NULL,             -- e.g. CUST-001
    cust_name     VARCHAR(200)  NOT NULL,

    -- Tax identifiers
    pan_number    CHAR(10)      NOT NULL,             -- Format: AAAAA9999A
    gstin_number  VARCHAR(15)   NULL,                 -- Format: 29AAAAA9999A1Z5
    tan_number    CHAR(10)      NOT NULL,             -- Format: AAAA99999A  (unique, never NULL)

    -- Status
    cust_status   ENUM(
                    'active',
                    'inactive'
                  )              NOT NULL DEFAULT 'active',

    -- Contact (single field for now)
    contact       VARCHAR(120)  NULL,

    -- ── Future columns (uncommenting requires matching app changes) ──
    -- short_name    VARCHAR(80)   NULL,
    -- cust_segment  VARCHAR(60)   NULL,
    -- cust_category ENUM('domestic','export','sez') NOT NULL DEFAULT 'domestic',
    -- contact_email VARCHAR(180)  NULL,
    -- contact_phone VARCHAR(20)   NULL,
    -- addr_line1    VARCHAR(200)  NULL,
    -- addr_line2    VARCHAR(200)  NULL,
    -- city_name     VARCHAR(80)   NULL,
    -- state_name    VARCHAR(80)   NULL,
    -- pin_code      VARCHAR(10)   NULL,
    -- created_by    INT UNSIGNED  NULL,
    -- updated_by    INT UNSIGNED  NULL,
    -- created_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- updated_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT pk_cust_master  PRIMARY KEY (cust_id),
    CONSTRAINT uq_cust_code    UNIQUE (cust_code),
    CONSTRAINT uq_cust_pan     UNIQUE (pan_number),
    CONSTRAINT uq_cust_tan     UNIQUE (tan_number),   -- TAN is a unique identifier

    -- ── Indexes for search / filter performance ──
    INDEX idx_cust_name        (cust_name),
    INDEX idx_cust_gstin       (gstin_number),
    INDEX idx_cust_status      (cust_status)
    -- NOTE: tan_number index is covered by uq_cust_tan above.

    -- ── FK constraints (activate only when created_by/updated_by columns are uncommented) ──
    -- CONSTRAINT fk_cust_created_by FOREIGN KEY (created_by) REFERENCES user_master(user_id),
    -- CONSTRAINT fk_cust_updated_by FOREIGN KEY (updated_by) REFERENCES user_master(user_id)

) ENGINE=InnoDB COMMENT='Customer master registry';


-- ─────────────────────────────────────────────────────────────
-- 2. STATS VIEW
--    Powers the three widget cards on the Customer Master
--    screen: Total Customers, Active Customers, Total TANs.
--    Backend queries this view directly.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_cust_master_stats AS
SELECT
    COUNT(*)                      AS total_customers,
    SUM(cust_status = 'active')   AS active_customers,
    SUM(cust_status = 'inactive') AS inactive_customers,
    COUNT(DISTINCT tan_number)    AS total_tans
FROM
    cust_master;


                     


-- ─────────────────────────────────────────────────────────────
-- 3. BOOKS SUMMARY VIEW
--    Powers the Summary tab table.
--    Columns: Customer Name, Taxable Amount, Gross Amount,
--             TDS Deductible, Collection Amount, TDS Receivable
--
--    collection_amt  = gross_amt - adjustments
--    tds_receivable  = tds_deductible - tds_already_credited (recon module)
--                      (for now equals tds_deductible until recon is built)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_books_summary AS
SELECT
    cm.cust_id,
    cm.cust_name,
    cm.cust_status,
    ir.fin_year,

    -- Core amounts aggregated per customer per FY
    COALESCE(SUM(ir.taxable_amt), 0)                        AS taxable_amt,
    COALESCE(SUM(ir.gross_amt),   0)                        AS gross_amt,
    COALESCE(SUM(ir.tds_deductible), 0)                     AS tds_deductible,

    -- Collection = gross minus linked adjustments
    COALESCE(SUM(ir.gross_amt), 0)
      - COALESCE((
          SELECT SUM(a.adj_amt)
          FROM   adjustments a
          WHERE  a.cust_id  = cm.cust_id
            AND  a.fin_year = ir.fin_year
        ), 0)                                               AS collection_amt,

    -- TDS Receivable = TDS deductible (recon module will refine this)
    COALESCE(SUM(ir.tds_deductible), 0)                     AS tds_receivable

FROM
    cust_master     cm
JOIN income_records ir ON ir.cust_id = cm.cust_id
GROUP BY
    cm.cust_id, cm.cust_name, cm.cust_status, ir.fin_year;


-- ─────────────────────────────────────────────────────────────
-- 4. BOOKS WIDGET VIEW
--    Powers the five metric cards on Books of Accounts.
--    Filtered by fin_year in the application layer.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW vw_books_widgets AS
SELECT
    fin_year,
    SUM(gross_amt)                                          AS sales_income,
    (
        SELECT COALESCE(SUM(adj_amt), 0)
        FROM   adjustments a2
        WHERE  a2.fin_year = ir.fin_year
    )                                                       AS adjustments,
    (
        SELECT COALESCE(SUM(adj_amt), 0)
        FROM   adjustments a3
        WHERE  a3.fin_year  = ir.fin_year
          AND  a3.income_id IS NOT NULL
    )                                                       AS linked_adjustments,
    SUM(taxable_amt)                                        AS total_income,
    SUM(tds_deductible)                                     AS tds_deductible
FROM
    income_records ir
GROUP BY
    fin_year;


-- ─────────────────────────────────────────────────────────────
-- END OF SCHEMA
-- ─────────────────────────────────────────────────────────────
