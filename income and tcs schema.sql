USE form26as_db;

-- 1. Ensure Table Structure for Corporate Ledger Books of Accounts
CREATE TABLE IF NOT EXISTS income_records (
    income_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    upload_ref VARCHAR(50) DEFAULT 'MANUAL_ENTRY',
    fin_year CHAR(7) NOT NULL,
    cust_id INT NOT NULL,
    cust_name VARCHAR(255) NOT NULL,
    doc_number VARCHAR(100) NOT NULL,
    doc_date DATE NOT NULL,
    doc_type VARCHAR(50) DEFAULT 'invoice', -- invoice, credit_note
    taxable_amt DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    tax_amt DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    gross_amt DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    tds_section VARCHAR(20) DEFAULT '—',
    tds_rate DECIMAL(5,2) DEFAULT 0.00,
    tds_deductible DECIMAL(15,2) DEFAULT 0.00,
    entry_source VARCHAR(50) DEFAULT 'manual'
);


-- 2. Ensure Aligned Architecture for TCS Codes Master
CREATE TABLE IF NOT EXISTS tcs_codes_master (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    cust_id INT NOT NULL,
    fin_year CHAR(7) NOT NULL,
    quarter CHAR(2) NOT NULL DEFAULT 'Q4',
    gl_code VARCHAR(30) NOT NULL,
    tcs_section VARCHAR(20) NOT NULL,
    sub_code VARCHAR(20) DEFAULT '—',
    tcs_rate DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    surcharge_pct DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    cess_pct DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    appln_form VARCHAR(50) DEFAULT 'Form 27D',
    applicable_to VARCHAR(150) NOT NULL,
    tcs_description TEXT NOT NULL,
    eff_from_date DATE NOT NULL
);
