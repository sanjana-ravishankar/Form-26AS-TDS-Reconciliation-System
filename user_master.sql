-- USER MASTER
-- Internal application users — required for audit trail.
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_master (
    user_id       INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    user_code     VARCHAR(20)   NOT NULL,             -- e.g. USR-001
    full_name     VARCHAR(120)  NOT NULL,
    email_addr    VARCHAR(180)  NOT NULL,
    dept_name     VARCHAR(80)   NULL,
    user_role     ENUM(
                    'admin',
                    'analyst',
                    'viewer'
                  )              NOT NULL DEFAULT 'viewer',
    is_active     TINYINT(1)    NOT NULL DEFAULT 1,
    pwd_hash      VARCHAR(255)  NOT NULL,
    last_login_at DATETIME      NULL,
    created_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP
                                  ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT pk_user_master  PRIMARY KEY (user_id),
    CONSTRAINT uq_user_code    UNIQUE (user_code),
    CONSTRAINT uq_user_email   UNIQUE (email_addr)
) ENGINE=InnoDB COMMENT='Internal application users';