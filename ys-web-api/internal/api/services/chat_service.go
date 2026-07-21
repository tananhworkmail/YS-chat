package services

import (
	"errors"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"web-api/internal/pkg/database"
	"web-api/internal/pkg/models/request"
	"web-api/internal/pkg/models/types"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
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
	ErrChatInvalidPoll               = "CHAT_INVALID_POLL"
	ErrChatPollNotFound              = "CHAT_POLL_NOT_FOUND"
	ErrChatPollClosed                = "CHAT_POLL_CLOSED"
	ErrChatPollCustomOptionsDisabled = "CHAT_POLL_CUSTOM_OPTIONS_DISABLED"
	ErrChatMessageNotFound           = "CHAT_MESSAGE_NOT_FOUND"
	ErrChatMessageVersionConflict    = "CHAT_MESSAGE_VERSION_CONFLICT"
	ErrChatClientMessageIDConflict   = "CHAT_CLIENT_MESSAGE_ID_CONFLICT"
	ErrChatRecallWindowExpired       = "CHAT_RECALL_WINDOW_EXPIRED"
	defaultMessagePageSize           = 50
	maxMessagePageSize               = 100
	minPollOptions                   = 2
	maxPollOptions                   = 20
	maxPollQuestionLength            = 500
	maxPollOptionLength              = 160
)

type ChatService struct {
	*BaseService
}

var ChatServiceInstance = &ChatService{}

var (
	chatSchemaMu    sync.Mutex
	chatSchemaReady atomic.Bool
)

type chatConversationRecord struct {
	ID              uint64     `gorm:"column:id;primaryKey"`
	Type            string     `gorm:"column:type"`
	Name            string     `gorm:"column:name"`
	Avatar          string     `gorm:"column:avatar"`
	Background      string     `gorm:"column:background"`
	PinnedMessageID *uint64    `gorm:"column:pinned_message_id"`
	MessagePinnedBy string     `gorm:"column:message_pinned_by"`
	MessagePinnedAt *time.Time `gorm:"column:message_pinned_at"`
	CreatedBy       string     `gorm:"column:created_by"`
	CreatedAt       time.Time  `gorm:"column:created_at"`
	UpdatedAt       time.Time  `gorm:"column:updated_at"`
}

type chatPinnedMessageRecord struct {
	ID             uint64    `gorm:"column:id;primaryKey"`
	ConversationID uint64    `gorm:"column:conversation_id"`
	MessageID      uint64    `gorm:"column:message_id"`
	PinnedBy       string    `gorm:"column:pinned_by"`
	PinnedAt       time.Time `gorm:"column:pinned_at"`
}

type chatReminderRecord struct {
	ID             uint64     `gorm:"column:id;primaryKey"`
	ConversationID uint64     `gorm:"column:conversation_id"`
	CreatorUserid  string     `gorm:"column:creator_userid"`
	Title          string     `gorm:"column:title"`
	RemindAt       time.Time  `gorm:"column:remind_at"`
	RepeatType     string     `gorm:"column:repeat_type"`
	Status         string     `gorm:"column:status"`
	FiredAt        *time.Time `gorm:"column:fired_at"`
	CreatedAt      time.Time  `gorm:"column:created_at"`
	UpdatedAt      time.Time  `gorm:"column:updated_at"`
}

type chatMessageRecord struct {
	ID                     uint64    `gorm:"column:id;primaryKey"`
	ConversationID         uint64    `gorm:"column:conversation_id"`
	SenderUserid           string    `gorm:"column:sender_userid"`
	MessageType            string    `gorm:"column:message_type"`
	Content                string    `gorm:"column:content"`
	ReplyToMessageID       *uint64   `gorm:"column:reply_to_message_id"`
	ForwardedFromMessageID *uint64   `gorm:"column:forwarded_from_message_id"`
	CreatedAt              time.Time `gorm:"column:created_at"`
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

type chatPollRecord struct {
	ID                 uint64     `gorm:"column:id;primaryKey"`
	MessageID          uint64     `gorm:"column:message_id"`
	ConversationID     uint64     `gorm:"column:conversation_id"`
	Question           string     `gorm:"column:question"`
	AllowCustomOptions bool       `gorm:"column:allow_custom_options"`
	AllowMultiple      bool       `gorm:"column:allow_multiple"`
	ShowVoters         bool       `gorm:"column:show_voters"`
	IsClosed           bool       `gorm:"column:is_closed"`
	ClosedBy           string     `gorm:"column:closed_by"`
	ClosedAt           *time.Time `gorm:"column:closed_at"`
	CreatedBy          string     `gorm:"column:created_by"`
	CreatedAt          time.Time  `gorm:"column:created_at"`
	UpdatedAt          time.Time  `gorm:"column:updated_at"`
}

type chatPollOptionRecord struct {
	ID        uint64    `gorm:"column:id;primaryKey"`
	PollID    uint64    `gorm:"column:poll_id"`
	Text      string    `gorm:"column:option_text"`
	CreatedBy string    `gorm:"column:created_by"`
	IsCustom  bool      `gorm:"column:is_custom"`
	CreatedAt time.Time `gorm:"column:created_at"`
}

type chatPollVoteRecord struct {
	ID        uint64    `gorm:"column:id;primaryKey"`
	PollID    uint64    `gorm:"column:poll_id"`
	OptionID  uint64    `gorm:"column:option_id"`
	Userid    string    `gorm:"column:userid"`
	CreatedAt time.Time `gorm:"column:created_at"`
}

type conversationRow struct {
	ID                  uint64     `gorm:"column:id"`
	Type                string     `gorm:"column:type"`
	Name                string     `gorm:"column:name"`
	Avatar              string     `gorm:"column:avatar"`
	Background          string     `gorm:"column:background"`
	MemberCount         int        `gorm:"column:member_count"`
	PinnedMessageID     *uint64    `gorm:"column:pinned_message_id"`
	MessagePinnedBy     string     `gorm:"column:message_pinned_by"`
	MessagePinnedByName string     `gorm:"column:message_pinned_by_name"`
	MessagePinnedAt     *time.Time `gorm:"column:message_pinned_at"`
	CreatedAt           time.Time  `gorm:"column:created_at"`
	UpdatedAt           time.Time  `gorm:"column:updated_at"`
	LastMessageID       *uint64    `gorm:"column:last_message_id"`
	LastSenderUserid    string     `gorm:"column:last_sender_userid"`
	LastSenderName      string     `gorm:"column:last_sender_name"`
	LastSenderAvatar    string     `gorm:"column:last_sender_avatar"`
	LastMessageType     string     `gorm:"column:last_message_type"`
	LastContent         string     `gorm:"column:last_content"`
	LastCreatedAt       *time.Time `gorm:"column:last_created_at"`
}

type memberRow struct {
	ConversationID uint64 `gorm:"column:conversation_id"`
	Userid         string `gorm:"column:userid"`
	Fullname       string `gorm:"column:fullname"`
	Nickname       string `gorm:"column:nickname"`
	Avatar         string `gorm:"column:avatar"`
	Role           string `gorm:"column:role"`
}

type messageRow struct {
	ID                     uint64    `gorm:"column:id"`
	ConversationID         uint64    `gorm:"column:conversation_id"`
	SenderUserid           string    `gorm:"column:sender_userid"`
	SenderName             string    `gorm:"column:sender_name"`
	SenderAvatar           string    `gorm:"column:sender_avatar"`
	MessageType            string    `gorm:"column:message_type"`
	Content                string    `gorm:"column:content"`
	ReplyToMessageID       *uint64   `gorm:"column:reply_to_message_id"`
	ForwardedFromMessageID *uint64   `gorm:"column:forwarded_from_message_id"`
	CreatedAt              time.Time `gorm:"column:created_at"`
}

type messageReferenceRow struct {
	ID           uint64 `gorm:"column:id"`
	SenderUserid string `gorm:"column:sender_userid"`
	SenderName   string `gorm:"column:sender_name"`
	MessageType  string `gorm:"column:message_type"`
	Content      string `gorm:"column:content"`
}

type pollVoteRow struct {
	PollID   uint64 `gorm:"column:poll_id"`
	OptionID uint64 `gorm:"column:option_id"`
	Userid   string `gorm:"column:userid"`
	Fullname string `gorm:"column:fullname"`
	Avatar   string `gorm:"column:avatar"`
}

func (s *ChatService) SearchUsers(currentUserid, keyword string) ([]types.ChatUser, error) {
	db, err := s.chatDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	keyword = strings.TrimSpace(keyword)
	if keyword == "" {
		return []types.ChatUser{}, nil
	}
	query := db.Table("users u").
		Select(`
			u.userid,
			COALESCE(u.fullname, u.userid) AS fullname,
			COALESCE(cc.nickname, '') AS nickname,
			COALESCE(u.avatar, '') AS avatar,
			CASE WHEN cc.id IS NULL THEN 0 ELSE 1 END AS is_contact
		`).
		Joins("LEFT JOIN chat_contacts cc ON cc.owner_userid = ? AND cc.contact_userid = u.userid", currentUserid).
		Where("u.userid <> ?", currentUserid).
		Limit(30).
		Order("is_contact DESC, fullname ASC")

	like := "%" + keyword + "%"
	query = query.Where("u.userid LIKE ? OR u.fullname LIKE ? OR cc.nickname LIKE ?", like, like, like)

	var users []types.ChatUser
	if err := query.Scan(&users).Error; err != nil {
		return nil, errors.New(ErrSystem)
	}
	applyUserPresence(users)
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
			COALESCE(c.nickname, '') AS nickname,
			COALESCE(u.avatar, '') AS avatar,
			1 AS is_contact
		FROM chat_contacts c
		JOIN users u ON u.userid = c.contact_userid
		WHERE c.owner_userid = ?
		ORDER BY COALESCE(NULLIF(c.nickname, ''), u.fullname, u.userid) ASC, u.userid ASC
	`, currentUserid).Scan(&contacts).Error; err != nil {
		return nil, errors.New(ErrSystem)
	}
	applyUserPresence(contacts)
	return contacts, nil
}

func (s *ChatService) Search(currentUserid, keyword, scope string) (*types.ChatSearchResults, error) {
	db, err := s.chatDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	keyword = strings.TrimSpace(keyword)
	scope = normalizeSearchScope(scope)
	results := &types.ChatSearchResults{
		Contacts: []types.ChatUser{},
		Messages: []types.ChatMessage{},
		Files:    []types.ChatMessage{},
	}
	if keyword == "" {
		return results, nil
	}

	var contactsLimit, messagesLimit, filesLimit = 25, 40, 40
	if scope == "all" {
		contactsLimit, messagesLimit, filesLimit = 8, 12, 12
	}

	if scope == "all" || scope == "contacts" {
		contacts, err := s.searchContacts(db, currentUserid, keyword, contactsLimit)
		if err != nil {
			return nil, errors.New(ErrSystem)
		}
		results.Contacts = contacts
	}

	if scope == "all" || scope == "messages" {
		messages, err := s.searchMessages(db, currentUserid, keyword, messagesLimit)
		if err != nil {
			return nil, errors.New(ErrSystem)
		}
		results.Messages = messages
	}

	if scope == "all" || scope == "files" {
		files, err := s.searchFiles(db, currentUserid, keyword, filesLimit)
		if err != nil {
			return nil, errors.New(ErrSystem)
		}
		results.Files = files
	}

	return results, nil
}

func (s *ChatService) PresenceAudience(userid string) ([]string, error) {
	db, err := s.chatDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	var userids []string
	if err := db.Raw(`
		SELECT owner_userid AS userid
		FROM chat_contacts
		WHERE contact_userid = ?
		UNION
		SELECT contact_userid AS userid
		FROM chat_contacts
		WHERE owner_userid = ?
		UNION
		SELECT cm_other.userid AS userid
		FROM chat_members cm_self
		JOIN chat_members cm_other ON cm_other.conversation_id = cm_self.conversation_id
		WHERE cm_self.userid = ? AND cm_other.userid <> ?
	`, userid, userid, userid, userid).Scan(&userids).Error; err != nil {
		return nil, errors.New(ErrSystem)
	}
	return userids, nil
}

func (s *ChatService) DirectCallRecipients(currentUserid string, conversationID uint64) ([]string, error) {
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
	if conversationType != "direct" {
		return nil, errors.New(ErrChatNoPermission)
	}

	userids, err := s.conversationMemberUserids(db, conversationID)
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	recipients := make([]string, 0, len(userids))
	for _, userid := range userids {
		if strings.TrimSpace(userid) != "" && userid != currentUserid {
			recipients = append(recipients, userid)
		}
	}
	return recipients, nil
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
	var nicknameRow struct {
		Nickname string `gorm:"column:nickname"`
	}
	if err := db.Table("chat_contacts").
		Select("COALESCE(nickname, '') AS nickname").
		Where("owner_userid = ? AND contact_userid = ?", currentUserid, contactUserid).
		Scan(&nicknameRow).Error; err != nil {
		return nil, errors.New(ErrSystem)
	}
	contact.Nickname = nicknameRow.Nickname

	contact.IsContact = true
	contact.IsOnline = RealtimeHubInstance.IsOnline(contact.Userid)
	return &contact, nil
}

func (s *ChatService) UpdateContactNickname(currentUserid, contactUserid string, req request.UpdateContactNicknameRequest) (*types.ChatUser, error) {
	db, err := s.chatDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	contactUserid = strings.TrimSpace(contactUserid)
	nickname := strings.TrimSpace(req.Nickname)
	if contactUserid == "" || contactUserid == currentUserid || len([]rune(nickname)) > 80 {
		return nil, errors.New(ErrInvalidInput)
	}

	result := db.Table("chat_contacts").
		Where("owner_userid = ? AND contact_userid = ?", currentUserid, contactUserid).
		Update("nickname", nickname)
	if result.Error != nil {
		return nil, errors.New(ErrSystem)
	}
	var contact types.ChatUser
	if err := db.Raw(`
		SELECT u.userid,
			COALESCE(u.fullname, u.userid) AS fullname,
			COALESCE(c.nickname, '') AS nickname,
			COALESCE(u.avatar, '') AS avatar,
			1 AS is_contact
		FROM chat_contacts c
		JOIN users u ON u.userid = c.contact_userid
		WHERE c.owner_userid = ? AND c.contact_userid = ?
	`, currentUserid, contactUserid).Scan(&contact).Error; err != nil {
		return nil, errors.New(ErrSystem)
	}
	if contact.Userid == "" {
		return nil, errors.New(ErrChatUserNotFound)
	}
	contact.IsOnline = RealtimeHubInstance.IsOnline(contact.Userid)
	return &contact, nil
}

func (s *ChatService) RegisterDeviceToken(currentUserid string, req request.RegisterDeviceTokenRequest) error {
	db, err := s.chatDB()
	if err != nil {
		return errors.New(ErrSystem)
	}

	token := strings.TrimSpace(req.Token)
	deviceID := strings.TrimSpace(req.DeviceID)
	if token == "" || len(token) > 512 || deviceID == "" || len(deviceID) > 128 {
		return errors.New(ErrInvalidInput)
	}

	platform := strings.ToLower(strings.TrimSpace(req.Platform))
	switch platform {
	case "android", "ios", "web":
	default:
		return errors.New(ErrInvalidInput)
	}

	// A Firebase token belongs to an app installation, not to a login session.
	// Clear every previous account association for this installation before
	// assigning the token to the account that just logged in.
	err = db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Exec(
			"DELETE FROM chat_device_tokens WHERE device_id = ? AND token <> ?",
			deviceID, token,
		).Error; err != nil {
			return err
		}
		return tx.Exec(`
		INSERT INTO chat_device_tokens (userid, token, device_id, platform, updated_at, created_at)
		VALUES (?, ?, ?, ?, ?, ?)
		ON DUPLICATE KEY UPDATE
			userid = VALUES(userid),
			device_id = VALUES(device_id),
			platform = VALUES(platform),
			updated_at = VALUES(updated_at)
	`, currentUserid, token, deviceID, platform, time.Now(), time.Now()).Error
	})
	if err != nil {
		return errors.New(ErrSystem)
	}
	return nil
}

func (s *ChatService) UnregisterDeviceToken(currentUserid string, req request.UnregisterDeviceTokenRequest) error {
	db, err := s.chatDB()
	if err != nil {
		return errors.New(ErrSystem)
	}

	deviceID := strings.TrimSpace(req.DeviceID)
	if deviceID == "" || len(deviceID) > 128 {
		return errors.New(ErrInvalidInput)
	}

	where := "userid = ? AND device_id = ?"
	args := []interface{}{currentUserid, deviceID}
	if token := strings.TrimSpace(req.Token); token != "" {
		where += " AND token = ?"
		args = append(args, token)
	}
	if err := db.Exec("DELETE FROM chat_device_tokens WHERE "+where, args...).Error; err != nil {
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
	var systemMessageID uint64
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
		if err := lockChatConversationRows(tx, newID); err != nil {
			return err
		}

		members := []map[string]interface{}{
			{"conversation_id": newID, "userid": currentUserid, "role": "member", "joined_at": now},
			{"conversation_id": newID, "userid": targetUserid, "role": "member", "joined_at": now},
		}
		if err := tx.Table("chat_members").Create(&members).Error; err != nil {
			return err
		}
		creatorName, err := s.conversationUserDisplayName(tx, newID, currentUserid)
		if err != nil {
			return err
		}
		systemMessageID, err = s.createSystemMessage(tx, newID, currentUserid, creatorName+" đã tạo nhóm", now)
		return err
	})
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	s.broadcastSystemMessageByID(db, currentUserid, newID, systemMessageID)
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
		if err := lockChatConversationRows(tx, newID); err != nil {
			return err
		}

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

func (s *ChatService) UpdateConversationSettings(currentUserid string, conversationID uint64, req request.UpdateConversationSettingsRequest) (*types.ChatConversation, error) {
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

	avatar := strings.TrimSpace(req.Avatar)
	background := strings.TrimSpace(req.Background)
	if len(avatar) > 1024 || len(background) > 1024 {
		return nil, errors.New(ErrInvalidInput)
	}
	var previous struct {
		Avatar     string `gorm:"column:avatar"`
		Background string `gorm:"column:background"`
	}
	if err := db.Table("chat_conversations").Select("avatar, background").Where("id = ?", conversationID).Take(&previous).Error; err != nil {
		return nil, errors.New(ErrSystem)
	}

	updates := map[string]interface{}{
		"background": background,
		"updated_at": time.Now(),
	}
	if conversationType == "group" {
		updates["avatar"] = avatar
	}

	if err := db.Table("chat_conversations").Where("id = ?", conversationID).Updates(updates).Error; err != nil {
		return nil, errors.New(ErrSystem)
	}
	backgroundChanged := previous.Background != background
	avatarChanged := conversationType == "group" && previous.Avatar != avatar
	if backgroundChanged || avatarChanged {
		actorName, nameErr := s.conversationUserDisplayName(db, conversationID, currentUserid)
		if nameErr == nil {
			if strings.TrimSpace(actorName) == "" {
				actorName = currentUserid
			}
			content := actorName + " đã cập nhật "
			switch {
			case backgroundChanged && avatarChanged:
				content += "ảnh nền và ảnh đại diện"
			case backgroundChanged:
				content += "ảnh nền"
			default:
				content += "ảnh đại diện"
			}
			if messageID, createErr := s.createSystemMessage(db, conversationID, currentUserid, content, time.Now()); createErr == nil {
				s.broadcastSystemMessageByID(db, currentUserid, conversationID, messageID)
			}
		}
	}

	conversation, err := s.getConversation(db, currentUserid, conversationID)
	if err != nil {
		return nil, err
	}
	audience := make([]string, 0, len(conversation.Members))
	for _, member := range conversation.Members {
		if strings.TrimSpace(member.Userid) != "" {
			audience = append(audience, member.Userid)
		}
	}
	if len(audience) > 0 {
		RealtimeHubInstance.BroadcastToUsers(audience, RealtimeEvent{
			Type:           "conversation.updated",
			ConversationID: conversationID,
			Payload: map[string]interface{}{
				"avatar":     conversation.Avatar,
				"background": conversation.Background,
			},
		})
	}
	return conversation, nil
}

func (s *ChatService) AddMembers(currentUserid string, conversationID uint64, req request.AddConversationMembersRequest) (*types.ChatConversation, error) {
	db, err := s.productionDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	userids := normalizeUserids(req.Userids)
	if len(userids) == 0 {
		return nil, errors.New(ErrInvalidInput)
	}

	if err := s.ensureUsersExist(db, userids); err != nil {
		return nil, err
	}

	var newUserids []string
	var systemMessageID uint64
	err = db.Transaction(func(tx *gorm.DB) error {
		if lockErr := lockChatConversationRows(tx, conversationID); lockErr != nil {
			return lockErr
		}
		if ok, checkErr := s.isConversationMember(tx, conversationID, currentUserid); checkErr != nil {
			return checkErr
		} else if !ok {
			return errors.New(ErrChatNoPermission)
		}
		conversationType, typeErr := s.conversationType(tx, conversationID)
		if typeErr != nil {
			return typeErr
		}
		if conversationType == "direct" {
			return errors.New(ErrChatCannotAddDirectMember)
		}
		existingUserids, existingErr := s.conversationExistingUserids(tx, conversationID, userids)
		if existingErr != nil {
			return existingErr
		}
		newUserids = subtractUserids(userids, existingUserids)
		if len(newUserids) == 0 {
			return nil
		}
		now := time.Now()
		var baseline struct {
			MessageID *uint64    `gorm:"column:message_id"`
			MessageAt *time.Time `gorm:"column:message_at"`
		}
		if err := tx.Raw("SELECT MAX(id) AS message_id, MAX(created_at) AS message_at FROM chat_messages WHERE conversation_id = ? AND message_type <> 'system'", conversationID).Scan(&baseline).Error; err != nil {
			return err
		}
		for _, userid := range newUserids {
			member := productionMemberInsertRecord{
				ConversationID: conversationID, Userid: userid, Role: "member",
				LastDeliveredMessageID: baseline.MessageID, LastReadMessageID: baseline.MessageID,
				LastReadAt: baseline.MessageAt, UnreadCount: 0, JoinedAt: now,
			}
			if member.LastReadAt == nil {
				baselineAt := coalesceTime(baseline.MessageAt, now)
				member.LastReadAt = &baselineAt
			}
			if err := tx.Table("chat_members").Clauses(clause.OnConflict{
				Columns:   []clause.Column{{Name: "conversation_id"}, {Name: "userid"}},
				DoNothing: true,
			}).Create(&member).Error; err != nil {
				return err
			}
		}
		if err := tx.Table("chat_conversations").
			Where("id = ?", conversationID).
			Update("updated_at", now).Error; err != nil {
			return err
		}
		actorName, err := s.conversationUserDisplayName(tx, conversationID, currentUserid)
		if err != nil {
			return err
		}
		addedNames, err := s.conversationUserDisplayNames(tx, conversationID, newUserids)
		if err != nil {
			return err
		}
		systemMessageID, err = s.createSystemMessage(tx, conversationID, currentUserid, actorName+" đã thêm "+strings.Join(addedNames, ", ")+" vào nhóm", now)
		return err
	})
	if err != nil {
		switch err.Error() {
		case ErrChatConversationNotFound, ErrChatNoPermission, ErrChatCannotAddDirectMember:
			return nil, err
		default:
			return nil, errors.New(ErrSystem)
		}
	}

	s.broadcastSystemMessageByID(db, currentUserid, conversationID, systemMessageID)
	return s.getConversation(db, currentUserid, conversationID)
}

func (s *ChatService) UpdateMemberNickname(currentUserid string, conversationID uint64, targetUserid string, req request.UpdateConversationMemberNicknameRequest) (*types.ChatConversation, error) {
	db, err := s.chatDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	targetUserid = strings.TrimSpace(targetUserid)
	if targetUserid == "" {
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
	if conversationType != "group" {
		return nil, errors.New(ErrInvalidInput)
	}

	if ok, err := s.isConversationMember(db, conversationID, targetUserid); err != nil {
		return nil, errors.New(ErrSystem)
	} else if !ok {
		return nil, errors.New(ErrChatMemberNotFound)
	}

	nickname := strings.TrimSpace(req.Nickname)
	if len([]rune(nickname)) > 80 {
		return nil, errors.New(ErrInvalidInput)
	}

	if err := db.Table("chat_members").
		Where("conversation_id = ? AND userid = ?", conversationID, targetUserid).
		Update("nickname", nickname).Error; err != nil {
		return nil, errors.New(ErrSystem)
	}

	return s.getConversation(db, currentUserid, conversationID)
}

func (s *ChatService) RemoveMember(currentUserid string, conversationID uint64, targetUserid string) (*types.ChatConversation, error) {
	db, err := s.productionDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	targetUserid = strings.TrimSpace(targetUserid)
	if targetUserid == "" {
		return nil, errors.New(ErrInvalidInput)
	}
	isLeaving := targetUserid == currentUserid

	var systemMessageID uint64
	err = db.Transaction(func(tx *gorm.DB) error {
		if lockErr := lockChatConversationRows(tx, conversationID); lockErr != nil {
			return lockErr
		}
		if ok, checkErr := s.isConversationMember(tx, conversationID, currentUserid); checkErr != nil {
			return checkErr
		} else if !ok {
			return errors.New(ErrChatNoPermission)
		}
		conversationType, typeErr := s.conversationType(tx, conversationID)
		if typeErr != nil {
			return typeErr
		}
		if conversationType == "direct" {
			return errors.New(ErrChatCannotRemoveDirectMember)
		}
		if !isLeaving {
			if ok, ownerErr := s.isConversationOwner(tx, conversationID, currentUserid); ownerErr != nil {
				return ownerErr
			} else if !ok {
				return errors.New(ErrChatOnlyOwnerCanManageMembers)
			}
		}
		if ok, checkErr := s.isConversationMember(tx, conversationID, targetUserid); checkErr != nil {
			return checkErr
		} else if !ok {
			return errors.New(ErrChatMemberNotFound)
		}
		actorName, nameErr := s.conversationUserDisplayName(tx, conversationID, currentUserid)
		if nameErr != nil {
			return nameErr
		}
		targetName, nameErr := s.conversationUserDisplayName(tx, conversationID, targetUserid)
		if nameErr != nil {
			return nameErr
		}
		systemContent := targetName + " đã rời nhóm"
		if !isLeaving {
			systemContent = actorName + " đã xóa " + targetName + " khỏi nhóm"
		}
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
		if err := tx.Table("chat_conversations").
			Where("id = ?", conversationID).
			Update("updated_at", now).Error; err != nil {
			return err
		}
		systemMessageID, err = s.createSystemMessage(tx, conversationID, currentUserid, systemContent, now)
		return err
	})
	if err != nil {
		switch err.Error() {
		case ErrChatConversationNotFound, ErrChatNoPermission, ErrChatCannotRemoveDirectMember, ErrChatOnlyOwnerCanManageMembers, ErrChatMemberNotFound:
			return nil, err
		default:
			return nil, errors.New(ErrSystem)
		}
	}

	s.broadcastSystemMessageByID(db, currentUserid, conversationID, systemMessageID)
	if isLeaving {
		return &types.ChatConversation{ID: conversationID}, nil
	}
	return s.getConversation(db, currentUserid, conversationID)
}

func (s *ChatService) ListMessages(currentUserid string, conversationID uint64, limit int, beforeID uint64) ([]types.ChatMessage, bool, error) {
	db, err := s.productionDB()
	if err != nil {
		return nil, false, errors.New(ErrSystem)
	}

	if ok, err := s.isConversationMember(db, conversationID, currentUserid); err != nil {
		return nil, false, errors.New(ErrSystem)
	} else if !ok {
		return nil, false, errors.New(ErrChatNoPermission)
	}

	if limit <= 0 {
		limit = defaultMessagePageSize
	}
	if limit > maxMessagePageSize {
		limit = maxMessagePageSize
	}

	var rows []messageRow
	query := `
		SELECT m.id, m.conversation_id, m.sender_userid,
			CASE
				WHEN c.type = 'direct' THEN COALESCE(NULLIF(cc_sender.nickname, ''), u.fullname, m.sender_userid)
				ELSE COALESCE(NULLIF(cm_sender.nickname, ''), u.fullname, m.sender_userid)
			END AS sender_name,
			COALESCE(u.avatar, '') AS sender_avatar,
			m.message_type, COALESCE(m.content, '') AS content,
			m.reply_to_message_id, m.forwarded_from_message_id, m.created_at
		FROM chat_messages m
		JOIN chat_conversations c ON c.id = m.conversation_id
		LEFT JOIN chat_members cm_sender ON cm_sender.conversation_id = m.conversation_id AND cm_sender.userid = m.sender_userid
		LEFT JOIN chat_contacts cc_sender ON cc_sender.owner_userid = ? AND cc_sender.contact_userid = m.sender_userid
		LEFT JOIN users u ON u.userid = m.sender_userid
		WHERE m.conversation_id = ?
			AND NOT EXISTS (SELECT 1 FROM chat_message_user_deletions d WHERE d.message_id = m.id AND d.userid = ?)
	`
	args := []interface{}{currentUserid, conversationID, currentUserid}
	if beforeID > 0 {
		query += " AND m.id < ?"
		args = append(args, beforeID)
	}
	query += " ORDER BY m.id DESC LIMIT ?"
	args = append(args, limit+1)

	if err := db.Raw(query, args...).Scan(&rows).Error; err != nil {
		return nil, false, errors.New(ErrSystem)
	}

	hasMore := len(rows) > limit
	if hasMore {
		rows = rows[:limit]
	}

	for i, j := 0, len(rows)-1; i < j; i, j = i+1, j-1 {
		rows[i], rows[j] = rows[j], rows[i]
	}

	messages, err := s.buildMessages(db, currentUserid, rows)
	return messages, hasMore, err
}

func (s *ChatService) sendMessageLegacy(currentUserid string, conversationID uint64, req request.SendChatMessageRequest) (*types.ChatMessage, error) {
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
	if (messageType == "text" || messageType == "link" || messageType == "call") && content == "" {
		return nil, errors.New(ErrChatEmptyMessage)
	}
	if (messageType == "file" || messageType == "folder" || messageType == "voice") && len(req.Attachments) == 0 {
		return nil, errors.New(ErrChatEmptyMessage)
	}

	var replyToMessageID *uint64
	if req.ReplyToMessageID > 0 {
		if ok, err := s.messageInConversation(db, currentUserid, conversationID, req.ReplyToMessageID); err != nil {
			return nil, errors.New(ErrSystem)
		} else if !ok {
			return nil, errors.New(ErrChatNoPermission)
		}
		replyToMessageID = &req.ReplyToMessageID
	}

	var forwardedFromMessageID *uint64
	if req.ForwardedFromMessageID > 0 {
		if ok, err := s.canAccessMessage(db, currentUserid, req.ForwardedFromMessageID); err != nil {
			return nil, errors.New(ErrSystem)
		} else if !ok {
			return nil, errors.New(ErrChatNoPermission)
		}
		forwardedFromMessageID = &req.ForwardedFromMessageID
	}

	var messageID uint64
	err = db.Transaction(func(tx *gorm.DB) error {
		now := time.Now()
		message := chatMessageRecord{
			ConversationID:         conversationID,
			SenderUserid:           currentUserid,
			MessageType:            messageType,
			Content:                content,
			ReplyToMessageID:       replyToMessageID,
			ForwardedFromMessageID: forwardedFromMessageID,
			CreatedAt:              now,
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

	message, err := s.loadMessageByID(db, currentUserid, messageID)
	if err != nil {
		return nil, err
	}
	s.broadcastMessageCreated(db, conversationID, message)
	go PushServiceInstance.SendChatMessageNotification(db, currentUserid, conversationID, message.ID, message.Type, message.Content)
	return message, nil
}

func (s *ChatService) CreatePoll(currentUserid string, conversationID uint64, req request.CreatePollRequest) (*types.ChatMessage, error) {
	db, err := s.productionDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	question := strings.TrimSpace(req.Question)
	options, err := normalizePollOptions(req.Options)
	if err != nil {
		return nil, err
	}
	if question == "" || len([]rune(question)) > maxPollQuestionLength || len(options) < minPollOptions {
		return nil, errors.New(ErrChatInvalidPoll)
	}

	var systemMessageID uint64
	var messageID uint64
	err = db.Transaction(func(tx *gorm.DB) error {
		if lockErr := lockChatConversationRows(tx, conversationID); lockErr != nil {
			return lockErr
		}
		if ok, checkErr := s.isConversationMember(tx, conversationID, currentUserid); checkErr != nil {
			return checkErr
		} else if !ok {
			return errors.New(ErrChatNoPermission)
		}
		conversationType, typeErr := s.conversationType(tx, conversationID)
		if typeErr != nil {
			return typeErr
		}
		if conversationType != "group" {
			return errors.New(ErrChatNoPermission)
		}
		now := time.Now()
		actorName, err := s.conversationUserDisplayName(tx, conversationID, currentUserid)
		if err != nil {
			return err
		}
		systemMessageID, err = s.createSystemMessage(tx, conversationID, currentUserid, actorName+" đã tạo bình chọn", now)
		if err != nil {
			return err
		}

		message := chatMessageRecord{
			ConversationID: conversationID,
			SenderUserid:   currentUserid,
			MessageType:    "poll",
			Content:        question,
			CreatedAt:      now,
		}
		if err := tx.Table("chat_messages").Create(&message).Error; err != nil {
			return err
		}
		messageID = message.ID

		poll := chatPollRecord{
			MessageID:          messageID,
			ConversationID:     conversationID,
			Question:           question,
			AllowCustomOptions: req.AllowCustomOptions,
			AllowMultiple:      req.AllowMultiple,
			ShowVoters:         req.ShowVoters,
			CreatedBy:          currentUserid,
			CreatedAt:          now,
			UpdatedAt:          now,
		}
		if err := tx.Table("chat_polls").Create(&poll).Error; err != nil {
			return err
		}

		for _, optionText := range options {
			option := chatPollOptionRecord{
				PollID:    poll.ID,
				Text:      optionText,
				CreatedBy: currentUserid,
				IsCustom:  false,
				CreatedAt: now,
			}
			if err := tx.Table("chat_poll_options").Create(&option).Error; err != nil {
				return err
			}
		}
		if err := tx.Table("chat_messages").Where("id = ?", messageID).Update("server_sequence", messageID).Error; err != nil {
			return err
		}
		if err := tx.Table("chat_members").Where("conversation_id = ? AND userid <> ?", conversationID, currentUserid).UpdateColumn("unread_count", gorm.Expr("unread_count + 1")).Error; err != nil {
			return err
		}
		var recipientUserids []string
		if err := tx.Table("chat_members").Where("conversation_id = ? AND userid <> ?", conversationID, currentUserid).Pluck("userid", &recipientUserids).Error; err != nil {
			return err
		}
		if len(recipientUserids) > 0 {
			receipts := make([]productionReceiptRecord, 0, len(recipientUserids))
			for _, userid := range recipientUserids {
				receipts = append(receipts, productionReceiptRecord{MessageID: messageID, ConversationID: conversationID, Userid: userid, CreatedAt: now, UpdatedAt: now})
			}
			if err := tx.Table("chat_message_receipts").CreateInBatches(receipts, 500).Error; err != nil {
				return err
			}
		}

		return tx.Table("chat_conversations").
			Where("id = ?", conversationID).
			Update("updated_at", now).Error
	})
	if err != nil {
		switch err.Error() {
		case ErrChatConversationNotFound, ErrChatNoPermission:
			return nil, err
		default:
			return nil, errors.New(ErrSystem)
		}
	}

	systemMessage, err := s.loadMessageByID(db, currentUserid, systemMessageID)
	if err != nil {
		return nil, err
	}
	message, err := s.loadMessageByID(db, currentUserid, messageID)
	if err != nil {
		return nil, err
	}
	s.broadcastMessageCreated(db, conversationID, systemMessage)
	s.broadcastMessageCreated(db, conversationID, message)
	if chatDBOverride == nil {
		go PushServiceInstance.SendChatMessageNotification(db, currentUserid, conversationID, message.ID, message.Type, message.Content)
	}
	return message, nil
}

func (s *ChatService) VotePoll(currentUserid string, messageID uint64, req request.VotePollRequest) (*types.ChatMessage, error) {
	db, err := s.chatDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	var poll chatPollRecord
	if err := db.Table("chat_polls").Where("message_id = ?", messageID).Take(&poll).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New(ErrChatPollNotFound)
		}
		return nil, errors.New(ErrSystem)
	}

	if ok, err := s.isConversationMember(db, poll.ConversationID, currentUserid); err != nil {
		return nil, errors.New(ErrSystem)
	} else if !ok {
		return nil, errors.New(ErrChatNoPermission)
	}
	if active, activeErr := s.isMessageActive(db, messageID); activeErr != nil {
		return nil, errors.New(ErrSystem)
	} else if !active {
		return nil, errors.New(ErrChatNoPermission)
	}
	if poll.IsClosed {
		return nil, errors.New(ErrChatPollClosed)
	}

	optionIDs := normalizeUintIDs(req.OptionIDs)
	customOption := strings.TrimSpace(req.CustomOption)
	if customOption != "" {
		if !poll.AllowCustomOptions {
			return nil, errors.New(ErrChatPollCustomOptionsDisabled)
		}
		if len([]rune(customOption)) > maxPollOptionLength {
			return nil, errors.New(ErrChatInvalidPoll)
		}
	}
	if len(optionIDs) > maxPollOptions || (!poll.AllowMultiple && len(optionIDs)+boolInt(customOption != "") > 1) {
		return nil, errors.New(ErrChatInvalidPoll)
	}

	if len(optionIDs) > 0 {
		var foundOptionIDs []uint64
		if err := db.Table("chat_poll_options").
			Where("poll_id = ? AND id IN ?", poll.ID, optionIDs).
			Pluck("id", &foundOptionIDs).Error; err != nil {
			return nil, errors.New(ErrSystem)
		}
		if len(foundOptionIDs) != len(optionIDs) {
			return nil, errors.New(ErrChatInvalidPoll)
		}
	}

	previousOptionIDs, err := s.pollUserOptionIDs(db, poll.ID, currentUserid)
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	var systemMessageID uint64
	err = db.Transaction(func(tx *gorm.DB) error {
		selectedOptionIDs := append([]uint64{}, optionIDs...)
		if customOption != "" {
			customOptionID, err := s.findOrCreatePollOption(tx, poll.ID, currentUserid, customOption)
			if err != nil {
				return err
			}
			selectedOptionIDs = append(selectedOptionIDs, customOptionID)
			selectedOptionIDs = normalizeUintIDs(selectedOptionIDs)
		}
		if !poll.AllowMultiple && len(selectedOptionIDs) > 1 {
			return errors.New(ErrChatInvalidPoll)
		}
		voteAction := pollVoteAction(previousOptionIDs, selectedOptionIDs)
		now := time.Now()

		if err := tx.Table("chat_poll_votes").
			Where("poll_id = ? AND userid = ?", poll.ID, currentUserid).
			Delete(&chatPollVoteRecord{}).Error; err != nil {
			return err
		}

		for _, optionID := range selectedOptionIDs {
			vote := chatPollVoteRecord{
				PollID:    poll.ID,
				OptionID:  optionID,
				Userid:    currentUserid,
				CreatedAt: now,
			}
			if err := tx.Table("chat_poll_votes").Create(&vote).Error; err != nil {
				return err
			}
		}
		if err := tx.Table("chat_polls").
			Where("id = ?", poll.ID).
			Update("updated_at", now).Error; err != nil {
			return err
		}
		if voteAction != "" {
			actorName, err := s.conversationUserDisplayName(tx, poll.ConversationID, currentUserid)
			if err != nil {
				return err
			}
			systemMessageID, err = s.createSystemMessage(tx, poll.ConversationID, currentUserid, actorName+" "+voteAction+" bình chọn \""+shortPollQuestion(poll.Question)+"\"", now)
			if err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		if err.Error() == ErrChatInvalidPoll {
			return nil, err
		}
		return nil, errors.New(ErrSystem)
	}

	message, err := s.loadMessageByID(db, currentUserid, messageID)
	if err != nil {
		return nil, err
	}
	s.broadcastPollUpdated(db, poll.ConversationID, message)
	s.broadcastSystemMessageByID(db, currentUserid, poll.ConversationID, systemMessageID)
	return message, nil
}

func (s *ChatService) ClosePoll(currentUserid string, messageID uint64) (*types.ChatMessage, error) {
	db, err := s.chatDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	var poll chatPollRecord
	if err := db.Table("chat_polls").Where("message_id = ?", messageID).Take(&poll).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New(ErrChatPollNotFound)
		}
		return nil, errors.New(ErrSystem)
	}
	if ok, err := s.isConversationMember(db, poll.ConversationID, currentUserid); err != nil {
		return nil, errors.New(ErrSystem)
	} else if !ok {
		return nil, errors.New(ErrChatNoPermission)
	}
	if active, activeErr := s.isMessageActive(db, messageID); activeErr != nil {
		return nil, errors.New(ErrSystem)
	} else if !active {
		return nil, errors.New(ErrChatNoPermission)
	}
	if poll.CreatedBy != currentUserid {
		return nil, errors.New(ErrChatNoPermission)
	}

	var systemMessageID uint64
	if !poll.IsClosed {
		err = db.Transaction(func(tx *gorm.DB) error {
			now := time.Now()
			if err := tx.Table("chat_polls").
				Where("id = ?", poll.ID).
				Updates(map[string]interface{}{
					"is_closed":  true,
					"closed_by":  currentUserid,
					"closed_at":  now,
					"updated_at": now,
				}).Error; err != nil {
				return err
			}
			actorName, err := s.conversationUserDisplayName(tx, poll.ConversationID, currentUserid)
			if err != nil {
				return err
			}
			systemMessageID, err = s.createSystemMessage(tx, poll.ConversationID, currentUserid, actorName+" đã đóng bình chọn \""+shortPollQuestion(poll.Question)+"\"", now)
			return err
		})
		if err != nil {
			return nil, errors.New(ErrSystem)
		}
	}

	message, err := s.loadMessageByID(db, currentUserid, messageID)
	if err != nil {
		return nil, err
	}
	s.broadcastPollUpdated(db, message.ConversationID, message)
	s.broadcastSystemMessageByID(db, currentUserid, message.ConversationID, systemMessageID)
	return message, nil
}

func (s *ChatService) broadcastMessageCreated(db *gorm.DB, conversationID uint64, message *types.ChatMessage) {
	userids, err := s.conversationMemberUserids(db, conversationID)
	if err != nil || len(userids) == 0 {
		return
	}

	for _, userid := range userids {
		personalized, loadErr := s.loadMessageByID(db, userid, message.ID)
		if loadErr != nil {
			continue
		}
		RealtimeHubInstance.BroadcastToUsers([]string{userid}, RealtimeEvent{
			Type: "chat.message.created", ConversationID: conversationID, Message: personalized,
			Payload: map[string]interface{}{"message": personalized}, SentAt: time.Now(),
		})
	}
}

func (s *ChatService) broadcastPollUpdated(db *gorm.DB, conversationID uint64, message *types.ChatMessage) {
	userids, err := s.conversationMemberUserids(db, conversationID)
	if err != nil || len(userids) == 0 {
		return
	}

	for _, userid := range userids {
		messageForUser, err := s.loadMessageByID(db, userid, message.ID)
		if err != nil {
			continue
		}
		RealtimeHubInstance.BroadcastToUsers([]string{userid}, RealtimeEvent{
			Type:           "chat.poll.updated",
			ConversationID: conversationID,
			Message:        messageForUser,
			SentAt:         time.Now(),
		})
	}
}

func (s *ChatService) broadcastSystemMessageByID(db *gorm.DB, currentUserid string, conversationID uint64, messageID uint64) {
	if messageID == 0 {
		return
	}
	message, err := s.loadMessageByID(db, currentUserid, messageID)
	if err != nil {
		return
	}
	s.broadcastMessageCreated(db, conversationID, message)
}

func (s *ChatService) createSystemMessage(db *gorm.DB, conversationID uint64, senderUserid string, content string, createdAt time.Time) (uint64, error) {
	message := chatMessageRecord{
		ConversationID: conversationID,
		SenderUserid:   senderUserid,
		MessageType:    "system",
		Content:        strings.TrimSpace(content),
		CreatedAt:      createdAt,
	}
	if message.Content == "" {
		return 0, nil
	}
	if err := db.Table("chat_messages").Create(&message).Error; err != nil {
		return 0, err
	}
	if err := db.Table("chat_messages").Where("id = ?", message.ID).Update("server_sequence", message.ID).Error; err != nil {
		return 0, err
	}
	return message.ID, nil
}

func (s *ChatService) chatDB() (*gorm.DB, error) {
	if chatDBOverride != nil {
		return chatDBOverride, nil
	}
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
	if chatSchemaReady.Load() {
		return nil
	}

	chatSchemaMu.Lock()
	defer chatSchemaMu.Unlock()

	if chatSchemaReady.Load() {
		return nil
	}

	statements := []string{
		`CREATE TABLE IF NOT EXISTS chat_schema_migrations (
			version VARCHAR(64) NOT NULL,
			applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			PRIMARY KEY (version)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
		`CREATE TABLE IF NOT EXISTS chat_conversations (
			id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			type VARCHAR(20) NOT NULL,
			name VARCHAR(160) NULL,
			avatar VARCHAR(255) NULL,
			background VARCHAR(1024) NULL,
			pinned_message_id BIGINT UNSIGNED NULL,
			message_pinned_by VARCHAR(64) NULL,
			message_pinned_at DATETIME NULL,
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
			nickname VARCHAR(80) NULL,
			joined_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			PRIMARY KEY (id),
			UNIQUE KEY uk_chat_members_conversation_user (conversation_id, userid),
			INDEX idx_chat_members_userid (userid),
			INDEX idx_chat_members_conversation (conversation_id)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
		`CREATE TABLE IF NOT EXISTS chat_pinned_messages (
			id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			conversation_id BIGINT UNSIGNED NOT NULL,
			message_id BIGINT UNSIGNED NOT NULL,
			pinned_by VARCHAR(64) NOT NULL,
			pinned_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			PRIMARY KEY (id),
			UNIQUE KEY uk_chat_pinned_messages_conversation_message (conversation_id, message_id),
			INDEX idx_chat_pinned_messages_conversation_time (conversation_id, pinned_at, id)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
		`CREATE TABLE IF NOT EXISTS chat_reminders (
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
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
		`CREATE TABLE IF NOT EXISTS chat_contacts (
			id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			owner_userid VARCHAR(64) NOT NULL,
			contact_userid VARCHAR(64) NOT NULL,
			nickname VARCHAR(80) NULL,
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
			device_id VARCHAR(128) NOT NULL DEFAULT '',
			platform VARCHAR(32) NOT NULL DEFAULT 'unknown',
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
			PRIMARY KEY (id),
			UNIQUE KEY uk_chat_device_tokens_token (token),
			INDEX idx_chat_device_tokens_userid (userid)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
		`CREATE TABLE IF NOT EXISTS chat_calls (
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
			INDEX idx_chat_calls_conversation_started (conversation_id, started_at),
			INDEX idx_chat_calls_caller_started (caller_userid, started_at),
			INDEX idx_chat_calls_callee_started (callee_userid, started_at),
			INDEX idx_chat_calls_status_started (status, started_at)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
		`CREATE TABLE IF NOT EXISTS chat_messages (
			id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			conversation_id BIGINT UNSIGNED NOT NULL,
			sender_userid VARCHAR(64) NOT NULL,
			message_type VARCHAR(20) NOT NULL,
			content TEXT NULL,
			reply_to_message_id BIGINT UNSIGNED NULL,
			forwarded_from_message_id BIGINT UNSIGNED NULL,
			client_message_id CHAR(36) NULL,
			server_sequence BIGINT UNSIGNED NULL,
			version INT UNSIGNED NOT NULL DEFAULT 1,
			edited_at DATETIME NULL,
			deleted_at DATETIME NULL,
			deleted_by VARCHAR(64) NULL,
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			PRIMARY KEY (id),
			UNIQUE KEY uk_chat_messages_sender_client (sender_userid, client_message_id),
			UNIQUE KEY uk_chat_messages_conversation_sequence (conversation_id, server_sequence),
			INDEX idx_chat_messages_conversation_created (conversation_id, created_at),
			INDEX idx_chat_messages_conversation_sender_created (conversation_id, sender_userid, created_at),
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
		`CREATE TABLE IF NOT EXISTS chat_pending_uploads (
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
			INDEX idx_chat_pending_uploads_user_claimed (userid, claimed_message_id)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
		`CREATE TABLE IF NOT EXISTS chat_polls (
			id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			message_id BIGINT UNSIGNED NOT NULL,
			conversation_id BIGINT UNSIGNED NOT NULL,
			question VARCHAR(500) NOT NULL,
			allow_custom_options TINYINT(1) NOT NULL DEFAULT 0,
			allow_multiple TINYINT(1) NOT NULL DEFAULT 0,
			show_voters TINYINT(1) NOT NULL DEFAULT 1,
			is_closed TINYINT(1) NOT NULL DEFAULT 0,
			closed_by VARCHAR(64) NULL,
			closed_at DATETIME NULL,
			created_by VARCHAR(64) NOT NULL,
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
			PRIMARY KEY (id),
			UNIQUE KEY uk_chat_polls_message (message_id),
			INDEX idx_chat_polls_conversation (conversation_id),
			INDEX idx_chat_polls_created_by (created_by)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
		`CREATE TABLE IF NOT EXISTS chat_poll_options (
			id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			poll_id BIGINT UNSIGNED NOT NULL,
			option_text VARCHAR(160) NOT NULL,
			created_by VARCHAR(64) NOT NULL,
			is_custom TINYINT(1) NOT NULL DEFAULT 0,
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			PRIMARY KEY (id),
			INDEX idx_chat_poll_options_poll (poll_id),
			INDEX idx_chat_poll_options_created_by (created_by)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
		`CREATE TABLE IF NOT EXISTS chat_poll_votes (
			id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			poll_id BIGINT UNSIGNED NOT NULL,
			option_id BIGINT UNSIGNED NOT NULL,
			userid VARCHAR(64) NOT NULL,
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			PRIMARY KEY (id),
			UNIQUE KEY uk_chat_poll_votes_user_option (poll_id, option_id, userid),
			INDEX idx_chat_poll_votes_poll_user (poll_id, userid),
			INDEX idx_chat_poll_votes_option (option_id)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
		`CREATE TABLE IF NOT EXISTS chat_message_receipts (
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
			INDEX idx_chat_message_receipts_conversation_user_message (conversation_id, userid, message_id),
			INDEX idx_chat_message_receipts_message_state (message_id, read_at, delivered_at)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
		`CREATE TABLE IF NOT EXISTS chat_message_user_deletions (
			id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			message_id BIGINT UNSIGNED NOT NULL,
			conversation_id BIGINT UNSIGNED NOT NULL,
			userid VARCHAR(64) NOT NULL,
			deleted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			PRIMARY KEY (id),
			UNIQUE KEY uk_chat_message_user_deletions_message_user (message_id, userid),
			INDEX idx_chat_message_user_deletions_user_conversation_message (userid, conversation_id, message_id)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
		`CREATE TABLE IF NOT EXISTS chat_message_reactions (
			id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			message_id BIGINT UNSIGNED NOT NULL,
			conversation_id BIGINT UNSIGNED NOT NULL,
			userid VARCHAR(64) NOT NULL,
			emoji VARCHAR(64) NOT NULL,
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
			PRIMARY KEY (id),
			UNIQUE KEY uk_chat_message_reactions_user_message_emoji (userid, message_id, emoji),
			INDEX idx_chat_message_reactions_message_emoji (message_id, emoji)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
		`CREATE TABLE IF NOT EXISTS chat_message_audit (
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
			INDEX idx_chat_message_audit_message_created (message_id, created_at),
			INDEX idx_chat_message_audit_actor_created (actor_userid, created_at)
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`,
	}

	for _, statement := range statements {
		if err := db.Exec(statement).Error; err != nil {
			return err
		}
	}
	if err := db.Exec(`INSERT IGNORE INTO chat_pinned_messages (conversation_id, message_id, pinned_by, pinned_at)
		SELECT id, pinned_message_id, COALESCE(message_pinned_by, created_by), COALESCE(message_pinned_at, updated_at)
		FROM chat_conversations WHERE pinned_message_id IS NOT NULL`).Error; err != nil {
		return err
	}

	if err := ensureColumn(db, "chat_members", "nickname", "VARCHAR(80) NULL AFTER role"); err != nil {
		return err
	}
	if err := ensureColumn(db, "chat_contacts", "nickname", "VARCHAR(80) NULL AFTER contact_userid"); err != nil {
		return err
	}
	if err := ensureColumn(db, "chat_conversations", "background", "VARCHAR(1024) NULL AFTER avatar"); err != nil {
		return err
	}
	conversationColumns := []struct{ name, definition string }{
		{"pinned_message_id", "BIGINT UNSIGNED NULL AFTER background"},
		{"message_pinned_by", "VARCHAR(64) NULL AFTER pinned_message_id"},
		{"message_pinned_at", "DATETIME NULL AFTER message_pinned_by"},
	}
	for _, column := range conversationColumns {
		if err := ensureColumn(db, "chat_conversations", column.name, column.definition); err != nil {
			return err
		}
	}
	if err := ensureColumn(db, "chat_messages", "reply_to_message_id", "BIGINT UNSIGNED NULL AFTER content"); err != nil {
		return err
	}
	if err := ensureColumn(db, "chat_messages", "forwarded_from_message_id", "BIGINT UNSIGNED NULL AFTER reply_to_message_id"); err != nil {
		return err
	}
	messageColumns := []struct{ name, definition string }{
		{"client_message_id", "CHAR(36) NULL AFTER forwarded_from_message_id"},
		{"server_sequence", "BIGINT UNSIGNED NULL AFTER client_message_id"},
		{"version", "INT UNSIGNED NOT NULL DEFAULT 1 AFTER server_sequence"},
		{"edited_at", "DATETIME NULL AFTER version"},
		{"deleted_at", "DATETIME NULL AFTER edited_at"},
		{"deleted_by", "VARCHAR(64) NULL AFTER deleted_at"},
	}
	for _, column := range messageColumns {
		if err := ensureColumn(db, "chat_messages", column.name, column.definition); err != nil {
			return err
		}
	}
	memberColumns := []struct{ name, definition string }{
		{"last_delivered_message_id", "BIGINT UNSIGNED NULL AFTER nickname"},
		{"last_read_message_id", "BIGINT UNSIGNED NULL AFTER last_delivered_message_id"},
		{"last_read_at", "DATETIME NULL AFTER last_read_message_id"},
		{"unread_count", "INT UNSIGNED NOT NULL DEFAULT 0 AFTER last_read_at"},
		{"mute_until", "DATETIME NULL AFTER unread_count"},
		{"pinned_at", "DATETIME NULL AFTER mute_until"},
		{"archived_at", "DATETIME NULL AFTER pinned_at"},
	}
	for _, column := range memberColumns {
		if err := ensureColumn(db, "chat_members", column.name, column.definition); err != nil {
			return err
		}
	}
	if err := ensureColumn(db, "chat_message_attachments", "deleted_at", "DATETIME NULL AFTER relative_path"); err != nil {
		return err
	}
	if err := ensureColumn(db, "chat_message_attachments", "deleted_by", "VARCHAR(64) NULL AFTER deleted_at"); err != nil {
		return err
	}
	if err := ensureColumn(db, "chat_pending_uploads", "relative_path", "VARCHAR(1024) NULL AFTER mime_type"); err != nil {
		return err
	}
	if err := ensureColumn(db, "chat_device_tokens", "device_id", "VARCHAR(128) NOT NULL DEFAULT '' AFTER token"); err != nil {
		return err
	}
	if err := ensureColumn(db, "chat_reminders", "repeat_type", "VARCHAR(16) NOT NULL DEFAULT 'none' AFTER remind_at"); err != nil {
		return err
	}
	if err := ensureColumn(db, "chat_polls", "is_closed", "TINYINT(1) NOT NULL DEFAULT 0 AFTER show_voters"); err != nil {
		return err
	}
	if err := ensureColumn(db, "chat_polls", "closed_by", "VARCHAR(64) NULL AFTER is_closed"); err != nil {
		return err
	}
	if err := ensureColumn(db, "chat_polls", "closed_at", "DATETIME NULL AFTER closed_by"); err != nil {
		return err
	}
	if err := ensureColumn(db, "chat_polls", "updated_at", "DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER created_at"); err != nil {
		return err
	}
	sequenceIndexExists, err := hasIndex(db, "chat_messages", "uk_chat_messages_conversation_sequence")
	if err != nil {
		return err
	}
	if !sequenceIndexExists {
		if err := db.Exec("UPDATE chat_messages SET server_sequence = id WHERE server_sequence IS NULL OR server_sequence = 0").Error; err != nil {
			return err
		}
	}
	indexes := []struct{ table, name, definition string }{
		{"chat_messages", "uk_chat_messages_sender_client", "UNIQUE KEY uk_chat_messages_sender_client (sender_userid, client_message_id)"},
		{"chat_messages", "uk_chat_messages_conversation_sequence", "UNIQUE KEY uk_chat_messages_conversation_sequence (conversation_id, server_sequence)"},
		{"chat_messages", "idx_chat_messages_conversation_sender_created", "KEY idx_chat_messages_conversation_sender_created (conversation_id, sender_userid, created_at)"},
		{"chat_messages", "idx_chat_messages_conversation_id", "KEY idx_chat_messages_conversation_id (conversation_id, id)"},
		{"chat_messages", "idx_chat_messages_conversation_created_id", "KEY idx_chat_messages_conversation_created_id (conversation_id, created_at, id)"},
		{"chat_messages", "idx_chat_messages_conversation_sender_id", "KEY idx_chat_messages_conversation_sender_id (conversation_id, sender_userid, id)"},
		{"chat_members", "idx_chat_members_user_settings", "KEY idx_chat_members_user_settings (userid, archived_at, pinned_at)"},
		{"chat_members", "idx_chat_members_conversation_read", "KEY idx_chat_members_conversation_read (conversation_id, last_read_message_id)"},
		{"chat_messages", "ft_chat_messages_content", "FULLTEXT KEY ft_chat_messages_content (content)"},
		{"chat_message_attachments", "ft_chat_attachments_name_path", "FULLTEXT KEY ft_chat_attachments_name_path (file_name, relative_path)"},
		{"chat_message_attachments", "idx_chat_attachments_file_url_deleted", "KEY idx_chat_attachments_file_url_deleted (file_url(191), deleted_at)"},
		{"chat_message_attachments", "idx_chat_attachments_mime_deleted_message", "KEY idx_chat_attachments_mime_deleted_message (mime_type, deleted_at, message_id)"},
	}
	for _, index := range indexes {
		if err := ensureIndex(db, index.table, index.name, index.definition); err != nil {
			return err
		}
	}
	if err := runChatProductionBackfill(db); err != nil {
		return err
	}

	chatSchemaReady.Store(true)
	return nil
}

func runChatProductionBackfill(db *gorm.DB) error {
	const version = "20260715_001_chat_production_features"
	var applied int64
	if err := db.Table("chat_schema_migrations").Where("version = ?", version).Count(&applied).Error; err != nil {
		return err
	}
	if applied > 0 {
		return nil
	}
	return db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Exec(`
			INSERT IGNORE INTO chat_message_receipts
				(message_id, conversation_id, userid, delivered_at, read_at, created_at, updated_at)
			SELECT m.id, m.conversation_id, cm.userid, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, m.created_at, CURRENT_TIMESTAMP
			FROM chat_messages m
			JOIN chat_members cm ON cm.conversation_id = m.conversation_id
				AND cm.userid <> m.sender_userid
				AND m.created_at >= cm.joined_at
			WHERE m.message_type <> 'system'
		`).Error; err != nil {
			return err
		}
		if err := tx.Exec(`
			UPDATE chat_members cm
			LEFT JOIN (
				SELECT conversation_id, MAX(id) AS last_message_id, MAX(created_at) AS last_message_at
				FROM chat_messages
				WHERE message_type <> 'system'
				GROUP BY conversation_id
			) legacy ON legacy.conversation_id = cm.conversation_id
			SET cm.last_delivered_message_id = legacy.last_message_id,
				cm.last_read_message_id = legacy.last_message_id,
				cm.last_read_at = COALESCE(legacy.last_message_at, cm.joined_at, CURRENT_TIMESTAMP),
				cm.unread_count = 0
			WHERE cm.last_read_message_id IS NULL
		`).Error; err != nil {
			return err
		}
		return tx.Exec("INSERT INTO chat_schema_migrations (version, applied_at) VALUES (?, ?)", version, time.Now().UTC()).Error
	})
}

func ensureIndex(db *gorm.DB, tableName, indexName, definition string) error {
	exists, err := hasIndex(db, tableName, indexName)
	if err != nil {
		return err
	}
	if !exists {
		return db.Exec("ALTER TABLE " + tableName + " ADD " + definition).Error
	}
	return nil
}

func hasIndex(db *gorm.DB, tableName, indexName string) (bool, error) {
	var count int64
	if err := db.Raw(`SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND INDEX_NAME = ?`, tableName, indexName).Scan(&count).Error; err != nil {
		return false, err
	}
	return count > 0, nil
}

func ensureColumn(db *gorm.DB, tableName, columnName, definition string) error {
	var columnCount int64
	if err := db.Raw(`
		SELECT COUNT(*)
		FROM INFORMATION_SCHEMA.COLUMNS
		WHERE TABLE_SCHEMA = DATABASE()
			AND TABLE_NAME = ?
			AND COLUMN_NAME = ?
	`, tableName, columnName).Scan(&columnCount).Error; err != nil {
		return err
	}
	if columnCount == 0 {
		if err := db.Exec("ALTER TABLE " + tableName + " ADD COLUMN " + columnName + " " + definition).Error; err != nil {
			return err
		}
	}
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

func (s *ChatService) conversationExistingUserids(db *gorm.DB, conversationID uint64, userids []string) ([]string, error) {
	if len(userids) == 0 {
		return []string{}, nil
	}
	var existing []string
	err := db.Table("chat_members").
		Where("conversation_id = ? AND userid IN ?", conversationID, userids).
		Pluck("userid", &existing).Error
	return existing, err
}

func (s *ChatService) conversationUserDisplayName(db *gorm.DB, conversationID uint64, userid string) (string, error) {
	userid = strings.TrimSpace(userid)
	if userid == "" {
		return "", nil
	}

	var row struct {
		Name string `gorm:"column:name"`
	}
	err := db.Raw(`
		SELECT COALESCE(NULLIF(cm.nickname, ''), u.fullname, cm.userid) AS name
		FROM chat_members cm
		LEFT JOIN users u ON u.userid = cm.userid
		WHERE cm.conversation_id = ? AND cm.userid = ?
		LIMIT 1
	`, conversationID, userid).Scan(&row).Error
	if err != nil {
		return "", err
	}
	if strings.TrimSpace(row.Name) != "" {
		return strings.TrimSpace(row.Name), nil
	}
	return s.userDisplayName(db, userid)
}

func (s *ChatService) conversationUserDisplayNames(db *gorm.DB, conversationID uint64, userids []string) ([]string, error) {
	result := make([]string, 0, len(userids))
	for _, userid := range userids {
		name, err := s.conversationUserDisplayName(db, conversationID, userid)
		if err != nil {
			return nil, err
		}
		if name == "" {
			name = userid
		}
		result = append(result, name)
	}
	return result, nil
}

func (s *ChatService) userDisplayName(db *gorm.DB, userid string) (string, error) {
	var row struct {
		Name string `gorm:"column:name"`
	}
	err := db.Raw(`
		SELECT COALESCE(NULLIF(fullname, ''), userid) AS name
		FROM users
		WHERE userid = ?
		LIMIT 1
	`, userid).Scan(&row).Error
	if err != nil {
		return "", err
	}
	if strings.TrimSpace(row.Name) != "" {
		return strings.TrimSpace(row.Name), nil
	}
	return userid, nil
}

func (s *ChatService) messageInConversation(db *gorm.DB, userid string, conversationID uint64, messageID uint64) (bool, error) {
	var count int64
	err := db.Table("chat_messages").
		Where("id = ? AND conversation_id = ? AND deleted_at IS NULL", messageID, conversationID).
		Where("NOT EXISTS (SELECT 1 FROM chat_message_user_deletions d WHERE d.message_id = chat_messages.id AND d.userid = ?)", userid).
		Count(&count).Error
	return count > 0, err
}

func (s *ChatService) isMessageActive(db *gorm.DB, messageID uint64) (bool, error) {
	var count int64
	err := db.Table("chat_messages").Where("id = ? AND deleted_at IS NULL", messageID).Count(&count).Error
	return count > 0, err
}

func (s *ChatService) canAccessMessage(db *gorm.DB, userid string, messageID uint64) (bool, error) {
	var count int64
	err := db.Table("chat_messages m").
		Joins("JOIN chat_members cm ON cm.conversation_id = m.conversation_id AND cm.userid = ?", userid).
		Where("m.id = ? AND m.deleted_at IS NULL", messageID).
		Where("NOT EXISTS (SELECT 1 FROM chat_message_user_deletions d WHERE d.message_id = m.id AND d.userid = ?)", userid).
		Count(&count).Error
	return count > 0, err
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
			COALESCE(c.background, '') AS background,
			(SELECT COUNT(*) FROM chat_members cm_count WHERE cm_count.conversation_id = c.id) AS member_count,
			c.pinned_message_id, COALESCE(c.message_pinned_by, '') AS message_pinned_by,
			CASE
				WHEN c.type = 'direct' THEN COALESCE(NULLIF(cc_pinner.nickname, ''), u_pinner.fullname, c.message_pinned_by, '')
				ELSE COALESCE(NULLIF(cm_pinner.nickname, ''), u_pinner.fullname, c.message_pinned_by, '')
			END AS message_pinned_by_name,
			c.message_pinned_at,
			c.created_at, c.updated_at,
			m.id AS last_message_id,
			COALESCE(m.sender_userid, '') AS last_sender_userid,
			CASE
				WHEN c.type = 'direct' THEN COALESCE(NULLIF(cc_sender.nickname, ''), u.fullname, m.sender_userid, '')
				ELSE COALESCE(NULLIF(cm_sender.nickname, ''), u.fullname, m.sender_userid, '')
			END AS last_sender_name,
			COALESCE(u.avatar, '') AS last_sender_avatar,
			COALESCE(m.message_type, '') AS last_message_type,
			COALESCE(m.content, '') AS last_content,
			m.created_at AS last_created_at
		FROM chat_conversations c
		JOIN chat_members cm ON cm.conversation_id = c.id AND cm.userid = ?
		LEFT JOIN chat_messages m ON m.id = (
			SELECT lm.id FROM chat_messages lm
			WHERE lm.conversation_id = c.id
				AND NOT EXISTS (SELECT 1 FROM chat_message_user_deletions d WHERE d.message_id = lm.id AND d.userid = ?)
			ORDER BY lm.id DESC
			LIMIT 1
		)
		LEFT JOIN users u ON u.userid = m.sender_userid
		LEFT JOIN chat_members cm_sender ON cm_sender.conversation_id = c.id AND cm_sender.userid = m.sender_userid
		LEFT JOIN chat_contacts cc_sender ON cc_sender.owner_userid = ? AND cc_sender.contact_userid = m.sender_userid
		LEFT JOIN chat_members cm_pinner ON cm_pinner.conversation_id = c.id AND cm_pinner.userid = c.message_pinned_by
		LEFT JOIN users u_pinner ON u_pinner.userid = c.message_pinned_by
		LEFT JOIN chat_contacts cc_pinner ON cc_pinner.owner_userid = ? AND cc_pinner.contact_userid = c.message_pinned_by
	`
	args := []interface{}{currentUserid, currentUserid, currentUserid, currentUserid}
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
	pinnedMessageIDs := make([]uint64, 0, len(rows))
	for _, row := range rows {
		ids = append(ids, row.ID)
		if row.PinnedMessageID != nil && *row.PinnedMessageID > 0 {
			pinnedMessageIDs = append(pinnedMessageIDs, *row.PinnedMessageID)
		}
	}

	membersByConversation, err := s.loadMembers(db, currentUserid, ids)
	if err != nil {
		return nil, errors.New(ErrSystem)
	}
	pinnedReferences, err := s.loadMessageReferences(db, currentUserid, pinnedMessageIDs)
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	conversations := make([]types.ChatConversation, 0, len(rows))
	for _, row := range rows {
		members := membersByConversation[row.ID]
		conversation := types.ChatConversation{
			ID:                  row.ID,
			Type:                row.Type,
			Name:                row.Name,
			Avatar:              row.Avatar,
			Background:          row.Background,
			MemberCount:         row.MemberCount,
			Members:             members,
			MessagePinnedBy:     row.MessagePinnedBy,
			MessagePinnedByName: row.MessagePinnedByName,
			MessagePinnedAt:     row.MessagePinnedAt,
			CreatedAt:           row.CreatedAt,
			UpdatedAt:           row.UpdatedAt,
		}

		if conversation.Type == "direct" {
			for _, member := range members {
				if member.Userid != currentUserid {
					conversation.Name = chatUserDisplayName(member)
					conversation.Avatar = member.Avatar
					break
				}
			}
			if conversation.Name == "" && len(members) > 0 {
				conversation.Name = chatUserDisplayName(members[0])
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
		if row.PinnedMessageID != nil && *row.PinnedMessageID > 0 {
			conversation.PinnedMessage = pinnedReferences[*row.PinnedMessageID]
		}
		pinState, pinErr := s.loadPinnedMessageState(db, currentUserid, row.ID)
		if pinErr != nil {
			return nil, errors.New(ErrSystem)
		}
		conversation.PinnedMessage = pinState.PinnedMessage
		conversation.PinnedMessages = pinState.PinnedMessages
		conversation.PinnedCount = pinState.PinnedCount

		conversations = append(conversations, conversation)
	}

	if err := s.enrichConversations(db, currentUserid, conversations); err != nil {
		return nil, errors.New(ErrSystem)
	}
	return conversations, nil
}

func (s *ChatService) loadMembers(db *gorm.DB, currentUserid string, conversationIDs []uint64) (map[uint64][]types.ChatUser, error) {
	var rows []memberRow
	if err := db.Raw(`
		SELECT cm.conversation_id,
			COALESCE(u.userid, cm.userid) AS userid,
			COALESCE(u.fullname, cm.userid) AS fullname,
			CASE
				WHEN c.type = 'direct' THEN COALESCE(cc.nickname, '')
				ELSE COALESCE(cm.nickname, '')
			END AS nickname,
			COALESCE(u.avatar, '') AS avatar,
			COALESCE(cm.role, 'member') AS role
		FROM chat_members cm
		JOIN chat_conversations c ON c.id = cm.conversation_id
		LEFT JOIN users u ON u.userid = cm.userid
		LEFT JOIN chat_contacts cc ON cc.owner_userid = ? AND cc.contact_userid = cm.userid
		WHERE cm.conversation_id IN ?
		ORDER BY cm.joined_at ASC
	`, currentUserid, conversationIDs).Scan(&rows).Error; err != nil {
		return nil, err
	}

	result := make(map[uint64][]types.ChatUser)
	for _, row := range rows {
		result[row.ConversationID] = append(result[row.ConversationID], types.ChatUser{
			Userid:   row.Userid,
			Fullname: row.Fullname,
			Nickname: row.Nickname,
			Avatar:   row.Avatar,
			Role:     row.Role,
		})
	}
	for conversationID, members := range result {
		applyUserPresence(members)
		result[conversationID] = members
	}
	return result, nil
}

func applyUserPresence(users []types.ChatUser) {
	if len(users) == 0 {
		return
	}

	userids := make([]string, 0, len(users))
	seen := make(map[string]struct{}, len(users))
	for _, user := range users {
		if user.Userid == "" {
			continue
		}
		if _, exists := seen[user.Userid]; exists {
			continue
		}
		seen[user.Userid] = struct{}{}
		userids = append(userids, user.Userid)
	}

	online := RealtimeHubInstance.OnlineSet(userids)
	for index := range users {
		users[index].IsOnline = online[users[index].Userid]
	}
}

func (s *ChatService) loadMessageByID(db *gorm.DB, currentUserid string, messageID uint64) (*types.ChatMessage, error) {
	var rows []messageRow
	if err := db.Raw(`
		SELECT m.id, m.conversation_id, m.sender_userid,
			CASE
				WHEN c.type = 'direct' THEN COALESCE(NULLIF(cc_sender.nickname, ''), u.fullname, m.sender_userid)
				ELSE COALESCE(NULLIF(cm_sender.nickname, ''), u.fullname, m.sender_userid)
			END AS sender_name,
			COALESCE(u.avatar, '') AS sender_avatar,
			m.message_type, COALESCE(m.content, '') AS content,
			m.reply_to_message_id, m.forwarded_from_message_id, m.created_at
		FROM chat_messages m
		JOIN chat_conversations c ON c.id = m.conversation_id
		LEFT JOIN chat_members cm_sender ON cm_sender.conversation_id = m.conversation_id AND cm_sender.userid = m.sender_userid
		LEFT JOIN chat_contacts cc_sender ON cc_sender.owner_userid = ? AND cc_sender.contact_userid = m.sender_userid
		LEFT JOIN users u ON u.userid = m.sender_userid
		WHERE m.id = ?
	`, currentUserid, messageID).Scan(&rows).Error; err != nil {
		return nil, errors.New(ErrSystem)
	}
	messages, err := s.buildMessages(db, currentUserid, rows)
	if err != nil {
		return nil, err
	}
	if len(messages) == 0 {
		return nil, errors.New(ErrSystem)
	}
	return &messages[0], nil
}

func (s *ChatService) buildMessages(db *gorm.DB, currentUserid string, rows []messageRow) ([]types.ChatMessage, error) {
	if len(rows) == 0 {
		return []types.ChatMessage{}, nil
	}

	messageIDs := make([]uint64, 0, len(rows))
	referenceIDs := make([]uint64, 0)
	seenReferenceIDs := make(map[uint64]struct{})
	for _, row := range rows {
		messageIDs = append(messageIDs, row.ID)
		if row.ReplyToMessageID != nil && *row.ReplyToMessageID > 0 {
			if _, ok := seenReferenceIDs[*row.ReplyToMessageID]; !ok {
				seenReferenceIDs[*row.ReplyToMessageID] = struct{}{}
				referenceIDs = append(referenceIDs, *row.ReplyToMessageID)
			}
		}
		if row.ForwardedFromMessageID != nil && *row.ForwardedFromMessageID > 0 {
			if _, ok := seenReferenceIDs[*row.ForwardedFromMessageID]; !ok {
				seenReferenceIDs[*row.ForwardedFromMessageID] = struct{}{}
				referenceIDs = append(referenceIDs, *row.ForwardedFromMessageID)
			}
		}
	}

	attachmentsByMessage, err := s.loadAttachments(db, messageIDs)
	if err != nil {
		return nil, errors.New(ErrSystem)
	}
	referencesByID, err := s.loadMessageReferences(db, currentUserid, referenceIDs)
	if err != nil {
		return nil, errors.New(ErrSystem)
	}
	pollsByMessage, err := s.loadPolls(db, currentUserid, messageIDs)
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	messages := make([]types.ChatMessage, 0, len(rows))
	for _, row := range rows {
		var replyTo *types.ChatMessageReference
		if row.ReplyToMessageID != nil {
			replyTo = referencesByID[*row.ReplyToMessageID]
		}
		var forwardedFrom *types.ChatMessageReference
		if row.ForwardedFromMessageID != nil {
			forwardedFrom = referencesByID[*row.ForwardedFromMessageID]
		}
		messages = append(messages, types.ChatMessage{
			ID:             row.ID,
			ConversationID: row.ConversationID,
			SenderUserid:   row.SenderUserid,
			SenderName:     row.SenderName,
			SenderAvatar:   row.SenderAvatar,
			Type:           row.MessageType,
			Content:        row.Content,
			ReplyTo:        replyTo,
			ForwardedFrom:  forwardedFrom,
			Attachments:    attachmentsByMessage[row.ID],
			Poll:           pollsByMessage[row.ID],
			CreatedAt:      row.CreatedAt,
		})
	}
	if err := s.enrichMessages(db, currentUserid, messages); err != nil {
		return nil, errors.New(ErrSystem)
	}
	return messages, nil
}

func (s *ChatService) loadPolls(db *gorm.DB, currentUserid string, messageIDs []uint64) (map[uint64]*types.ChatPoll, error) {
	result := make(map[uint64]*types.ChatPoll)
	if len(messageIDs) == 0 {
		return result, nil
	}

	var pollRows []chatPollRecord
	if err := db.Table("chat_polls").
		Where("message_id IN ?", messageIDs).
		Order("id ASC").
		Scan(&pollRows).Error; err != nil {
		return nil, err
	}
	if len(pollRows) == 0 {
		return result, nil
	}

	pollIDs := make([]uint64, 0, len(pollRows))
	pollsByID := make(map[uint64]*types.ChatPoll, len(pollRows))
	for _, row := range pollRows {
		poll := &types.ChatPoll{
			ID:                 row.ID,
			MessageID:          row.MessageID,
			Question:           row.Question,
			AllowCustomOptions: row.AllowCustomOptions,
			AllowMultiple:      row.AllowMultiple,
			ShowVoters:         row.ShowVoters,
			IsClosed:           row.IsClosed,
			ClosedBy:           row.ClosedBy,
			ClosedAt:           row.ClosedAt,
			CreatedBy:          row.CreatedBy,
			Options:            []types.ChatPollOption{},
			MyOptionIDs:        []uint64{},
			CreatedAt:          row.CreatedAt,
			UpdatedAt:          row.UpdatedAt,
		}
		pollIDs = append(pollIDs, row.ID)
		pollsByID[row.ID] = poll
		result[row.MessageID] = poll
	}

	var optionRows []chatPollOptionRecord
	if err := db.Table("chat_poll_options").
		Where("poll_id IN ?", pollIDs).
		Order("id ASC").
		Scan(&optionRows).Error; err != nil {
		return nil, err
	}

	optionIndex := make(map[uint64]struct {
		pollID uint64
		index  int
	}, len(optionRows))
	for _, row := range optionRows {
		poll := pollsByID[row.PollID]
		if poll == nil {
			continue
		}
		poll.Options = append(poll.Options, types.ChatPollOption{
			ID:        row.ID,
			PollID:    row.PollID,
			Text:      row.Text,
			CreatedBy: row.CreatedBy,
			IsCustom:  row.IsCustom,
			Voters:    []types.ChatPollVoter{},
			CreatedAt: row.CreatedAt,
		})
		optionIndex[row.ID] = struct {
			pollID uint64
			index  int
		}{pollID: row.PollID, index: len(poll.Options) - 1}
	}

	var voteRows []pollVoteRow
	if err := db.Raw(`
		SELECT v.poll_id, v.option_id, v.userid,
			COALESCE(u.fullname, v.userid) AS fullname,
			COALESCE(u.avatar, '') AS avatar
		FROM chat_poll_votes v
		LEFT JOIN users u ON u.userid = v.userid
		WHERE v.poll_id IN ?
		ORDER BY v.created_at ASC, v.id ASC
	`, pollIDs).Scan(&voteRows).Error; err != nil {
		return nil, err
	}

	votersByPoll := make(map[uint64]map[string]struct{}, len(pollIDs))
	for _, row := range voteRows {
		optionPosition, ok := optionIndex[row.OptionID]
		if !ok {
			continue
		}
		poll := pollsByID[optionPosition.pollID]
		if poll == nil {
			continue
		}
		option := &poll.Options[optionPosition.index]
		option.VoteCount++
		if poll.ShowVoters {
			option.Voters = append(option.Voters, types.ChatPollVoter{
				Userid:   row.Userid,
				Fullname: row.Fullname,
				Avatar:   row.Avatar,
			})
		}
		if row.Userid == currentUserid {
			poll.MyOptionIDs = append(poll.MyOptionIDs, row.OptionID)
		}
		if votersByPoll[poll.ID] == nil {
			votersByPoll[poll.ID] = make(map[string]struct{})
		}
		votersByPoll[poll.ID][row.Userid] = struct{}{}
	}

	for _, poll := range pollsByID {
		poll.TotalVotes = len(votersByPoll[poll.ID])
		sort.Slice(poll.MyOptionIDs, func(i, j int) bool {
			return poll.MyOptionIDs[i] < poll.MyOptionIDs[j]
		})
	}

	return result, nil
}

func (s *ChatService) findOrCreatePollOption(db *gorm.DB, pollID uint64, currentUserid string, optionText string) (uint64, error) {
	var option chatPollOptionRecord
	err := db.Table("chat_poll_options").
		Where("poll_id = ? AND option_text = ?", pollID, optionText).
		Take(&option).Error
	if err == nil {
		return option.ID, nil
	}
	if !errors.Is(err, gorm.ErrRecordNotFound) {
		return 0, err
	}

	option = chatPollOptionRecord{
		PollID:    pollID,
		Text:      optionText,
		CreatedBy: currentUserid,
		IsCustom:  true,
		CreatedAt: time.Now(),
	}
	if err := db.Table("chat_poll_options").Create(&option).Error; err != nil {
		return 0, err
	}
	return option.ID, nil
}

func (s *ChatService) pollUserOptionIDs(db *gorm.DB, pollID uint64, userid string) ([]uint64, error) {
	var optionIDs []uint64
	err := db.Table("chat_poll_votes").
		Where("poll_id = ? AND userid = ?", pollID, userid).
		Order("option_id ASC").
		Pluck("option_id", &optionIDs).Error
	return optionIDs, err
}

func (s *ChatService) loadMessageReferences(db *gorm.DB, currentUserid string, messageIDs []uint64) (map[uint64]*types.ChatMessageReference, error) {
	result := make(map[uint64]*types.ChatMessageReference)
	if len(messageIDs) == 0 {
		return result, nil
	}

	var rows []messageReferenceRow
	if err := db.Raw(`
		SELECT m.id, m.sender_userid,
			CASE
				WHEN c.type = 'direct' THEN COALESCE(NULLIF(cc_sender.nickname, ''), u.fullname, m.sender_userid)
				ELSE COALESCE(NULLIF(cm_sender.nickname, ''), u.fullname, m.sender_userid)
			END AS sender_name,
			m.message_type, COALESCE(m.content, '') AS content
		FROM chat_messages m
		JOIN chat_conversations c ON c.id = m.conversation_id
		LEFT JOIN chat_members cm_sender ON cm_sender.conversation_id = m.conversation_id AND cm_sender.userid = m.sender_userid
		LEFT JOIN chat_contacts cc_sender ON cc_sender.owner_userid = ? AND cc_sender.contact_userid = m.sender_userid
		LEFT JOIN users u ON u.userid = m.sender_userid
		WHERE m.id IN ?
			AND m.deleted_at IS NULL
			AND NOT EXISTS (SELECT 1 FROM chat_message_user_deletions d WHERE d.message_id = m.id AND d.userid = ?)
	`, currentUserid, messageIDs, currentUserid).Scan(&rows).Error; err != nil {
		return nil, err
	}

	for _, row := range rows {
		result[row.ID] = &types.ChatMessageReference{
			ID:           row.ID,
			SenderUserid: row.SenderUserid,
			SenderName:   row.SenderName,
			Type:         row.MessageType,
			Content:      row.Content,
		}
	}
	return result, nil
}

func (s *ChatService) loadAttachments(db *gorm.DB, messageIDs []uint64) (map[uint64][]types.ChatAttachment, error) {
	var rows []chatAttachmentRecord
	if err := db.Table("chat_message_attachments").
		Where("message_id IN ?", messageIDs).
		Where("deleted_at IS NULL").
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

func (s *ChatService) searchContacts(db *gorm.DB, currentUserid, keyword string, limit int) ([]types.ChatUser, error) {
	like := "%" + keyword + "%"
	var contacts []types.ChatUser
	if err := db.Raw(`
		SELECT u.userid,
			COALESCE(u.fullname, u.userid) AS fullname,
			COALESCE(c.nickname, '') AS nickname,
			COALESCE(u.avatar, '') AS avatar,
			1 AS is_contact
		FROM chat_contacts c
		JOIN users u ON u.userid = c.contact_userid
		WHERE c.owner_userid = ?
			AND (u.userid LIKE ? OR u.fullname LIKE ? OR c.nickname LIKE ?)
		ORDER BY COALESCE(NULLIF(c.nickname, ''), u.fullname, u.userid) ASC, u.userid ASC
		LIMIT ?
	`, currentUserid, like, like, like, limit).Scan(&contacts).Error; err != nil {
		return nil, err
	}
	applyUserPresence(contacts)
	return contacts, nil
}

func (s *ChatService) searchMessages(db *gorm.DB, currentUserid, keyword string, limit int) ([]types.ChatMessage, error) {
	var rows []messageRow
	query := `
		SELECT m.id, m.conversation_id, m.sender_userid,
			CASE
				WHEN c.type = 'direct' THEN COALESCE(NULLIF(cc_sender.nickname, ''), u.fullname, m.sender_userid)
				ELSE COALESCE(NULLIF(cm_sender.nickname, ''), u.fullname, m.sender_userid)
			END AS sender_name,
			COALESCE(u.avatar, '') AS sender_avatar,
			m.message_type, COALESCE(m.content, '') AS content,
			m.reply_to_message_id, m.forwarded_from_message_id, m.created_at
		FROM chat_messages m
		JOIN chat_conversations c ON c.id = m.conversation_id
		JOIN chat_members cm_self ON cm_self.conversation_id = m.conversation_id AND cm_self.userid = ?
		LEFT JOIN chat_members cm_sender ON cm_sender.conversation_id = m.conversation_id AND cm_sender.userid = m.sender_userid
		LEFT JOIN chat_contacts cc_sender ON cc_sender.owner_userid = ? AND cc_sender.contact_userid = m.sender_userid
		LEFT JOIN users u ON u.userid = m.sender_userid
		WHERE m.message_type NOT IN ('call', 'system')
			AND m.deleted_at IS NULL
			AND NOT EXISTS (SELECT 1 FROM chat_message_user_deletions d WHERE d.message_id = m.id AND d.userid = ?)
	`
	args := []interface{}{currentUserid, currentUserid, currentUserid}
	if db.Dialector.Name() == "mysql" {
		booleanQuery := mysqlBooleanSearch(keyword)
		if booleanQuery == "" {
			return []types.ChatMessage{}, nil
		}
		query += " AND MATCH(m.content) AGAINST (? IN BOOLEAN MODE)"
		args = append(args, booleanQuery)
	} else {
		query += " AND COALESCE(m.content, '') LIKE ?"
		args = append(args, "%"+keyword+"%")
	}
	query += `
		ORDER BY m.id DESC
		LIMIT ?
	`
	args = append(args, limit)
	if err := db.Raw(query, args...).Scan(&rows).Error; err != nil {
		return nil, err
	}
	return s.buildMessages(db, currentUserid, rows)
}

func (s *ChatService) searchFiles(db *gorm.DB, currentUserid, keyword string, limit int) ([]types.ChatMessage, error) {
	var rows []messageRow
	query := `
		SELECT DISTINCT m.id, m.conversation_id, m.sender_userid,
			CASE
				WHEN c.type = 'direct' THEN COALESCE(NULLIF(cc_sender.nickname, ''), u.fullname, m.sender_userid)
				ELSE COALESCE(NULLIF(cm_sender.nickname, ''), u.fullname, m.sender_userid)
			END AS sender_name,
			COALESCE(u.avatar, '') AS sender_avatar,
			m.message_type, COALESCE(m.content, '') AS content,
			m.reply_to_message_id, m.forwarded_from_message_id, m.created_at
		FROM chat_message_attachments a
		JOIN chat_messages m ON m.id = a.message_id
		JOIN chat_conversations c ON c.id = m.conversation_id
		JOIN chat_members cm_self ON cm_self.conversation_id = m.conversation_id AND cm_self.userid = ?
		LEFT JOIN chat_members cm_sender ON cm_sender.conversation_id = m.conversation_id AND cm_sender.userid = m.sender_userid
		LEFT JOIN chat_contacts cc_sender ON cc_sender.owner_userid = ? AND cc_sender.contact_userid = m.sender_userid
		LEFT JOIN users u ON u.userid = m.sender_userid
		WHERE m.message_type NOT IN ('call', 'system')
			AND m.deleted_at IS NULL AND a.deleted_at IS NULL
			AND NOT EXISTS (SELECT 1 FROM chat_message_user_deletions d WHERE d.message_id = m.id AND d.userid = ?)
	`
	args := []interface{}{currentUserid, currentUserid, currentUserid}
	if db.Dialector.Name() == "mysql" {
		booleanQuery := mysqlBooleanSearch(keyword)
		if booleanQuery == "" {
			return []types.ChatMessage{}, nil
		}
		query += " AND MATCH(a.file_name, a.relative_path) AGAINST (? IN BOOLEAN MODE)"
		args = append(args, booleanQuery)
	} else {
		like := "%" + keyword + "%"
		query += " AND (a.file_name LIKE ? OR a.relative_path LIKE ?)"
		args = append(args, like, like)
	}
	query += `
		ORDER BY m.id DESC
		LIMIT ?
	`
	args = append(args, limit)
	if err := db.Raw(query, args...).Scan(&rows).Error; err != nil {
		return nil, err
	}
	return s.buildMessages(db, currentUserid, rows)
}

func normalizeSearchScope(scope string) string {
	normalized := strings.ToLower(strings.TrimSpace(scope))
	switch normalized {
	case "contacts", "messages", "files":
		return normalized
	default:
		return "all"
	}
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

func subtractUserids(userids []string, existing []string) []string {
	existingSet := make(map[string]bool, len(existing))
	for _, userid := range existing {
		existingSet[userid] = true
	}

	result := make([]string, 0, len(userids))
	for _, userid := range userids {
		if userid == "" || existingSet[userid] {
			continue
		}
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
		if name := chatUserDisplayName(member); name != "" {
			names = append(names, name)
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

func chatUserDisplayName(user types.ChatUser) string {
	if strings.TrimSpace(user.Nickname) != "" {
		return strings.TrimSpace(user.Nickname)
	}
	if strings.TrimSpace(user.Fullname) != "" {
		return strings.TrimSpace(user.Fullname)
	}
	return user.Userid
}

func normalizePollOptions(options []string) ([]string, error) {
	result := make([]string, 0, len(options))
	seen := make(map[string]bool, len(options))
	for _, option := range options {
		option = strings.TrimSpace(option)
		if option == "" {
			continue
		}
		if len([]rune(option)) > maxPollOptionLength {
			return nil, errors.New(ErrChatInvalidPoll)
		}
		key := strings.ToLower(option)
		if seen[key] {
			return nil, errors.New(ErrChatInvalidPoll)
		}
		seen[key] = true
		result = append(result, option)
	}
	if len(result) > maxPollOptions {
		return nil, errors.New(ErrChatInvalidPoll)
	}
	return result, nil
}

func pollVoteAction(previousOptionIDs []uint64, selectedOptionIDs []uint64) string {
	if sameUintSet(previousOptionIDs, selectedOptionIDs) {
		return ""
	}
	if len(previousOptionIDs) == 0 && len(selectedOptionIDs) > 0 {
		return "đã bình chọn trong"
	}
	if len(previousOptionIDs) > 0 && len(selectedOptionIDs) == 0 {
		return "đã hủy bình chọn trong"
	}
	return "đã đổi bình chọn trong"
}

func sameUintSet(first []uint64, second []uint64) bool {
	first = normalizeUintIDs(first)
	second = normalizeUintIDs(second)
	if len(first) != len(second) {
		return false
	}
	firstSet := make(map[uint64]bool, len(first))
	for _, id := range first {
		firstSet[id] = true
	}
	for _, id := range second {
		if !firstSet[id] {
			return false
		}
	}
	return true
}

func shortPollQuestion(question string) string {
	question = strings.TrimSpace(question)
	runes := []rune(question)
	if len(runes) <= 80 {
		return question
	}
	return string(runes[:80]) + "..."
}

func normalizeUintIDs(ids []uint64) []uint64 {
	result := make([]uint64, 0, len(ids))
	seen := make(map[uint64]bool, len(ids))
	for _, id := range ids {
		if id == 0 || seen[id] {
			continue
		}
		seen[id] = true
		result = append(result, id)
	}
	return result
}

func boolInt(value bool) int {
	if value {
		return 1
	}
	return 0
}

func isValidMessageType(messageType string) bool {
	switch messageType {
	case "text", "link", "file", "folder", "voice", "call":
		return true
	default:
		return false
	}
}
