-- Additive, rerunnable MySQL/MariaDB migration for production chat features.
-- Existing messages are preserved. NULL client_message_id values remain valid.

CREATE TABLE IF NOT EXISTS chat_schema_migrations (
    version VARCHAR(128) NOT NULL,
    applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELIMITER $$
DROP PROCEDURE IF EXISTS ys_chat_add_column$$
DROP PROCEDURE IF EXISTS ys_chat_add_index$$
CREATE PROCEDURE ys_chat_add_column(
    IN p_table VARCHAR(64),
    IN p_column VARCHAR(64),
    IN p_definition TEXT
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = DATABASE()
          AND table_name = p_table
          AND column_name = p_column
    ) THEN
        SET @ddl = CONCAT('ALTER TABLE `', p_table, '` ADD COLUMN `', p_column, '` ', p_definition);
        PREPARE stmt FROM @ddl;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
END$$

CREATE PROCEDURE ys_chat_add_index(
    IN p_table VARCHAR(64),
    IN p_index VARCHAR(128),
    IN p_definition TEXT
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.statistics
        WHERE table_schema = DATABASE()
          AND table_name = p_table
          AND index_name = p_index
    ) THEN
        SET @ddl = CONCAT('ALTER TABLE `', p_table, '` ADD ', p_definition);
        PREPARE stmt FROM @ddl;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
END$$
DELIMITER ;

CALL ys_chat_add_column('chat_messages', 'client_message_id', 'CHAR(36) NULL');
CALL ys_chat_add_column('chat_messages', 'server_sequence', 'BIGINT UNSIGNED NULL');
CALL ys_chat_add_column('chat_messages', 'version', 'INT UNSIGNED NOT NULL DEFAULT 1');
CALL ys_chat_add_column('chat_messages', 'edited_at', 'DATETIME NULL');
CALL ys_chat_add_column('chat_messages', 'deleted_at', 'DATETIME NULL');
CALL ys_chat_add_column('chat_messages', 'deleted_by', 'VARCHAR(64) NULL');

CALL ys_chat_add_column('chat_members', 'last_delivered_message_id', 'BIGINT UNSIGNED NULL');
CALL ys_chat_add_column('chat_members', 'last_read_message_id', 'BIGINT UNSIGNED NULL');
CALL ys_chat_add_column('chat_members', 'last_read_at', 'DATETIME NULL');
CALL ys_chat_add_column('chat_members', 'unread_count', 'INT UNSIGNED NOT NULL DEFAULT 0');
CALL ys_chat_add_column('chat_members', 'mute_until', 'DATETIME NULL');
CALL ys_chat_add_column('chat_members', 'pinned_at', 'DATETIME NULL');
CALL ys_chat_add_column('chat_members', 'archived_at', 'DATETIME NULL');

CALL ys_chat_add_column('chat_message_attachments', 'deleted_at', 'DATETIME NULL');
CALL ys_chat_add_column('chat_message_attachments', 'deleted_by', 'VARCHAR(64) NULL');
CALL ys_chat_add_column('chat_message_attachments', 'relative_path', 'VARCHAR(1024) NULL');

CREATE TABLE IF NOT EXISTS chat_pending_uploads (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    userid VARCHAR(64) NOT NULL,
    file_url VARCHAR(1024) NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    file_size BIGINT NOT NULL DEFAULT 0,
    mime_type VARCHAR(160) NULL,
    relative_path VARCHAR(1024) NULL,
    claimed_message_id BIGINT UNSIGNED NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_chat_pending_uploads_url (file_url(191)),
    KEY idx_chat_pending_uploads_user_claimed (userid, claimed_message_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS chat_message_receipts (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    message_id BIGINT UNSIGNED NOT NULL,
    conversation_id BIGINT UNSIGNED NOT NULL,
    userid VARCHAR(64) NOT NULL,
    delivered_at DATETIME NULL,
    read_at DATETIME NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_chat_message_receipts_message_user (message_id, userid),
    KEY idx_chat_message_receipts_conversation_user_message (conversation_id, userid, message_id),
    KEY idx_chat_message_receipts_message_state (message_id, read_at, delivered_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS chat_message_user_deletions (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    message_id BIGINT UNSIGNED NOT NULL,
    conversation_id BIGINT UNSIGNED NOT NULL,
    userid VARCHAR(64) NOT NULL,
    deleted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_chat_message_user_deletions_message_user (message_id, userid),
    KEY idx_chat_message_user_deletions_user_conversation_message (userid, conversation_id, message_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS chat_message_reactions (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    message_id BIGINT UNSIGNED NOT NULL,
    conversation_id BIGINT UNSIGNED NOT NULL,
    userid VARCHAR(64) NOT NULL,
    emoji VARCHAR(64) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uk_chat_message_reactions_user_message_emoji (userid, message_id, emoji),
    KEY idx_chat_message_reactions_message_emoji (message_id, emoji)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS chat_message_audit (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    message_id BIGINT UNSIGNED NOT NULL,
    conversation_id BIGINT UNSIGNED NOT NULL,
    actor_userid VARCHAR(64) NOT NULL,
    action VARCHAR(32) NOT NULL,
    previous_version INT UNSIGNED NOT NULL DEFAULT 1,
    new_version INT UNSIGNED NOT NULL DEFAULT 1,
    snapshot_json LONGTEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_chat_message_audit_message_created (message_id, created_at),
    KEY idx_chat_message_audit_actor_created (actor_userid, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- id is the immutable key and also makes this compatible with SQL_SAFE_UPDATES=1.
UPDATE chat_messages
SET server_sequence = id
WHERE id > 0
  AND (server_sequence IS NULL OR server_sequence = 0);

CALL ys_chat_add_index('chat_messages', 'uk_chat_messages_sender_client',
    'UNIQUE KEY `uk_chat_messages_sender_client` (`sender_userid`, `client_message_id`)');
CALL ys_chat_add_index('chat_messages', 'uk_chat_messages_conversation_sequence',
    'UNIQUE KEY `uk_chat_messages_conversation_sequence` (`conversation_id`, `server_sequence`)');
CALL ys_chat_add_index('chat_messages', 'idx_chat_messages_conversation_id',
    'KEY `idx_chat_messages_conversation_id` (`conversation_id`, `id`)');
CALL ys_chat_add_index('chat_messages', 'idx_chat_messages_conversation_created_id',
    'KEY `idx_chat_messages_conversation_created_id` (`conversation_id`, `created_at`, `id`)');
CALL ys_chat_add_index('chat_messages', 'idx_chat_messages_conversation_sender_id',
    'KEY `idx_chat_messages_conversation_sender_id` (`conversation_id`, `sender_userid`, `id`)');
CALL ys_chat_add_index('chat_messages', 'ft_chat_messages_content',
    'FULLTEXT KEY `ft_chat_messages_content` (`content`)');
CALL ys_chat_add_index('chat_members', 'idx_chat_members_user_settings',
    'KEY `idx_chat_members_user_settings` (`userid`, `archived_at`, `pinned_at`)');
CALL ys_chat_add_index('chat_members', 'idx_chat_members_conversation_read',
    'KEY `idx_chat_members_conversation_read` (`conversation_id`, `last_read_message_id`)');
CALL ys_chat_add_index('chat_message_attachments', 'ft_chat_attachments_name_path',
    'FULLTEXT KEY `ft_chat_attachments_name_path` (`file_name`, `relative_path`)');
CALL ys_chat_add_index('chat_message_attachments', 'idx_chat_attachments_mime_deleted_message',
    'KEY `idx_chat_attachments_mime_deleted_message` (`mime_type`, `deleted_at`, `message_id`)');

-- Legacy rows predate receipts/read-state. Treat them as already delivered/read
-- so deploying this migration does not create surprise unread badges.
INSERT IGNORE INTO chat_message_receipts
    (message_id, conversation_id, userid, delivered_at, read_at, created_at, updated_at)
SELECT m.id, m.conversation_id, cm.userid, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP,
       m.created_at, CURRENT_TIMESTAMP
FROM chat_messages AS m
JOIN chat_members AS cm
  ON cm.conversation_id = m.conversation_id
 AND cm.userid <> m.sender_userid
 AND (cm.joined_at IS NULL OR m.created_at >= cm.joined_at)
WHERE m.message_type <> 'system';

UPDATE chat_members AS cm
LEFT JOIN (
    SELECT conversation_id, MAX(id) AS last_message_id, MAX(created_at) AS last_message_at
    FROM chat_messages
    WHERE message_type <> 'system'
    GROUP BY conversation_id
) AS legacy ON legacy.conversation_id = cm.conversation_id
SET cm.last_delivered_message_id = legacy.last_message_id,
    cm.last_read_message_id = legacy.last_message_id,
    cm.last_read_at = COALESCE(legacy.last_message_at, cm.joined_at, CURRENT_TIMESTAMP),
    cm.unread_count = 0
WHERE cm.id > 0
  AND cm.last_read_message_id IS NULL;

INSERT IGNORE INTO chat_schema_migrations (version, applied_at)
VALUES ('20260715_001_chat_production_features', CURRENT_TIMESTAMP);

DROP PROCEDURE ys_chat_add_index;
DROP PROCEDURE ys_chat_add_column;

-- Verification (all should be 1 after a successful run).
SELECT
    EXISTS(SELECT 1 FROM information_schema.statistics
           WHERE table_schema = DATABASE() AND table_name = 'chat_messages'
             AND index_name = 'uk_chat_messages_sender_client') AS idempotency_index_ok,
    EXISTS(SELECT 1 FROM information_schema.statistics
           WHERE table_schema = DATABASE() AND table_name = 'chat_messages'
             AND index_name = 'uk_chat_messages_conversation_sequence') AS catchup_index_ok,
    EXISTS(SELECT 1 FROM information_schema.tables
           WHERE table_schema = DATABASE() AND table_name = 'chat_message_audit') AS edit_audit_ok;
