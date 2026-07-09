-- ================================================================
-- TDS Codes Master v2 — Full Official Rates (threshold_limit corrected)
-- Source: Income Tax India (Finance Act 2026, AY 2026-27)
-- Replaces per-customer table with a global reference table
-- ================================================================

USE form26as_db;

-- Drop old table and recreate
 DROP TABLE IF EXISTS tds_codes_master;
 
 CREATE TABLE tds_codes_master (
    id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    section_code    VARCHAR(20)    NOT NULL,          -- e.g. 192, 194C, 194J
    sub_code        VARCHAR(10)    DEFAULT NULL,       -- a, b, i, ii etc.
    description     TEXT           NOT NULL,           -- nature of payment
    payee_type      VARCHAR(50)    DEFAULT 'ALL',      -- ALL / INDIVIDUAL_HUF / OTHERS / NON_RESIDENT
    is_resident     TINYINT(1)     NOT NULL DEFAULT 1, -- 1=Resident, 0=Non-Resident
    tds_rate        DECIMAL(6,3)   NOT NULL DEFAULT 0.000, -- rate in %
    surcharge_pct   DECIMAL(5,2)   NOT NULL DEFAULT 0.00,
    cess_pct        DECIMAL(5,2)   NOT NULL DEFAULT 0.00,
    threshold_limit BIGINT         DEFAULT NULL,       -- NULL = no threshold (in INR)
    threshold_note  VARCHAR(255)   DEFAULT NULL,       -- human readable note
    appln_form      VARCHAR(20)    DEFAULT 'Form 16A',
    effective_from  DATE           NOT NULL DEFAULT '2024-04-01',
    is_active       TINYINT(1)     NOT NULL DEFAULT 1,
    notes           TEXT           DEFAULT NULL,
    INDEX idx_section (section_code),
    INDEX idx_resident (is_resident),
    INDEX idx_payee (payee_type)
);

-- ================================================================
-- RESIDENT INDIA (is_resident = 1)
-- ================================================================
INSERT INTO tds_codes_master
(section_code, sub_code, description, payee_type, is_resident, tds_rate, threshold_limit, threshold_note, appln_form, notes) VALUES

-- 192: Salary — slab rate (stored as 0, handled separately)
('192', NULL, 'Payment of salary', 'ALL', 1, 0.000, NULL, 'Normal slab rate applies', 'Form 16', 'Rate depends on individual slab — not a fixed %'),

-- 192A: PF withdrawal
('192A', NULL, 'Payment of accumulated balance of provident fund taxable in hands of employee', 'ALL', 1, 10.000, 50000, 'Threshold: Rs. 50,000', 'Form 16A', NULL),

-- 193: Interest on securities
('193', 'a', 'Interest on debentures/securities by local authority or corporation', 'ALL', 1, 10.000, NULL, NULL, 'Form 16A', NULL),
('193', 'b', 'Interest on listed debentures issued by a company', 'ALL', 1, 10.000, NULL, NULL, 'Form 16A', NULL),
('193', 'c', 'Interest on Central/State Government security (8% Savings Bonds etc.)', 'ALL', 1, 10.000, NULL, NULL, 'Form 16A', NULL),
('193', 'd', 'Interest on any other security', 'ALL', 1, 10.000, NULL, NULL, 'Form 16A', NULL),

-- 194: Dividend
('194', NULL, 'Income by way of dividend', 'ALL', 1, 10.000, 5000, 'Threshold: Rs. 5,000', 'Form 16A', NULL),

-- 194A: Interest other than securities
('194A', NULL, 'Income by way of interest other than interest on securities', 'ALL', 1, 10.000, 40000, 'Threshold: Rs. 40,000 (Rs. 50,000 for senior citizens)', 'Form 16A', NULL),

-- 194B: Lottery winnings
('194B', NULL, 'Income by way of winnings from lotteries, crossword puzzles, card games, gambling', 'ALL', 1, 30.000, 10000, 'Threshold: Rs. 10,000 per transaction', 'Form 16A', NULL),

-- 194BA: Online game winnings
('194BA', NULL, 'Income by way of winnings from any online game', 'ALL', 1, 30.000, NULL, 'No threshold — every rupee taxable', 'Form 16A', NULL),

-- 194BB: Horse race winnings
('194BB', NULL, 'Income by way of winnings from horse races', 'ALL', 1, 30.000, 10000, 'Threshold: Rs. 10,000 per transaction', 'Form 16A', NULL),

-- 194C: Contractors
('194C', 'a', 'Payment to contractor/sub-contractor — Individual/HUF', 'INDIVIDUAL_HUF', 1, 1.000, 100000, 'Single: Rs. 30,000 | Aggregate FY: Rs. 1,00,000', 'Form 16A', NULL),
('194C', 'b', 'Payment to contractor/sub-contractor — Others (Company/Firm/etc.)', 'OTHERS', 1, 2.000, 100000, 'Single: Rs. 30,000 | Aggregate FY: Rs. 1,00,000', 'Form 16A', NULL),

-- 194D: Insurance commission
('194D', NULL, 'Insurance commission', 'ALL', 1, 5.000, 15000, 'Threshold: Rs. 15,000', 'Form 16A', NULL),

-- 194DA: Life insurance policy payment
('194DA', NULL, 'Payment in respect of life insurance policy', 'ALL', 1, 2.000, 100000, 'Threshold: Rs. 1,00,000', 'Form 16A', NULL),

-- 194EE: NSS deposits
('194EE', NULL, 'Payment in respect of deposit under National Savings Scheme', 'ALL', 1, 10.000, 2500, 'Threshold: Rs. 2,500', 'Form 16A', NULL),

-- 194F: Mutual Fund repurchase (discontinued from 01-10-2024)
('194F', NULL, 'Payment on account of repurchase of unit by Mutual Fund or Unit Trust of India', 'ALL', 1, 20.000, NULL, NULL, 'Form 16A', 'NOT APPLICABLE w.e.f. 01-10-2024'),

-- 194G: Lottery commission
('194G', NULL, 'Commission on sale of lottery tickets', 'ALL', 1, 2.000, 15000, 'Threshold: Rs. 15,000', 'Form 16A', NULL),

-- 194H: Commission/brokerage
('194H', NULL, 'Commission or brokerage', 'ALL', 1, 2.000, 15000, 'Threshold: Rs. 15,000', 'Form 16A', NULL),

-- 194I: Rent
('194I', 'a', 'Rent — Plant and Machinery', 'ALL', 1, 2.000, 240000, 'Threshold: Rs. 2,40,000 per annum', 'Form 16A', NULL),
('194I', 'b', 'Rent — Land or building or furniture or fitting', 'ALL', 1, 10.000, 240000, 'Threshold: Rs. 2,40,000 per annum', 'Form 16A', NULL),

-- 194IA: Immovable property transfer
('194IA', NULL, 'Payment on transfer of certain immovable property other than agricultural land', 'ALL', 1, 1.000, 5000000, 'Threshold: Rs. 50,00,000', 'Form 26QB', NULL),

-- 194IB: Rent by Individual/HUF
('194IB', NULL, 'Payment of rent by individual or HUF not liable to tax audit', 'INDIVIDUAL_HUF', 1, 2.000, 50000, 'Threshold: Rs. 50,000 per month', 'Form 26QC', NULL),

-- 194IC: Joint Development Agreements
('194IC', NULL, 'Payment of monetary consideration under Joint Development Agreements', 'ALL', 1, 10.000, NULL, NULL, 'Form 16A', NULL),

-- 194J: Professional/Technical fees
('194J', 'a', 'Fees for technical services / royalty for cinematographic films / call centre', 'ALL', 1, 2.000, 30000, 'Threshold: Rs. 30,000 per annum', 'Form 16A', NULL),
('194J', 'b', 'Fees for professional services — Any other sum', 'ALL', 1, 10.000, 30000, 'Threshold: Rs. 30,000 per annum', 'Form 16A', NULL),

-- 194K: Income from units
('194K', NULL, 'Income in respect of units payable to resident person', 'ALL', 1, 10.000, 5000, 'Threshold: Rs. 5,000', 'Form 16A', NULL),

-- 194LA: Compensation on immovable property acquisition
('194LA', NULL, 'Payment of compensation on acquisition of certain immovable property', 'ALL', 1, 10.000, 250000, 'Threshold: Rs. 2,50,000', 'Form 16A', NULL),

-- 194LBA: Business trust distribution
('194LBA', '1', 'Business trust distributing interest from SPV or rental income to unit holders', 'ALL', 1, 10.000, NULL, NULL, 'Form 16A', NULL),

-- 194LBB: Investment fund income
('194LBB', NULL, 'Investment fund paying income to resident unit holder', 'ALL', 1, 10.000, NULL, NULL, 'Form 16A', NULL),

-- 194LBC: Securitisation trust income
('194LBC', NULL, 'Income from investment in securitisation trust — resident', 'ALL', 1, 10.000, NULL, NULL, 'Form 16A', NULL),

-- 194M: Commission/professional by Individual/HUF
('194M', NULL, 'Commission, brokerage, contractual fee, professional fee paid by Individual/HUF not covered under 194C/194H/194J', 'INDIVIDUAL_HUF', 1, 2.000, 5000000, 'Threshold: Rs. 50,00,000 aggregate per FY', 'Form 16A', NULL),

-- 194N: Cash withdrawal
('194N', 'a', 'Cash withdrawal exceeding Rs. 1 crore', 'ALL', 1, 2.000, 10000000, 'Threshold: Rs. 1,00,00,000 (Rs. 3 Cr for co-operative society)', 'Form 16A', NULL),
('194N', 'b', 'Cash withdrawal exceeding Rs. 20 lakhs — ITR non-filer', 'ALL', 1, 2.000, 2000000, 'For persons who have not filed ITR for 3 preceding years', 'Form 16A', 'Rate is 2% between 20L-1Cr, 5% above 1Cr for non-filers'),

-- 194O: E-commerce
('194O', NULL, 'Payment/credit by e-commerce operator to e-commerce participant', 'ALL', 1, 0.100, 500000, 'Threshold: Rs. 5,00,000 for resident individual/HUF participant', 'Form 16A', NULL),

-- 194P: Senior citizen (bank deducts)
('194P', NULL, 'Deduction of tax by specified bank for senior citizen aged 75 or more', 'ALL', 1, 0.000, NULL, 'Tax on total income as per slab rate', 'Form 16A', 'Slab rate — not fixed %'),

-- 194Q: Purchase of goods
('194Q', NULL, 'Payment for purchase of goods exceeding Rs. 50 lakhs', 'ALL', 1, 0.100, 5000000, 'Threshold: Rs. 50,00,000 aggregate per FY', 'Form 16A', 'TDS on amount exceeding Rs. 50L'),

-- 194R: Benefit/perquisite
('194R', NULL, 'Deduction on benefit or perquisite provided arising from business/profession', 'ALL', 1, 10.000, 20000, 'Threshold: Rs. 20,000 aggregate per FY', 'Form 16A', NULL),

-- 194S: Virtual Digital Assets
('194S', NULL, 'Payment on transfer of Virtual Digital Asset (VDA/Crypto)', 'ALL', 1, 1.000, 10000, 'Threshold: Rs. 10,000 (specified person: Rs. 50,000)', 'Form 16A', NULL),

-- 194T: Partner payment from firm (effective 01-04-2025)
('194T', NULL, 'Payments of salary/remuneration/commission/bonus/interest to partner of firm', 'ALL', 1, 10.000, 20000, 'Threshold: Rs. 20,000 aggregate per FY', 'Form 16A', 'Effective from 01-04-2025'),

-- 195: Other payments to non-resident (resident placeholder — actual is NR section)
('195', NULL, 'Payment of any other sum — catch-all for non-resident', 'ALL', 1, 10.000, NULL, NULL, 'Form 16A', 'See non-resident section for specific sub-rates'),

-- Any Other Income (catch-all)
('OTHER', NULL, 'Any other income not covered under specific sections', 'ALL', 1, 10.000, NULL, NULL, 'Form 16A', NULL);

-- ================================================================
-- NON-RESIDENT (is_resident = 0)
-- ================================================================
INSERT INTO tds_codes_master
(section_code, sub_code, description, payee_type, is_resident, tds_rate, threshold_limit, threshold_note, appln_form, notes) VALUES

('192', NULL, 'Payment of salary to non-resident', 'ALL', 0, 0.000, NULL, 'Normal slab rate', 'Form 16', 'Slab rate — not fixed %'),
('192A', NULL, 'PF withdrawal — non-resident', 'ALL', 0, 10.000, NULL, NULL, 'Form 16A', NULL),
('194B', NULL, 'Lottery winnings — non-resident', 'ALL', 0, 30.000, NULL, NULL, 'Form 16A', NULL),
('194BA', NULL, 'Online game winnings — non-resident', 'ALL', 0, 30.000, NULL, NULL, 'Form 16A', NULL),
('194BB', NULL, 'Horse race winnings — non-resident', 'ALL', 0, 30.000, NULL, NULL, 'Form 16A', NULL),
('194E', NULL, 'Payment to non-resident sportsmen or sports association', 'ALL', 0, 20.000, NULL, NULL, 'Form 16A', NULL),
('194EE', NULL, 'Payment in respect of NSS deposits — non-resident', 'ALL', 0, 10.000, NULL, NULL, 'Form 16A', NULL),
('194F', NULL, 'Mutual Fund repurchase — non-resident', 'ALL', 0, 20.000, NULL, NULL, 'Form 16A', 'NOT APPLICABLE w.e.f. 01-10-2024'),
('194G', NULL, 'Lottery commission — non-resident', 'ALL', 0, 2.000, NULL, NULL, 'Form 16A', NULL),
('194LB', NULL, 'Payment of interest on infrastructure debt fund — non-resident', 'ALL', 0, 5.000, NULL, NULL, 'Form 16A', NULL),
('194LBA', '2a', 'Business trust distribution — Section 10(23FC)(a) — non-resident', 'ALL', 0, 5.000, NULL, NULL, 'Form 16A', NULL),
('194LBA', '2b', 'Business trust distribution — Section 10(23FC)(b) — non-resident', 'ALL', 0, 10.000, NULL, NULL, 'Form 16A', NULL),
('194LBA', '3', 'Business trust distribution — Section 10(23FCA) — non-resident', 'ALL', 0, 30.000, NULL, NULL, 'Form 16A', NULL),
('194LBB', NULL, 'Investment fund income — non-resident unit holder', 'ALL', 0, 30.000, NULL, NULL, 'Form 16A', NULL),
('194LBC', NULL, 'Securitisation trust income — non-resident', 'ALL', 0, 30.000, NULL, NULL, 'Form 16A', NULL),
('194LC', NULL, 'Interest by Indian company on foreign currency borrowing/long-term bonds', 'ALL', 0, 5.000, NULL, NULL, 'Form 16A', '4% for IFSC listed bonds; 9% for bonds from IFSC source after 01-04-2023'),
('194LD', NULL, 'Interest on rupee denominated bond to FII/Qualified Foreign Investor', 'ALL', 0, 5.000, NULL, NULL, 'Form 16A', NULL),
('194N', 'a', 'Cash withdrawal exceeding Rs. 1 crore — non-resident', 'ALL', 0, 2.000, 10000000, NULL, 'Form 16A', NULL),
('194N', 'b', 'Cash withdrawal exceeding Rs. 20 lakhs — non-resident ITR non-filer', 'ALL', 0, 2.000, 2000000, NULL, 'Form 16A', '2% between 20L-1Cr, 5% above 1Cr'),
('194T', NULL, 'Partner payment from firm — non-resident', 'ALL', 0, 10.000, 20000, 'Threshold: Rs. 20,000', 'Form 16A', 'Effective from 01-04-2025'),

-- 195: Various non-resident income sub-types
('195', 'a', 'Income in respect of investment made by Non-Resident Indian Citizen', 'ALL', 0, 20.000, NULL, NULL, 'Form 16A', NULL),
('195', 'b', 'Long-term capital gains u/s 115E — Non-Resident Indian', 'ALL', 0, 12.500, NULL, NULL, 'Form 16A', NULL),
('195', 'c', 'Long-term capital gains u/s 112(1)(c)(iii)', 'ALL', 0, 12.500, NULL, NULL, 'Form 16A', NULL),
('195', 'd', 'Long-term capital gains u/s 112A exceeding Rs. 1,25,000', 'ALL', 0, 12.500, 125000, 'Threshold: Rs. 1,25,000', 'Form 16A', NULL),
('195', 'e', 'Short-term capital gains u/s 111A', 'ALL', 0, 20.000, NULL, NULL, 'Form 16A', NULL),
('195', 'f', 'Any other long-term capital gains', 'ALL', 0, 12.500, NULL, NULL, 'Form 16A', NULL),
('195', 'g', 'Any other income to non-resident', 'ALL', 0, 30.000, NULL, NULL, 'Form 16A', NULL);

-- ================================================================
-- Verify
-- ================================================================
SELECT
    section_code,
    sub_code,
    CASE is_resident WHEN 1 THEN 'Resident' ELSE 'Non-Resident' END AS residency,
    payee_type,
    tds_rate,
    threshold_limit,
    is_active
FROM tds_codes_master
ORDER BY is_resident DESC, section_code, sub_code;

SELECT COUNT(*) AS total_sections FROM tds_codes_master;


