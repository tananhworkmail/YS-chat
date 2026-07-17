-- Reliability storage for call arbitration and history. No media/audio is stored.

CREATE TABLE IF NOT EXISTS chat_calls (
    call_id VARCHAR(128) NOT NULL,
    conversation_id BIGINT UNSIGNED NOT NULL,
    caller_userid VARCHAR(64) NOT NULL,
    callee_userid VARCHAR(64) NOT NULL,
    accepted_by_device_id VARCHAR(128) NULL,
    started_at DATETIME NOT NULL,
    answered_at DATETIME NULL,
    ended_at DATETIME NULL,
    status VARCHAR(32) NOT NULL,
    duration_seconds BIGINT NOT NULL DEFAULT 0,
    end_reason VARCHAR(64) NULL,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (call_id),
    KEY idx_chat_calls_conversation_started (conversation_id, started_at),
    KEY idx_chat_calls_caller_started (caller_userid, started_at),
    KEY idx_chat_calls_callee_started (callee_userid, started_at),
    KEY idx_chat_calls_status_started (status, started_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO chat_schema_migrations (version, applied_at)
VALUES ('20260717_002_realtime_calls', CURRENT_TIMESTAMP);
