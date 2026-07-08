-- ─────────────────────────────────────────────────────────────
-- 1. ADJUSTMENTS
--    Credit notes, deductions, and other adjustments against
--    income records. Linked Adjustments = those matched to
--    a specific income_record row.
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS adjustments (
    adj_id          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    fin_year        CHAR(7)       NOT NULL,
    cust_id         INT UNSIGNED  NULL,
    income_id       INT UNSIGNED  NULL,                 -- NULL = unlinked adjustment

    adj_type        ENUM(
                      'credit_note',
                      'discount',
                      'write_off',
                      'advance_adj',
                      'other'
                    )              NOT NULL,
    adj_date        DATE          NOT NULL,
    adj_amt         DECIMAL(15,2) NOT NULL,             -- always positive
    ref_number      VARCHAR(60)   NULL,                 -- CN / debit note ref
    remarks         VARCHAR(255)  NULL,
    upload_ref      VARCHAR(30)   NULL,

    created_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_adjustments      PRIMARY KEY (adj_id),
    CONSTRAINT fk_adj_cust         FOREIGN KEY (cust_id)
                                     REFERENCES cust_master(cust_id)
                                     ON DELETE SET NULL,
    CONSTRAINT fk_adj_income       FOREIGN KEY (income_id)
                                     REFERENCES income_records(income_id)
                                     ON DELETE SET NULL,

    INDEX idx_adj_fin_year         (fin_year),
    INDEX idx_adj_cust             (cust_id),
    INDEX idx_adj_income           (income_id)
) ENGINE=InnoDB COMMENT='Adjustments (credit notes, discounts) against income records';


-- ─────────────────────────────────────────────────────────────
-- 2. UNREFERENCED ENTRIES
--    Rows from uploaded files that could not be matched to
--    any customer (no PAN / TAN / name match).
--    Powers: Unreferenced Entries tab.
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS unreferenced_entries (
    unref_id        INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    upload_id       INT UNSIGNED  NOT NULL,
    upload_ref      VARCHAR(30)   NOT NULL,
    fin_year        CHAR(7)       NOT NULL,

    raw_identifier  VARCHAR(255)  NULL,                 -- name / code as in source file
    doc_number      VARCHAR(60)   NULL,
    doc_date        DATE          NULL,
    entry_amt       DECIMAL(15,2) NULL,

    unref_reason    ENUM(
                      'no_pan',
                      'no_tan',
                      'no_customer',
                      'duplicate'
                    )              NOT NULL,
    remarks         VARCHAR(255)  NULL,
    resolved        TINYINT(1)    NOT NULL DEFAULT 0,   -- 1 = manually resolved
    resolved_by     INT UNSIGNED  NULL,
    resolved_at     DATETIME      NULL,

    created_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_unref_entries    PRIMARY KEY (unref_id),
    CONSTRAINT fk_unref_upload     FOREIGN KEY (upload_id)
                                     REFERENCES upload_history(upload_id),
    CONSTRAINT fk_unref_resolved   FOREIGN KEY (resolved_by)
                                     REFERENCES user_master(user_id),

    INDEX idx_unref_fin_year       (fin_year),
    INDEX idx_unref_reason         (unref_reason),
    INDEX idx_unref_resolved       (resolved)
) ENGINE=InnoDB COMMENT='Upload rows that could not be matched to any customer';
