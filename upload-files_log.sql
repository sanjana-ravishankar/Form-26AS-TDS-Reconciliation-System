USE form26as_db;

-- Adds the missing cryptographic validation tracker column to your existing data logs cleanly
ALTER TABLE file_uploads_log 
ADD COLUMN file_hash VARCHAR(64) NOT NULL DEFAULT 'PENDING_HASH';

