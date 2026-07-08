USE form26as_db;

CREATE TABLE IF NOT EXISTS form26as_records (
    record_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    fin_year CHAR(7) NOT NULL,
    tan_of_deductor CHAR(10) NOT NULL,
    deductor_name VARCHAR(200) NOT NULL,
    section_code VARCHAR(20) NOT NULL,
    transaction_date DATE NOT NULL,
    booking_amt DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    tds_credited DECIMAL(15,2) NOT NULL DEFAULT 0.00
);
