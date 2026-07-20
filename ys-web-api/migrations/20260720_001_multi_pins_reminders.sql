-- Multiple shared pinned messages and server-scheduled conversation reminders.

CREATE TABLE IF NOT EXISTS chat_pinned_messages (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    conversation_id BIGINT UNSIGNED NOT NULL,
    message_id BIGINT UNSIGNED NOT NULL,
    pinned_by VARCHAR(64) NOT NULL,
    pinned_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_chat_pinned_messages_conversation_message (conversation_id, message_id),
    INDEX idx_chat_pinned_messages_conversation_time (conversation_id, pinned_at, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO chat_pinned_messages (conversation_id, message_id, pinned_by, pinned_at)
SELECT id, pinned_message_id, COALESCE(message_pinned_by, created_by), COALESCE(message_pinned_at, updated_at)
FROM chat_conversations
WHERE pinned_message_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS chat_reminders (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    conversation_id BIGINT UNSIGNED NOT NULL,
    creator_userid VARCHAR(64) NOT NULL,
    title VARCHAR(240) NOT NULL,
    remind_at DATETIME NOT NULL,
    repeat_type VARCHAR(16) NOT NULL DEFAULT 'none',
    status VARCHAR(20) NOT NULL DEFAULT 'scheduled',
    fired_at DATETIME NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX idx_chat_reminders_due (status, remind_at),
    INDEX idx_chat_reminders_conversation (conversation_id, remind_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO chat_schema_migrations (version, applied_at)
VALUES ('20260720_001_multi_pins_reminders', CURRENT_TIMESTAMP);
