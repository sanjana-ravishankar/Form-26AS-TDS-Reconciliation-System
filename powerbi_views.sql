-- ================================================================
-- Form 26AS Utility — Power BI MySQL Views
-- Verified against actual schema 26-Jun-2026
-- Run once on form26as_db before connecting Power BI
-- ================================================================

USE form26as_db;

-- ================================================================
-- VIEW 1: vw_tds_summary
-- Customer-wise TDS deductible vs 26AS credit per FY
-- ================================================================
CREATE OR REPLACE VIEW vw_tds_summary AS
SELECT
    c.cust_id,
    c.cust_code,
    c.cust_name,
    c.pan_number,
    c.tan_number,
    ir.fin_year,
    COALESCE(SUM(ir.taxable_amt), 0.00)     AS total_taxable_amt,
    COALESCE(SUM(ir.tax_amt), 0.00)         AS total_tds_deductible,
    COALESCE(SUM(ir.gross_amt), 0.00)       AS total_gross_amt,
    COALESCE(f26.total_tds_credited, 0.00)  AS total_26as_credit,
    COALESCE(SUM(ir.tax_amt), 0.00)
        - COALESCE(f26.total_tds_credited, 0.00) AS variance_amt,
    CASE
        WHEN COALESCE(SUM(ir.tax_amt), 0) = 0 THEN 0.00
        ELSE ROUND(
            COALESCE(f26.total_tds_credited, 0.00)
            / COALESCE(SUM(ir.tax_amt), 0.00) * 100, 2)
    END AS pct_credit,
    COUNT(ir.income_id)                     AS invoice_count,
    COALESCE(tc.tds_section, '—')           AS tds_section,
    COALESCE(tc.tds_rate, 0.00)             AS tds_rate
FROM cust_master c
LEFT JOIN income_records ir
    ON c.cust_id = ir.cust_id
LEFT JOIN (
    SELECT
        LOWER(TRIM(tan_of_deductor)) AS tan,
        fin_year,
        SUM(tds_credited)            AS total_tds_credited
    FROM form26as_records
    GROUP BY LOWER(TRIM(tan_of_deductor)), fin_year
) f26
    ON LOWER(TRIM(c.tan_number)) = f26.tan
    AND ir.fin_year = f26.fin_year
LEFT JOIN tds_codes_master tc
    ON tc.cust_id = c.cust_id
GROUP BY
    c.cust_id, c.cust_code, c.cust_name,
    c.pan_number, c.tan_number,
    ir.fin_year, f26.total_tds_credited,
    tc.tds_section, tc.tds_rate;


-- ================================================================
-- VIEW 2: vw_reconciliation
-- Customer-wise reconciliation status per FY
-- ================================================================
CREATE OR REPLACE VIEW vw_reconciliation AS
SELECT
    c.cust_id,
    c.cust_code,
    c.cust_name,
    c.pan_number,
    c.tan_number,
    b.fin_year,
    COALESCE(b.system_tds, 0.00)   AS system_tds,
    COALESCE(b.gross_income, 0.00) AS book_credit,
    COALESCE(g.f26as_credit, 0.00) AS f26as_credit,
    COALESCE(b.system_tds, 0.00)
        - COALESCE(g.f26as_credit, 0.00) AS variance_amt,
    CASE
        WHEN COALESCE(b.system_tds, 0) = 0
         AND COALESCE(g.f26as_credit, 0) = 0 THEN 0.00
        WHEN COALESCE(b.system_tds, 0) = 0
          OR COALESCE(g.f26as_credit, 0) = 0 THEN 0.00
        WHEN b.system_tds >= g.f26as_credit
            THEN ROUND((g.f26as_credit / b.system_tds) * 100, 2)
        ELSE ROUND((b.system_tds / g.f26as_credit) * 100, 2)
    END AS match_score_pct,
    COALESCE(ro.manual_status,
        CASE
            WHEN COALESCE(b.system_tds, 0) = 0
             AND COALESCE(g.f26as_credit, 0) = 0 THEN 'open'
            WHEN ABS(COALESCE(g.f26as_credit, 0)
                   - COALESCE(b.system_tds, 0)) < 1.00 THEN 'reconciled'
            WHEN COALESCE(g.f26as_credit, 0) = 0 THEN 'open'
            WHEN CASE
                    WHEN b.system_tds >= g.f26as_credit
                        THEN (g.f26as_credit / b.system_tds) * 100
                    ELSE (b.system_tds / g.f26as_credit) * 100
                 END >= 85.00 THEN 'likely_match'
            WHEN CASE
                    WHEN b.system_tds >= g.f26as_credit
                        THEN (g.f26as_credit / b.system_tds) * 100
                    ELSE (b.system_tds / g.f26as_credit) * 100
                 END >= 50.00 THEN 'suggested_match'
            ELSE 'open'
        END
    ) AS recon_status,
    COALESCE(ro.remarks,
        'Automated engine validation complete.') AS remarks,
    ro.updated_at AS status_updated_at
FROM cust_master c
LEFT JOIN (
    SELECT cust_id, fin_year,
           SUM(tax_amt)   AS system_tds,
           SUM(gross_amt) AS gross_income
    FROM income_records
    GROUP BY cust_id, fin_year
) b ON c.cust_id = b.cust_id
LEFT JOIN (
    SELECT LOWER(TRIM(tan_of_deductor)) AS tan,
           fin_year,
           SUM(tds_credited)            AS f26as_credit
    FROM form26as_records
    GROUP BY LOWER(TRIM(tan_of_deductor)), fin_year
) g ON LOWER(TRIM(c.tan_number)) = g.tan
    AND b.fin_year = g.fin_year
LEFT JOIN recon_overrides ro
    ON ro.cust_id = c.cust_id
    AND ro.fin_year = b.fin_year
WHERE b.system_tds IS NOT NULL
   OR g.f26as_credit IS NOT NULL;


-- ================================================================
-- VIEW 3: vw_invoice_detail
-- Invoice-level detail for break down of the details
-- ================================================================
CREATE OR REPLACE VIEW vw_invoice_detail AS
SELECT
    ir.income_id,
    ir.upload_ref,
    ir.fin_year,
    c.cust_code,
    c.cust_name,
    c.pan_number,
    c.tan_number,
    ir.doc_number,
    ir.doc_date,
    ir.doc_type,
    ir.taxable_amt,
    ir.tax_amt,
    ir.gross_amt,
    ir.tds_deductible,
    ir.tds_section,
    ir.tds_rate,
    ir.entry_source,
    MONTH(ir.doc_date)   AS txn_month,
    YEAR(ir.doc_date)    AS txn_year,
    CASE MONTH(ir.doc_date)
        WHEN 4  THEN 'Q1' WHEN 5  THEN 'Q1' WHEN 6  THEN 'Q1'
        WHEN 7  THEN 'Q2' WHEN 8  THEN 'Q2' WHEN 9  THEN 'Q2'
        WHEN 10 THEN 'Q3' WHEN 11 THEN 'Q3' WHEN 12 THEN 'Q3'
        ELSE 'Q4'
    END AS fy_quarter
FROM income_records ir
JOIN cust_master c ON ir.cust_id = c.cust_id;


-- ================================================================
-- VIEW 4: vw_upload_history
-- Upload log for audit tracking
-- ================================================================
CREATE OR REPLACE VIEW vw_upload_history AS
SELECT
    ul.upload_id,
    ul.module_name,
    ul.fin_year,
    ul.`quarter`,
    ul.file_name,
    ul.file_size_kb,
    ul.rows_imported,
    ul.upload_status,
    ul.uploaded_by,
    ul.uploaded_at,
    ul.file_hash,
    DATE(ul.uploaded_at) AS upload_date,
    HOUR(ul.uploaded_at) AS upload_hour
FROM file_uploads_log ul;


-- ================================================================
-- Verify
-- ================================================================
SHOW FULL TABLES WHERE Table_type = 'VIEW';
