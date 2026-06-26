package services

import (
	"errors"
	"strings"
	"sync"
	"time"

	"web-api/internal/pkg/database"
	"web-api/internal/pkg/models/request"
	"web-api/internal/pkg/models/types"

	"gorm.io/gorm"
)

const (
	ErrChatUserNotFound              = "CHAT_USER_NOT_FOUND"
	ErrChatConversationNotFound      = "CHAT_CONVERSATION_NOT_FOUND"
	ErrChatNoPermission              = "CHAT_NO_PERMISSION"
	ErrChatEmptyMessage              = "CHAT_EMPTY_MESSAGE"
	ErrChatInvalidMessageType        = "CHAT_INVALID_MESSAGE_TYPE"
	ErrChatGroupNeedsMember          = "CHAT_GROUP_NEEDS_MEMBER"
	ErrChatCannotAddDirectMember     = "CHAT_CANNOT_ADD_DIRECT_MEMBER"
	ErrChatCannotRemoveDirectMember  = "CHAT_CANNOT_REMOVE_DIRECT_MEMBER"
	ErrChatOnlyOwnerCanManageMembers = "CHAT_ONLY_OWNER_CAN_MANAGE_MEMBERS"
	ErrChatMemberNotFound            = "CHAT_MEMBER_NOT_FOUND"
)

type ChatService struct {
	*BaseService
}

var ChatServiceInstance = &ChatService{}

var (
	chatSchemaMu    sync.Mutex
	chatSchemaReady bool
)

type chatConversationRecord struct {
	ID        uint64    `gorm:"column:id;primaryKey"`
	Type      string    `gorm:"column:type"`
	Name      string    `gorm:"column:name"`
	Avatar    string    `gorm:"column:avatar"`
	CreatedBy string    `gorm:"column:created_by"`
	CreatedAt time.Time `gorm:"column:created_at"`
	UpdatedAt time.Time `gorm:"column:updated_at"`
}

type chatMessageRecord struct {
	ID             uint64    `gorm:"column:id;primaryKey"`
	ConversationID uint64    `gorm:"column:conversation_id"`
	SenderUserid   string    `gorm:"column:sender_userid"`
	MessageType    string    `gorm:"column:message_type"`
	Content        string    `gorm:"column:content"`
	CreatedAt      time.Time `gorm:"column:created_at"`
}

type chatAttachmentRecord struct {
	ID           uint64    `gorm:"column:id;primaryKey"`
	MessageID    uint64    `gorm:"column:message_id"`
	FileName     string    `gorm:"column:file_name"`
	FileURL      string    `gorm:"column:file_url"`
	FileSize     int64     `gorm:"column:file_size"`
	MimeType     string    `gorm:"column:mime_type"`
	RelativePath string    `gorm:"column:relative_path"`
	CreatedAt    time.Time `gorm:"column:created_at"`
}

type conversationRow struct {
	ID               uint64     `gorm:"column:id"`
	Type             string     `gorm:"column:type"`
	Name             string     `gorm:"column:name"`
	Avatar           string     `gorm:"column:avatar"`
	MemberCount      int        `gorm:"column:member_count"`
	CreatedAt        time.Time  `gorm:"column:created_at"`
	UpdatedAt        time.Time  `gorm:"column:updated_at"`
	LastMessageID    *uint64    `gorm:"column:last_message_id"`
	LastSenderUserid string     `gorm:"column:last_sender_userid"`
	LastSenderName   string     `gorm:"column:last_sender_name"`
	LastSenderAvatar string     `gorm:"column:last_sender_avatar"`
	LastMessageType  string     `gorm:"column:last_message_type"`
	LastContent      string     `gorm:"column:last_content"`
	LastCreatedAt    *time.Time `gorm:"column:last_created_at"`
}

type memberRow struct {
	ConversationID uint64 `gorm:"column:conversation_id"`
	Userid         string `gorm:"column:userid"`
	Fullname       string `gorm:"column:fullname"`
	Avatar         string `gorm:"column:avatar"`
	Role           string `gorm:"column:role"`
}

type messageRow struct {
	ID             uint64    `gorm:"column:id"`
	ConversationID uint64    `gorm:"column:conversation_id"`
	SenderUserid   string    `gorm:"column:sender_userid"`
	SenderName     string    `gorm:"column:sender_name"`
	SenderAvatar   string    `gorm:"column:sender_avatar"`
	MessageType    string    `gorm:"column:message_type"`
	Content        string    `gorm:"column:content"`
	CreatedAt      time.Time `gorm:"column:created_at"`
}

func (s *ChatService) SearchUsers(currentUserid, keyword string) ([]types.ChatUser, error) {
	db, err := s.chatDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	keyword = strings.TrimSpace(keyword)
	query := db.Table("users u").
		Select(`
			u.userid,
			COALESCE(u.fullname, u.userid) AS fullname,
			COALESCE(u.avatar, '') AS avatar,
			CASE WHEN cc.id IS NULL THEN 0 ELSE 1 END AS is_contact
		`).
		Joins("LEFT JOIN chat_contacts cc ON cc.owner_userid = ? AND cc.contact_userid = u.userid", currentUserid).
		Where("u.userid <> ?", currentUserid).
		Limit(30).
		Order("is_contact DESC, fullname ASC")

	if keyword != "" {
		like := "%" + keyword + "%"
		query = query.Where("u.userid LIKE ? OR u.fullname LIKE ?", like, like)
	}

	var users []types.ChatUser
	if err := query.Scan(&users).Error; err != nil {
		return nil, errors.New(ErrSystem)
	}
	return users, nil
}

func (s *ChatService) ListContacts(currentUserid string) ([]types.ChatUser, error) {
	db, err := s.chatDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	var contacts []types.ChatUser
	if err := db.Raw(`
		SELECT u.userid,
			COALESCE(u.fullname, u.userid) AS fullname,
			COALESCE(u.avatar, '') AS avatar,
			1 AS is_contact
		FROM chat_contacts c
		JOIN users u ON u.userid = c.contact_userid
		WHERE c.owner_userid = ?
		ORDER BY u.fullname ASC, u.userid ASC
	`, currentUserid).Scan(&contacts).Error; err != nil {
		return nil, errors.New(ErrSystem)
	}
	return contacts, nil
}

func (s *ChatService) AddContact(currentUserid string, req request.AddContactRequest) (*types.ChatUser, error) {
	db, err := s.chatDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	contactUserid := strings.TrimSpace(req.Userid)
	if contactUserid == "" || contactUserid == currentUserid {
		return nil, errors.New(ErrInvalidInput)
	}

	var contact types.ChatUser
	if err := db.Table("users").
		Select("userid, COALESCE(fullname, userid) AS fullname, COALESCE(avatar, '') AS avatar").
		Where("userid = ?", contactUserid).
		Scan(&contact).Error; err != nil {
		return nil, errors.New(ErrSystem)
	}
	if contact.Userid == "" {
		return nil, errors.New(ErrChatUserNotFound)
	}

	if err := db.Exec(
		"INSERT IGNORE INTO chat_contacts (owner_userid, contact_userid, created_at) VALUES (?, ?, ?)",
		currentUserid,
		contactUserid,
		time.Now(),
	).Error; err != nil {
		return nil, errors.New(ErrSystem)
	}

	contact.IsContact = true
	return &contact, nil
}

func (s *ChatService) RegisterDeviceToken(currentUserid string, req request.RegisterDeviceTokenRequest) error {
	db, err := s.chatDB()
	if err != nil {
		return errors.New(ErrSystem)
	}

	token := strings.TrimSpace(req.Token)
	if token == "" {
		return errors.New(ErrInvalidInput)
	}

	platform := strings.ToLower(strings.TrimSpace(req.Platform))
	switch platform {
	case "android", "ios", "web":
	default:
		platform = "unknown"
	}

	if err := db.Exec(`
		INSERT INTO chat_device_tokens (userid, token, platform, updated_at, created_at)
		VALUES (?, ?, ?, ?, ?)
		ON DUPLICATE KEY UPDATE
			userid = VALUES(userid),
			platform = VALUES(platform),
			updated_at = VALUES(updated_at)
	`, currentUserid, token, platform, time.Now(), time.Now()).Error; err != nil {
		return errors.New(ErrSystem)
	}
	return nil
}

func (s *ChatService) ListConversations(currentUserid string) ([]types.ChatConversation, error) {
	db, err := s.chatDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}
	return s.loadConversations(db, currentUserid, 0)
}

func (s *ChatService) CreateDirectConversation(currentUserid string, req request.CreateDirectConversationRequest) (*types.ChatConversation, error) {
	db, err := s.chatDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	targetUserid := strings.TrimSpace(req.Userid)
	if targetUserid == "" || targetUserid == currentUserid {
		return nil, errors.New(ErrInvalidInput)
	}

	if ok, err := s.userExists(db, targetUserid); err != nil {
		return nil, errors.New(ErrSystem)
	} else if !ok {
		return nil, errors.New(ErrChatUserNotFound)
	}

	existingID, err := s.findDirectConversation(db, currentUserid, targetUserid)
	if err != nil {
		return nil, errors.New(ErrSystem)
	}
	if existingID > 0 {
		return s.getConversation(db, currentUserid, existingID)
	}

	var newID uint64
	err = db.Transaction(func(tx *gorm.DB) error {
		now := time.Now()
		conversation := chatConversationRecord{
			Type:      "direct",
			CreatedBy: currentUserid,
			CreatedAt: now,
			UpdatedAt: now,
		}
		if err := tx.Table("chat_conversations").Create(&conversation).Error; err != nil {
			return err
		}
		newID = conversation.ID

		members := []map[string]interface{}{
			{"conversation_id": newID, "userid": currentUserid, "role": "member", "joined_at": now},
			{"conversation_id": newID, "userid": targetUserid, "role": "member", "joined_at": now},
		}
		return tx.Table("chat_members").Create(&members).Error
	})
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	return s.getConversation(db, currentUserid, newID)
}

func (s *ChatService) CreateGroupConversation(currentUserid string, req request.CreateGroupConversationRequest) (*types.ChatConversation, error) {
	db, err := s.chatDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	name := strings.TrimSpace(req.Name)
	if name == "" {
		return nil, errors.New(ErrInvalidInput)
	}

	memberUserids := normalizeUserids(req.MemberUserids)
	memberUserids = appendUniqueUserid(memberUserids, currentUserid)
	if len(memberUserids) < 2 {
		return nil, errors.New(ErrChatGroupNeedsMember)
	}

	if err := s.ensureUsersExist(db, memberUserids); err != nil {
		return nil, err
	}

	var newID uint64
	err = db.Transaction(func(tx *gorm.DB) error {
		now := time.Now()
		conversation := chatConversationRecord{
			Type:      "group",
			Name:      name,
			CreatedBy: currentUserid,
			CreatedAt: now,
			UpdatedAt: now,
		}
		if err := tx.Table("chat_conversations").Create(&conversation).Error; err != nil {
			return err
		}
		newID = conversation.ID

		members := make([]map[string]interface{}, 0, len(memberUserids))
		for _, userid := range memberUserids {
			role := "member"
			if userid == currentUserid {
				role = "owner"
			}
			members = append(members, map[string]interface{}{
				"conversation_id": newID,
				"userid":          userid,
				"role":            role,
				"joined_at":       now,
			})
		}
		return tx.Table("chat_members").Create(&members).Error
	})
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	return s.getConversation(db, currentUserid, newID)
}

func (s *ChatService) AddMembers(currentUserid string, conversationID uint64, req request.AddConversationMembersRequest) (*types.ChatConversation, error) {
	db, err := s.chatDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	if ok, err := s.isConversationMember(db, conversationID, currentUserid); err != nil {
		return nil, errors.New(ErrSystem)
	} else if !ok {
		return nil, errors.New(ErrChatNoPermission)
	}

	conversationType, err := s.conversationType(db, conversationID)
	if err != nil {
		return nil, err
	}
	if conversationType == "direct" {
		return nil, errors.New(ErrChatCannotAddDirectMember)
	}

	userids := normalizeUserids(req.Userids)
	if len(userids) == 0 {
		return nil, errors.New(ErrInvalidInput)
	}

	if err := s.ensureUsersExist(db, userids); err != nil {
		return nil, err
	}

	err = db.Transaction(func(tx *gorm.DB) error {
		now := time.Now()
		for _, userid := range userids {
			if err := tx.Exec(
				"INSERT IGNORE INTO chat_members (conversation_id, userid, role, joined_at) VALUES (?, ?, 'member', ?)",
				conversationID,
				userid,
				now,
			).Error; err != nil {
				return err
			}
		}
		return tx.Table("chat_conversations").
			Where("id = ?", conversationID).
			Update("updated_at", now).Error
	})
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	return s.getConversation(db, currentUserid, conversationID)
}

func (s *ChatService) RemoveMember(currentUserid string, conversationID uint64, targetUserid string) (*types.ChatConversation, error) {
	db, err := s.chatDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	targetUserid = strings.TrimSpace(targetUserid)
	if targetUserid == "" || targetUserid == currentUserid {
		return nil, errors.New(ErrInvalidInput)
	}

	if ok, err := s.isConversationMember(db, conversationID, currentUserid); err != nil {
		return nil, errors.New(ErrSystem)
	} else if !ok {
		return nil, errors.New(ErrChatNoPermission)
	}

	conversationType, err := s.conversationType(db, conversationID)
	if err != nil {
		return nil, err
	}
	if conversationType == "direct" {
		return nil, errors.New(ErrChatCannotRemoveDirectMember)
	}

	if ok, err := s.isConversationOwner(db, conversationID, currentUserid); err != nil {
		return nil, errors.New(ErrSystem)
	} else if !ok {
		return nil, errors.New(ErrChatOnlyOwnerCanManageMembers)
	}

	if ok, err := s.isConversationMember(db, conversationID, targetUserid); err != nil {
		return nil, errors.New(ErrSystem)
	} else if !ok {
		return nil, errors.New(ErrChatMemberNotFound)
	}

	err = db.Transaction(func(tx *gorm.DB) error {
		now := time.Now()
		result := tx.Exec(
			"DELETE FROM chat_members WHERE conversation_id = ? AND userid = ?",
			conversationID,
			targetUserid,
		)
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected == 0 {
			return errors.New(ErrChatMemberNotFound)
		}
		return tx.Table("chat_conversations").
			Where("id = ?", conversationID).
			Update("updated_at", now).Error
	})
	if err != nil {
		if err.Error() == ErrChatMemberNotFound {
			return nil, errors.New(ErrChatMemberNotFound)
		}
		return nil, errors.New(ErrSystem)
	}

	return s.getConversation(db, currentUserid, conversationID)
}

func (s *ChatService) ListMessages(currentUserid string, conversationID uint64) ([]types.ChatMessage, error) {
	db, err := s.chatDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	if ok, err := s.isConversationMember(db, conversationID, currentUserid); err != nil {
		return nil, errors.New(ErrSystem)
	} else if !ok {
		return nil, errors.New(ErrChatNoPermission)
	}

	var rows []messageRow
	if err := db.Raw(`
		SELECT m.id, m.conversation_id, m.sender_userid,
			COALESCE(u.fullname, m.sender_userid) AS sender_name,
			COALESCE(u.avatar, '') AS sender_avatar,
			m.message_type, COALESCE(m.content, '') AS content, m.created_at
		FROM chat_messages m
		LEFT JOIN users u ON u.userid = m.sender_userid
		WHERE m.conversation_id = ?
		ORDER BY m.id DESC
		LIMIT 200
	`, conversationID).Scan(&rows).Error; err != nil {
		return nil, errors.New(ErrSystem)
	}

	for i, j := 0, len(rows)-1; i < j; i, j = i+1, j-1 {
		rows[i], rows[j] = rows[j], rows[i]
	}

	return s.buildMessages(db, rows)
}

func (s *ChatService) SendMessage(currentUserid string, conversationID uint64, req request.SendChatMessageRequest) (*types.ChatMessage, error) {
	db, err := s.chatDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	if ok, err := s.isConversationMember(db, conversationID, currentUserid); err != nil {
		return nil, errors.New(ErrSystem)
	} else if !ok {
		return nil, errors.New(ErrChatNoPermission)
	}

	messageType := strings.TrimSpace(req.Type)
	content := strings.TrimSpace(req.Content)
	if !isValidMessageType(messageType) {
		return nil, errors.New(ErrChatInvalidMessageType)
	}
	if (messageType == "text" || messageType == "link") && content == "" {
		return nil, errors.New(ErrChatEmptyMessage)
	}
	if (messageType == "file" || messageType == "folder" || messageType == "voice") && len(req.Attachments) == 0 {
		return nil, errors.New(ErrChatEmptyMessage)
	}

	var messageID uint64
	err = db.Transaction(func(tx *gorm.DB) error {
		now := time.Now()
		message := chatMessageRecord{
			ConversationID: conversationID,
			SenderUserid:   currentUserid,
			MessageType:    messageType,
			Content:        content,
			CreatedAt:      now,
		}
		if err := tx.Table("chat_messages").Create(&message).Error; err != nil {
			return err
		}
		messageID = message.ID

		for _, attachment := range req.Attachments {
			record := chatAttachmentRecord{
				MessageID:    messageID,
				FileName:     strings.TrimSpace(attachment.FileName),
				FileURL:      strings.TrimSpace(attachment.FileURL),
				FileSize:     attachment.FileSize,
				MimeType:     strings.TrimSpace(attachment.MimeType),
				RelativePath: strings.TrimSpace(attachment.RelativePath),
				CreatedAt:    now,
			}
			if record.FileName == "" || record.FileURL == "" {
				continue
			}
			if err := tx.Table("chat_message_attachments").Create(&record).Error; err != nil {
				return err
			}
		}

		return tx.Table("chat_conversations").
			Where("id = ?", conversationID).
			Update("updated_at", now).Error
	})
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	message, err := s.loadMessageByID(db, messageID)
	if err != nil {
		return nil, err
	}
	s.broadcastMessageCreated(db, conversationID, message)
	go PushServiceInstance.SendChatMessageNotification(db, currentUserid, conversationID, message.ID, message.Type, message.Content)
	return message, nil
}

func (s *ChatService) broadcastMessageCreated(db *gorm.DB, conversationID uint64, message *types.ChatMessage) {
	userids, err := s.conversationMemberUserids(db, conversationID)
	if err != nil || len(userids) == 0 {
		return
	}

	RealtimeHubInstance.BroadcastToUsers(userids, RealtimeEvent{
		Type:           "chat.message.created",
		ConversationID: conversationID,
		Message:        message,
		SentAt:         time.Now(),
	})
}

func (s *ChatService) chatDB() (*gorm.DB, error) {
	db, err := database.WEBDB_DBConnection()
	if err != nil {
		return nil, err
	}
	if err := ensureChatSchema(db); err != nil {
		return nil, err
	}
	return db, nil
}

func ensureChatSchema(db *gorm.DB) error {
	if chatSchemaReady {
		return nil
	}

	chatSchemaMu.Lock()
	defer chatSchemaMu.Unlock()

	if chatSchemaReady {
		return nil
	}

	statements := []string{
		`CREATE TABLE IF NOT EXISTS chat_conversations (
			id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			type VARCHAR(20) NOT NULL,
			name VARCHAR(160) NULL,
			avatar VARCHAR(255) NULL,
			created_by VARCHAR(64) NOT NULL,
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
			PRIMARY KEY (id),
			INDEX idx_chat_conversations_updated_at (updated_at),
			INDEX idx_chat_conversations_created_by (created_by)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
		`CREATE TABLE IF NOT EXISTS chat_members (
			id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			conversation_id BIGINT UNSIGNED NOT NULL,
			userid VARCHAR(64) NOT NULL,
			role VARCHAR(20) NOT NULL DEFAULT 'member',
			joined_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			PRIMARY KEY (id),
			UNIQUE KEY uk_chat_members_conversation_user (conversation_id, userid),
			INDEX idx_chat_members_userid (userid),
			INDEX idx_chat_members_conversation (conversation_id)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
		`CREATE TABLE IF NOT EXISTS chat_contacts (
			id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			owner_userid VARCHAR(64) NOT NULL,
			contact_userid VARCHAR(64) NOT NULL,
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			PRIMARY KEY (id),
			UNIQUE KEY uk_chat_contacts_owner_contact (owner_userid, contact_userid),
			INDEX idx_chat_contacts_owner (owner_userid),
			INDEX idx_chat_contacts_contact (contact_userid)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
		`CREATE TABLE IF NOT EXISTS chat_device_tokens (
			id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			userid VARCHAR(64) NOT NULL,
			token VARCHAR(512) NOT NULL,
			platform VARCHAR(32) NOT NULL DEFAULT 'unknown',
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
			PRIMARY KEY (id),
			UNIQUE KEY uk_chat_device_tokens_token (token),
			INDEX idx_chat_device_tokens_userid (userid)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
		`CREATE TABLE IF NOT EXISTS chat_messages (
			id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			conversation_id BIGINT UNSIGNED NOT NULL,
			sender_userid VARCHAR(64) NOT NULL,
			message_type VARCHAR(20) NOT NULL,
			content TEXT NULL,
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			PRIMARY KEY (id),
			INDEX idx_chat_messages_conversation_created (conversation_id, created_at),
			INDEX idx_chat_messages_sender (sender_userid)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
		`CREATE TABLE IF NOT EXISTS chat_message_attachments (
			id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			message_id BIGINT UNSIGNED NOT NULL,
			file_name VARCHAR(255) NOT NULL,
			file_url VARCHAR(1024) NOT NULL,
			file_size BIGINT NOT NULL DEFAULT 0,
			mime_type VARCHAR(160) NULL,
			relative_path VARCHAR(1024) NULL,
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			PRIMARY KEY (id),
			INDEX idx_chat_message_attachments_message (message_id)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
	}

	for _, statement := range statements {
		if err := db.Exec(statement).Error; err != nil {
			return err
		}
	}

	chatSchemaReady = true
	return nil
}

func (s *ChatService) userExists(db *gorm.DB, userid string) (bool, error) {
	var count int64
	if err := db.Table("users").Where("userid = ?", userid).Count(&count).Error; err != nil {
		return false, err
	}
	return count > 0, nil
}

func (s *ChatService) ensureUsersExist(db *gorm.DB, userids []string) error {
	if len(userids) == 0 {
		return errors.New(ErrInvalidInput)
	}

	var count int64
	if err := db.Table("users").Where("userid IN ?", userids).Count(&count).Error; err != nil {
		return errors.New(ErrSystem)
	}
	if int(count) != len(userids) {
		return errors.New(ErrChatUserNotFound)
	}
	return nil
}

func (s *ChatService) findDirectConversation(db *gorm.DB, firstUserid, secondUserid string) (uint64, error) {
	var conversationID uint64
	err := db.Raw(`
		SELECT c.id
		FROM chat_conversations c
		JOIN chat_members m1 ON m1.conversation_id = c.id AND m1.userid = ?
		JOIN chat_members m2 ON m2.conversation_id = c.id AND m2.userid = ?
		WHERE c.type = 'direct'
			AND (SELECT COUNT(*) FROM chat_members mx WHERE mx.conversation_id = c.id) = 2
		LIMIT 1
	`, firstUserid, secondUserid).Scan(&conversationID).Error
	return conversationID, err
}

func (s *ChatService) isConversationMember(db *gorm.DB, conversationID uint64, userid string) (bool, error) {
	var count int64
	err := db.Table("chat_members").
		Where("conversation_id = ? AND userid = ?", conversationID, userid).
		Count(&count).Error
	return count > 0, err
}

func (s *ChatService) isConversationOwner(db *gorm.DB, conversationID uint64, userid string) (bool, error) {
	var count int64
	err := db.Table("chat_members").
		Where("conversation_id = ? AND userid = ? AND role = ?", conversationID, userid, "owner").
		Count(&count).Error
	return count > 0, err
}

func (s *ChatService) conversationType(db *gorm.DB, conversationID uint64) (string, error) {
	var conversation struct {
		Type string `gorm:"column:type"`
	}
	err := db.Table("chat_conversations").
		Select("type").
		Where("id = ?", conversationID).
		Take(&conversation).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return "", errors.New(ErrChatConversationNotFound)
	}
	if err != nil {
		return "", errors.New(ErrSystem)
	}
	return conversation.Type, nil
}

func (s *ChatService) conversationMemberUserids(db *gorm.DB, conversationID uint64) ([]string, error) {
	var userids []string
	err := db.Table("chat_members").
		Where("conversation_id = ?", conversationID).
		Pluck("userid", &userids).Error
	return userids, err
}

func (s *ChatService) getConversation(db *gorm.DB, currentUserid string, conversationID uint64) (*types.ChatConversation, error) {
	conversations, err := s.loadConversations(db, currentUserid, conversationID)
	if err != nil {
		return nil, err
	}
	if len(conversations) == 0 {
		return nil, errors.New(ErrChatConversationNotFound)
	}
	return &conversations[0], nil
}

func (s *ChatService) loadConversations(db *gorm.DB, currentUserid string, conversationID uint64) ([]types.ChatConversation, error) {
	var rows []conversationRow
	query := `
		SELECT c.id, c.type, COALESCE(c.name, '') AS name, COALESCE(c.avatar, '') AS avatar,
			(SELECT COUNT(*) FROM chat_members cm_count WHERE cm_count.conversation_id = c.id) AS member_count,
			c.created_at, c.updated_at,
			m.id AS last_message_id,
			COALESCE(m.sender_userid, '') AS last_sender_userid,
			COALESCE(u.fullname, m.sender_userid, '') AS last_sender_name,
			COALESCE(u.avatar, '') AS last_sender_avatar,
			COALESCE(m.message_type, '') AS last_message_type,
			COALESCE(m.content, '') AS last_content,
			m.created_at AS last_created_at
		FROM chat_conversations c
		JOIN chat_members cm ON cm.conversation_id = c.id AND cm.userid = ?
		LEFT JOIN chat_messages m ON m.id = (
			SELECT lm.id FROM chat_messages lm
			WHERE lm.conversation_id = c.id
			ORDER BY lm.id DESC
			LIMIT 1
		)
		LEFT JOIN users u ON u.userid = m.sender_userid
	`
	args := []interface{}{currentUserid}
	if conversationID > 0 {
		query += " WHERE c.id = ?"
		args = append(args, conversationID)
	}
	query += " ORDER BY COALESCE(m.created_at, c.updated_at) DESC, c.id DESC"

	if err := db.Raw(query, args...).Scan(&rows).Error; err != nil {
		return nil, errors.New(ErrSystem)
	}
	if len(rows) == 0 {
		return []types.ChatConversation{}, nil
	}

	ids := make([]uint64, 0, len(rows))
	for _, row := range rows {
		ids = append(ids, row.ID)
	}

	membersByConversation, err := s.loadMembers(db, ids)
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	conversations := make([]types.ChatConversation, 0, len(rows))
	for _, row := range rows {
		members := membersByConversation[row.ID]
		conversation := types.ChatConversation{
			ID:          row.ID,
			Type:        row.Type,
			Name:        row.Name,
			Avatar:      row.Avatar,
			MemberCount: row.MemberCount,
			Members:     members,
			CreatedAt:   row.CreatedAt,
			UpdatedAt:   row.UpdatedAt,
		}

		if conversation.Type == "direct" {
			for _, member := range members {
				if member.Userid != currentUserid {
					conversation.Name = member.Fullname
					conversation.Avatar = member.Avatar
					break
				}
			}
			if conversation.Name == "" && len(members) > 0 {
				conversation.Name = members[0].Fullname
				conversation.Avatar = members[0].Avatar
			}
		} else if conversation.Name == "" {
			conversation.Name = groupFallbackName(members)
		}

		if row.LastMessageID != nil && *row.LastMessageID > 0 {
			createdAt := row.UpdatedAt
			if row.LastCreatedAt != nil {
				createdAt = *row.LastCreatedAt
			}
			conversation.LastMessage = &types.ChatMessage{
				ID:             *row.LastMessageID,
				ConversationID: row.ID,
				SenderUserid:   row.LastSenderUserid,
				SenderName:     row.LastSenderName,
				SenderAvatar:   row.LastSenderAvatar,
				Type:           row.LastMessageType,
				Content:        row.LastContent,
				CreatedAt:      createdAt,
			}
		}

		conversations = append(conversations, conversation)
	}

	return conversations, nil
}

func (s *ChatService) loadMembers(db *gorm.DB, conversationIDs []uint64) (map[uint64][]types.ChatUser, error) {
	var rows []memberRow
	if err := db.Raw(`
		SELECT cm.conversation_id,
			COALESCE(u.userid, cm.userid) AS userid,
			COALESCE(u.fullname, cm.userid) AS fullname,
			COALESCE(u.avatar, '') AS avatar,
			COALESCE(cm.role, 'member') AS role
		FROM chat_members cm
		LEFT JOIN users u ON u.userid = cm.userid
		WHERE cm.conversation_id IN ?
		ORDER BY cm.joined_at ASC
	`, conversationIDs).Scan(&rows).Error; err != nil {
		return nil, err
	}

	result := make(map[uint64][]types.ChatUser)
	for _, row := range rows {
		result[row.ConversationID] = append(result[row.ConversationID], types.ChatUser{
			Userid:   row.Userid,
			Fullname: row.Fullname,
			Avatar:   row.Avatar,
			Role:     row.Role,
		})
	}
	return result, nil
}

func (s *ChatService) loadMessageByID(db *gorm.DB, messageID uint64) (*types.ChatMessage, error) {
	var rows []messageRow
	if err := db.Raw(`
		SELECT m.id, m.conversation_id, m.sender_userid,
			COALESCE(u.fullname, m.sender_userid) AS sender_name,
			COALESCE(u.avatar, '') AS sender_avatar,
			m.message_type, COALESCE(m.content, '') AS content, m.created_at
		FROM chat_messages m
		LEFT JOIN users u ON u.userid = m.sender_userid
		WHERE m.id = ?
	`, messageID).Scan(&rows).Error; err != nil {
		return nil, errors.New(ErrSystem)
	}
	messages, err := s.buildMessages(db, rows)
	if err != nil {
		return nil, err
	}
	if len(messages) == 0 {
		return nil, errors.New(ErrSystem)
	}
	return &messages[0], nil
}

func (s *ChatService) buildMessages(db *gorm.DB, rows []messageRow) ([]types.ChatMessage, error) {
	if len(rows) == 0 {
		return []types.ChatMessage{}, nil
	}

	messageIDs := make([]uint64, 0, len(rows))
	for _, row := range rows {
		messageIDs = append(messageIDs, row.ID)
	}

	attachmentsByMessage, err := s.loadAttachments(db, messageIDs)
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	messages := make([]types.ChatMessage, 0, len(rows))
	for _, row := range rows {
		messages = append(messages, types.ChatMessage{
			ID:             row.ID,
			ConversationID: row.ConversationID,
			SenderUserid:   row.SenderUserid,
			SenderName:     row.SenderName,
			SenderAvatar:   row.SenderAvatar,
			Type:           row.MessageType,
			Content:        row.Content,
			Attachments:    attachmentsByMessage[row.ID],
			CreatedAt:      row.CreatedAt,
		})
	}
	return messages, nil
}

func (s *ChatService) loadAttachments(db *gorm.DB, messageIDs []uint64) (map[uint64][]types.ChatAttachment, error) {
	var rows []chatAttachmentRecord
	if err := db.Table("chat_message_attachments").
		Where("message_id IN ?", messageIDs).
		Order("id ASC").
		Scan(&rows).Error; err != nil {
		return nil, err
	}

	result := make(map[uint64][]types.ChatAttachment)
	for _, row := range rows {
		result[row.MessageID] = append(result[row.MessageID], types.ChatAttachment{
			ID:           row.ID,
			MessageID:    row.MessageID,
			FileName:     row.FileName,
			FileURL:      row.FileURL,
			FileSize:     row.FileSize,
			MimeType:     row.MimeType,
			RelativePath: row.RelativePath,
			CreatedAt:    row.CreatedAt,
		})
	}
	return result, nil
}

func normalizeUserids(userids []string) []string {
	result := make([]string, 0, len(userids))
	seen := make(map[string]bool)
	for _, userid := range userids {
		userid = strings.TrimSpace(userid)
		if userid == "" || seen[userid] {
			continue
		}
		seen[userid] = true
		result = append(result, userid)
	}
	return result
}

func appendUniqueUserid(userids []string, userid string) []string {
	userid = strings.TrimSpace(userid)
	if userid == "" {
		return userids
	}
	for _, item := range userids {
		if item == userid {
			return userids
		}
	}
	return append(userids, userid)
}

func groupFallbackName(members []types.ChatUser) string {
	names := make([]string, 0, len(members))
	for _, member := range members {
		if member.Fullname != "" {
			names = append(names, member.Fullname)
		}
		if len(names) == 3 {
			break
		}
	}
	if len(names) == 0 {
		return "Nhom chat"
	}
	return strings.Join(names, ", ")
}

func isValidMessageType(messageType string) bool {
	switch messageType {
	case "text", "link", "file", "folder", "voice":
		return true
	default:
		return false
	}
}
