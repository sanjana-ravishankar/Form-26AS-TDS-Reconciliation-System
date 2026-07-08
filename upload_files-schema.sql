USE form26as_db;

CREATE TABLE IF NOT EXISTS file_uploads_log (
    upload_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    file_name VARCHAR(255) NOT NULL,
    fin_year CHAR(7) NOT NULL,
    quarter CHAR(2) NOT NULL,
    file_size_kb DECIMAL(10,2) NOT NULL,
    upload_status VARCHAR(20) NOT NULL DEFAULT 'success',
    rows_imported INT NOT NULL DEFAULT 0,
    uploaded_by VARCHAR(100) NOT NULL DEFAULT 'Sanjana Ravishankar',
    uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    module_name VARCHAR(50) NOT NULL DEFAULT 'BOOKS_OF_ACCOUNTS'
);
