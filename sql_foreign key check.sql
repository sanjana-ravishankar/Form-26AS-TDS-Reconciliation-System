-- In case there is a need to alter this table, drop foreign key checks, alter and then set it back

SET FOREIGN_KEY_CHECKS = 0;

ALTER TABLE unreferenced_entries
DROP FOREIGN KEY fk_unref_upload;

SET FOREIGN_KEY_CHECKS = 1;
