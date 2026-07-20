-- Distinguishes audio and video calls. WebRTC media itself is never stored.

ALTER TABLE chat_calls
    ADD COLUMN media_type VARCHAR(16) NOT NULL DEFAULT 'audio' AFTER callee_userid;

INSERT IGNORE INTO chat_schema_migrations (version, applied_at)
VALUES ('20260718_001_video_calls', CURRENT_TIMESTAMP);
