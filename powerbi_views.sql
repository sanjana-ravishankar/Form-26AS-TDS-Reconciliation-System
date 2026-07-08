-- ================================================================
-- Form 26AS Utility — Power BI MySQL Views  (v2 schema)
-- Updated: tds_codes_master v2 (no cust_id, no tds_section col)
--          income_records: tds_deductible replaces tax_amt for TDS calc
--          Tolerance widened to 5.00 (paisa rounding across invoices)
-- Run once on form26as_db before connecting Power BI
-- ================================================================

USE form26as_db;

-- ================================================================
-- VIEW 1: vw_tds_summary
-- Customer-wise TDS deductible vs 26AS credit per FY
-- v2 fix: removed JOIN to tds_codes_master (no cust_id in v2)
--         tds_section / tds_rate now read directly from income_records
--         tax_amt  -> tds_deductible for TDS calculation
-- ================================================================
CREATE OR REPLACE VIEW vw_tds_summary AS
SELECT
    c.cust_id,
    c.cust_code,
    c.cust_name,
    c.pan_number,
    c.tan_number,
    ir.fin_year,
    COALESCE(SUM(ir.taxable_amt),    0.00) AS total_taxable_amt,
    COALESCE(SUM(ir.tds_deductible), 0.00) AS total_tds_deductible,
    COALESCE(SUM(ir.gross_amt),      0.00) AS total_gross_amt,
    COALESCE(f26.total_tds_credited, 0.00) AS total_26as_credit,
    COALESCE(SUM(ir.tds_deductible), 0.00)
        - COALESCE(f26.total_tds_credited, 0.00)   AS variance_amt,
    CASE
        WHEN COALESCE(SUM(ir.tds_deductible), 0) = 0 THEN 0.00
        ELSE ROUND(
            COALESCE(f26.total_tds_credited, 0.00)
            / COALESCE(SUM(ir.tds_deductible), 0.00) * 100, 2)
    END AS pct_credit,
    COUNT(ir.income_id)                            AS invoice_count,
    -- tds_section and tds_rate: take the most common section for this customer+FY
    -- (a customer may have multiple sections; the dominant one is shown in summary)
    COALESCE(
        (SELECT ir2.tds_section
         FROM income_records ir2
         WHERE ir2.cust_id = c.cust_id AND ir2.fin_year = ir.fin_year
           AND ir2.tds_section != '—'
         GROUP BY ir2.tds_section
         ORDER BY COUNT(*) DESC
         LIMIT 1),
    '—') AS tds_section,
    COALESCE(
        (SELECT ir3.tds_rate
         FROM income_records ir3
         WHERE ir3.cust_id = c.cust_id AND ir3.fin_year = ir.fin_year
           AND ir3.tds_section != '—'
         GROUP BY ir3.tds_rate
         ORDER BY COUNT(*) DESC
         LIMIT 1),
    0.00) AS tds_rate
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
GROUP BY
    c.cust_id, c.cust_code, c.cust_name,
    c.pan_number, c.tan_number,
    ir.fin_year, f26.total_tds_credited;


-- ================================================================
-- VIEW 2: vw_reconciliation
-- Customer-wise reconciliation status per FY
-- v2 fix: tax_amt -> tds_deductible, tolerance 1.00 -> 5.00
-- ================================================================
CREATE OR REPLACE VIEW vw_reconciliation AS
SELECT
    c.cust_id,
    c.cust_code,
    c.cust_name,
    c.pan_number,
    c.tan_number,
    b.fin_year,
    COALESCE(b.system_tds,  0.00) AS system_tds,
    COALESCE(b.gross_income,0.00) AS book_credit,
    COALESCE(g.f26as_credit,0.00) AS f26as_credit,
    COALESCE(b.system_tds,  0.00)
        - COALESCE(g.f26as_credit, 0.00)           AS variance_amt,
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
                   - COALESCE(b.system_tds, 0)) < 5.00 THEN 'reconciled'
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
           SUM(tds_deductible) AS system_tds,
           SUM(gross_amt)      AS gross_income
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
-- VIEW 3: vw_invoice_detail  (no changes needed — was already correct)
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
    MONTH(ir.doc_date) AS txn_month,
    YEAR(ir.doc_date)  AS txn_year,
    CASE MONTH(ir.doc_date)
        WHEN 4  THEN 'Q1' WHEN 5  THEN 'Q1' WHEN 6  THEN 'Q1'
        WHEN 7  THEN 'Q2' WHEN 8  THEN 'Q2' WHEN 9  THEN 'Q2'
        WHEN 10 THEN 'Q3' WHEN 11 THEN 'Q3' WHEN 12 THEN 'Q3'
        ELSE 'Q4'
    END AS fy_quarter
FROM income_records ir
JOIN cust_master c ON ir.cust_id = c.cust_id;


-- ================================================================
-- VIEW 4: vw_upload_history  (no changes needed — was already correct)
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
