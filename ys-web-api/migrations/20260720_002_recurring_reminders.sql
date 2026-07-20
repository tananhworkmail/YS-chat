-- Recurring conversation reminders.

DROP PROCEDURE IF EXISTS ys_chat_add_column;
DELIMITER //
CREATE PROCEDURE ys_chat_add_column(
    IN table_name_value VARCHAR(64),
    IN column_name_value VARCHAR(64),
    IN column_definition_value TEXT
)
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = table_name_value
          AND column_name = column_name_value
    ) THEN
        SET @ddl = CONCAT(
            'ALTER TABLE `', table_name_value, '` ADD COLUMN `',
            column_name_value, '` ', column_definition_value
        );
        PREPARE statement_value FROM @ddl;
        EXECUTE statement_value;
        DEALLOCATE PREPARE statement_value;
    END IF;
END //
DELIMITER ;

CALL ys_chat_add_column('chat_reminders', 'repeat_type', 'VARCHAR(16) NOT NULL DEFAULT ''none'' AFTER remind_at');

INSERT IGNORE INTO chat_schema_migrations (version, applied_at)
VALUES ('20260720_002_recurring_reminders', CURRENT_TIMESTAMP);

DROP PROCEDURE ys_chat_add_column;
