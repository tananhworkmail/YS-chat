package services

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
	"unicode"

	"web-api/internal/pkg/config"
	"web-api/internal/pkg/models/request"
	"web-api/internal/pkg/models/types"

	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

const (
	defaultRecallWindow = 15 * time.Minute
	maxReactionRunes    = 16
)

// chatDBOverride is intentionally package-private and is used by service tests
// to exercise transaction semantics without connecting to the company DB.
var chatDBOverride *gorm.DB

type productionMessageRecord struct {
	ID                     uint64     `gorm:"column:id;primaryKey"`
	ConversationID         uint64     `gorm:"column:conversation_id"`
	SenderUserid           string     `gorm:"column:sender_userid"`
	MessageType            string     `gorm:"column:message_type"`
	Content                string     `gorm:"column:content"`
	ReplyToMessageID       *uint64    `gorm:"column:reply_to_message_id"`
	ForwardedFromMessageID *uint64    `gorm:"column:forwarded_from_message_id"`
	ClientMessageID        *string    `gorm:"column:client_message_id"`
	ServerSequence         *uint64    `gorm:"column:server_sequence"`
	Version                uint       `gorm:"column:version"`
	EditedAt               *time.Time `gorm:"column:edited_at"`
	DeletedAt              *time.Time `gorm:"column:deleted_at"`
	DeletedBy              string     `gorm:"column:deleted_by"`
	CreatedAt              time.Time  `gorm:"column:created_at"`
}

type productionAttachmentRecord struct {
	ID           uint64     `gorm:"column:id;primaryKey"`
	MessageID    uint64     `gorm:"column:message_id"`
	FileName     string     `gorm:"column:file_name"`
	FileURL      string     `gorm:"column:file_url"`
	FileSize     int64      `gorm:"column:file_size"`
	MimeType     string     `gorm:"column:mime_type"`
	RelativePath string     `gorm:"column:relative_path"`
	DeletedAt    *time.Time `gorm:"column:deleted_at"`
	DeletedBy    string     `gorm:"column:deleted_by"`
	CreatedAt    time.Time  `gorm:"column:created_at"`
}

type productionPendingUploadRecord struct {
	ID               uint64    `gorm:"column:id;primaryKey"`
	Userid           string    `gorm:"column:userid"`
	FileURL          string    `gorm:"column:file_url"`
	FileName         string    `gorm:"column:file_name"`
	FileSize         int64     `gorm:"column:file_size"`
	MimeType         string    `gorm:"column:mime_type"`
	RelativePath     string    `gorm:"column:relative_path"`
	ClaimedMessageID *uint64   `gorm:"column:claimed_message_id"`
	CreatedAt        time.Time `gorm:"column:created_at"`
}

type productionMemberState struct {
	ConversationID         uint64     `gorm:"column:conversation_id"`
	Userid                 string     `gorm:"column:userid"`
	LastDeliveredMessageID *uint64    `gorm:"column:last_delivered_message_id"`
	LastReadMessageID      *uint64    `gorm:"column:last_read_message_id"`
	LastReadAt             *time.Time `gorm:"column:last_read_at"`
	UnreadCount            int        `gorm:"column:unread_count"`
	MuteUntil              *time.Time `gorm:"column:mute_until"`
	PinnedAt               *time.Time `gorm:"column:pinned_at"`
	ArchivedAt             *time.Time `gorm:"column:archived_at"`
}

type productionMemberInsertRecord struct {
	ConversationID         uint64     `gorm:"column:conversation_id"`
	Userid                 string     `gorm:"column:userid"`
	Role                   string     `gorm:"column:role"`
	LastDeliveredMessageID *uint64    `gorm:"column:last_delivered_message_id"`
	LastReadMessageID      *uint64    `gorm:"column:last_read_message_id"`
	LastReadAt             *time.Time `gorm:"column:last_read_at"`
	UnreadCount            int        `gorm:"column:unread_count"`
	JoinedAt               time.Time  `gorm:"column:joined_at"`
}

type productionReceiptRecord struct {
	ID             uint64     `gorm:"column:id;primaryKey"`
	MessageID      uint64     `gorm:"column:message_id"`
	ConversationID uint64     `gorm:"column:conversation_id"`
	Userid         string     `gorm:"column:userid"`
	DeliveredAt    *time.Time `gorm:"column:delivered_at"`
	ReadAt         *time.Time `gorm:"column:read_at"`
	CreatedAt      time.Time  `gorm:"column:created_at"`
	UpdatedAt      time.Time  `gorm:"column:updated_at"`
}

type productionReactionRecord struct {
	ID             uint64    `gorm:"column:id;primaryKey"`
	MessageID      uint64    `gorm:"column:message_id"`
	ConversationID uint64    `gorm:"column:conversation_id"`
	Userid         string    `gorm:"column:userid"`
	Emoji          string    `gorm:"column:emoji"`
	CreatedAt      time.Time `gorm:"column:created_at"`
	UpdatedAt      time.Time `gorm:"column:updated_at"`
}

type productionUserDeletionRecord struct {
	ID             uint64    `gorm:"column:id;primaryKey"`
	MessageID      uint64    `gorm:"column:message_id"`
	ConversationID uint64    `gorm:"column:conversation_id"`
	Userid         string    `gorm:"column:userid"`
	DeletedAt      time.Time `gorm:"column:deleted_at"`
}

type productionAuditRecord struct {
	ID              uint64    `gorm:"column:id;primaryKey"`
	MessageID       uint64    `gorm:"column:message_id"`
	ConversationID  uint64    `gorm:"column:conversation_id"`
	ActorUserid     string    `gorm:"column:actor_userid"`
	Action          string    `gorm:"column:action"`
	PreviousVersion uint      `gorm:"column:previous_version"`
	NewVersion      uint      `gorm:"column:new_version"`
	SnapshotJSON    string    `gorm:"column:snapshot_json"`
	CreatedAt       time.Time `gorm:"column:created_at"`
}

type messageProductionMetadata struct {
	ID              uint64     `gorm:"column:id"`
	ClientMessageID string     `gorm:"column:client_message_id"`
	ServerSequence  uint64     `gorm:"column:server_sequence"`
	Version         uint       `gorm:"column:version"`
	EditedAt        *time.Time `gorm:"column:edited_at"`
	DeletedAt       *time.Time `gorm:"column:deleted_at"`
	DeletedBy       string     `gorm:"column:deleted_by"`
}

type receiptDisplayRow struct {
	MessageID   uint64     `gorm:"column:message_id"`
	Userid      string     `gorm:"column:userid"`
	Fullname    string     `gorm:"column:fullname"`
	Avatar      string     `gorm:"column:avatar"`
	DeliveredAt *time.Time `gorm:"column:delivered_at"`
	ReadAt      *time.Time `gorm:"column:read_at"`
}

type reactionDisplayRow struct {
	MessageID uint64    `gorm:"column:message_id"`
	Userid    string    `gorm:"column:userid"`
	Fullname  string    `gorm:"column:fullname"`
	Avatar    string    `gorm:"column:avatar"`
	Emoji     string    `gorm:"column:emoji"`
	UpdatedAt time.Time `gorm:"column:updated_at"`
}

type editHistoryRow struct {
	ID              uint64    `gorm:"column:id"`
	MessageID       uint64    `gorm:"column:message_id"`
	ConversationID  uint64    `gorm:"column:conversation_id"`
	ActorUserid     string    `gorm:"column:actor_userid"`
	Action          string    `gorm:"column:action"`
	PreviousVersion uint      `gorm:"column:previous_version"`
	NewVersion      uint      `gorm:"column:new_version"`
	SnapshotJSON    string    `gorm:"column:snapshot_json"`
	CreatedAt       time.Time `gorm:"column:created_at"`
	EditorName      string    `gorm:"column:editor_name"`
	EditorAvatar    string    `gorm:"column:editor_avatar"`
}

func (s *ChatService) productionDB() (*gorm.DB, error) {
	if chatDBOverride != nil {
		return chatDBOverride, nil
	}
	return s.chatDB()
}

// lockChatConversationRows is the first write lock taken by every operation
// that can change the recipient snapshot or conversation membership. Sorting
// also gives cross-conversation forwards one deterministic lock order.
func lockChatConversationRows(tx *gorm.DB, conversationIDs ...uint64) error {
	seen := make(map[uint64]struct{}, len(conversationIDs))
	ids := make([]uint64, 0, len(conversationIDs))
	for _, conversationID := range conversationIDs {
		if conversationID == 0 {
			continue
		}
		if _, exists := seen[conversationID]; exists {
			continue
		}
		seen[conversationID] = struct{}{}
		ids = append(ids, conversationID)
	}
	if len(ids) == 0 {
		return errors.New(ErrChatConversationNotFound)
	}
	sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })
	var rows []struct {
		ID uint64 `gorm:"column:id"`
	}
	query := tx.Table("chat_conversations").Select("id").Where("id IN ?", ids).Order("id ASC")
	if tx.Dialector.Name() == "mysql" {
		query = query.Clauses(clause.Locking{Strength: "UPDATE"})
	}
	if err := query.Find(&rows).Error; err != nil {
		return err
	}
	if len(rows) != len(ids) {
		return errors.New(ErrChatConversationNotFound)
	}
	return nil
}

// SendMessage is retained for internal/older callers while the HTTP endpoint
// exposes the replay bit returned by SendMessageIdempotent.
func (s *ChatService) SendMessage(currentUserid string, conversationID uint64, req request.SendChatMessageRequest) (*types.ChatMessage, error) {
	message, _, err := s.SendMessageIdempotent(currentUserid, conversationID, req)
	return message, err
}

func (s *ChatService) SendMessageIdempotent(currentUserid string, conversationID uint64, req request.SendChatMessageRequest) (*types.ChatMessage, bool, error) {
	db, err := s.productionDB()
	if err != nil {
		return nil, false, errors.New(ErrSystem)
	}
	if ok, checkErr := s.isConversationMember(db, conversationID, currentUserid); checkErr != nil {
		return nil, false, errors.New(ErrSystem)
	} else if !ok {
		return nil, false, errors.New(ErrChatNoPermission)
	}

	clientMessageID := strings.TrimSpace(req.ClientMessageID)
	if clientMessageID == "" {
		// Legacy clients remain accepted, but every newly persisted message still
		// gets an identifier that newer responses can retain for future retries.
		clientMessageID = uuid.NewString()
	} else if parsed, parseErr := uuid.Parse(clientMessageID); parseErr != nil {
		return nil, false, errors.New(ErrInvalidInput)
	} else {
		clientMessageID = strings.ToLower(parsed.String())
	}

	if existing, findErr := s.findMessageByClientID(db, currentUserid, clientMessageID); findErr == nil && existing != nil {
		if existing.ConversationID != conversationID {
			return nil, false, errors.New(ErrChatClientMessageIDConflict)
		}
		message, loadErr := s.loadMessageByID(db, currentUserid, existing.ID)
		return message, true, loadErr
	} else if findErr != nil {
		return nil, false, errors.New(ErrSystem)
	}

	messageType := strings.TrimSpace(req.Type)
	content := strings.TrimSpace(req.Content)
	if !isValidMessageType(messageType) {
		return nil, false, errors.New(ErrChatInvalidMessageType)
	}
	if (messageType == "text" || messageType == "link" || messageType == "call") && content == "" {
		return nil, false, errors.New(ErrChatEmptyMessage)
	}
	attachments, attachmentErr := normalizeAttachmentInputs(req.Attachments, req.ForwardedFromMessageID > 0)
	if attachmentErr != nil {
		return nil, false, attachmentErr
	}
	if (messageType == "file" || messageType == "folder" || messageType == "voice") && len(attachments) == 0 {
		return nil, false, errors.New(ErrChatEmptyMessage)
	}

	var replyToMessageID *uint64
	if req.ReplyToMessageID > 0 {
		if ok, checkErr := s.messageInConversation(db, currentUserid, conversationID, req.ReplyToMessageID); checkErr != nil {
			return nil, false, errors.New(ErrSystem)
		} else if !ok {
			return nil, false, errors.New(ErrChatNoPermission)
		}
		replyToMessageID = &req.ReplyToMessageID
	}
	var forwardedFromMessageID *uint64
	var forwardedConversationID uint64
	if req.ForwardedFromMessageID > 0 {
		if ok, checkErr := s.canAccessMessage(db, currentUserid, req.ForwardedFromMessageID); checkErr != nil {
			return nil, false, errors.New(ErrSystem)
		} else if !ok {
			return nil, false, errors.New(ErrChatNoPermission)
		}
		forwardedFromMessageID = &req.ForwardedFromMessageID
		if findErr := db.Table("chat_messages").Select("conversation_id").Where("id = ?", req.ForwardedFromMessageID).Scan(&forwardedConversationID).Error; findErr != nil {
			return nil, false, errors.New(ErrSystem)
		}
	}

	var messageID uint64
	err = db.Transaction(func(tx *gorm.DB) error {
		now := time.Now().UTC()
		if lockErr := lockChatConversationRows(tx, conversationID, forwardedConversationID); lockErr != nil {
			return lockErr
		}
		var member struct {
			ID uint64 `gorm:"column:id"`
		}
		memberQuery := tx.Table("chat_members").Select("id").Where("conversation_id = ? AND userid = ?", conversationID, currentUserid)
		if tx.Dialector.Name() == "mysql" {
			memberQuery = memberQuery.Clauses(clause.Locking{Strength: "UPDATE"})
		}
		if takeErr := memberQuery.Take(&member).Error; takeErr != nil {
			if errors.Is(takeErr, gorm.ErrRecordNotFound) {
				return errors.New(ErrChatNoPermission)
			}
			return takeErr
		}
		record := productionMessageRecord{
			ConversationID: conversationID, SenderUserid: currentUserid, MessageType: messageType,
			Content: content, ReplyToMessageID: replyToMessageID, ForwardedFromMessageID: forwardedFromMessageID,
			ClientMessageID: &clientMessageID, Version: 1, CreatedAt: now,
		}
		if createErr := tx.Table("chat_messages").Create(&record).Error; createErr != nil {
			return createErr
		}
		messageID = record.ID
		if updateErr := tx.Table("chat_messages").Where("id = ?", messageID).Update("server_sequence", messageID).Error; updateErr != nil {
			return updateErr
		}
		for _, attachment := range attachments {
			item, authorizeErr := s.authorizeAndClaimAttachment(tx, currentUserid, forwardedFromMessageID, messageID, attachment)
			if authorizeErr != nil {
				return authorizeErr
			}
			item.CreatedAt = now
			if createErr := tx.Table("chat_message_attachments").Create(&item).Error; createErr != nil {
				return createErr
			}
		}
		if updateErr := tx.Table("chat_members").Where("conversation_id = ? AND userid <> ?", conversationID, currentUserid).
			UpdateColumn("unread_count", gorm.Expr("unread_count + 1")).Error; updateErr != nil {
			return updateErr
		}
		var recipientUserids []string
		if findErr := tx.Table("chat_members").Where("conversation_id = ? AND userid <> ?", conversationID, currentUserid).Pluck("userid", &recipientUserids).Error; findErr != nil {
			return findErr
		}
		if len(recipientUserids) > 0 {
			receipts := make([]productionReceiptRecord, 0, len(recipientUserids))
			for _, userid := range recipientUserids {
				receipts = append(receipts, productionReceiptRecord{MessageID: messageID, ConversationID: conversationID, Userid: userid, CreatedAt: now, UpdatedAt: now})
			}
			if createErr := tx.Table("chat_message_receipts").CreateInBatches(receipts, 500).Error; createErr != nil {
				return createErr
			}
		}
		return tx.Table("chat_conversations").Where("id = ?", conversationID).Update("updated_at", now).Error
	})
	if err != nil {
		// The unique (sender_userid, client_message_id) key is the final arbiter
		// when concurrent retries both pass the optimistic lookup above.
		existing, findErr := s.findMessageByClientID(db, currentUserid, clientMessageID)
		if findErr == nil && existing != nil {
			if existing.ConversationID != conversationID {
				return nil, false, errors.New(ErrChatClientMessageIDConflict)
			}
			message, loadErr := s.loadMessageByID(db, currentUserid, existing.ID)
			return message, true, loadErr
		}
		if err.Error() == ErrChatNoPermission {
			return nil, false, err
		}
		return nil, false, errors.New(ErrSystem)
	}

	message, err := s.loadMessageByID(db, currentUserid, messageID)
	if err != nil {
		return nil, false, err
	}
	s.broadcastMessageCreated(db, conversationID, message)
	if chatDBOverride == nil {
		go PushServiceInstance.SendChatMessageNotification(db, currentUserid, conversationID, message.ID, message.Type, message.Content)
	}
	return message, false, nil
}

func (s *ChatService) RegisterPendingUploads(currentUserid string, attachments []types.ChatAttachment) error {
	if strings.TrimSpace(currentUserid) == "" || len(attachments) == 0 {
		return errors.New(ErrInvalidInput)
	}
	db, err := s.productionDB()
	if err != nil {
		return errors.New(ErrSystem)
	}
	now := time.Now().UTC()
	records := make([]productionPendingUploadRecord, 0, len(attachments))
	for _, attachment := range attachments {
		path, pathErr := localChatAttachmentPath(attachment.FileURL)
		if pathErr != nil {
			return errors.New(ErrInvalidInput)
		}
		info, statErr := os.Stat(path)
		if statErr != nil || !info.Mode().IsRegular() {
			return errors.New(ErrInvalidInput)
		}
		fileName := filepath.Base(strings.TrimSpace(attachment.FileName))
		if fileName == "" || fileName == "." {
			return errors.New(ErrInvalidInput)
		}
		records = append(records, productionPendingUploadRecord{
			Userid: currentUserid, FileURL: strings.TrimSpace(attachment.FileURL), FileName: fileName,
			FileSize: info.Size(), MimeType: strings.TrimSpace(attachment.MimeType), RelativePath: strings.TrimSpace(attachment.RelativePath), CreatedAt: now,
		})
	}
	return db.Transaction(func(tx *gorm.DB) error {
		return tx.Table("chat_pending_uploads").CreateInBatches(records, 100).Error
	})
}

func normalizeAttachmentInputs(inputs []request.ChatAttachmentInput, allowForwarded bool) ([]request.ChatAttachmentInput, error) {
	result := make([]request.ChatAttachmentInput, 0, len(inputs))
	seen := map[string]bool{}
	for _, input := range inputs {
		input.FileName = filepath.Base(strings.TrimSpace(input.FileName))
		input.FileURL = strings.TrimSpace(input.FileURL)
		input.MimeType = strings.TrimSpace(input.MimeType)
		input.RelativePath = strings.TrimSpace(input.RelativePath)
		if input.FileName == "" || input.FileName == "." || input.FileURL == "" || input.FileSize < 0 {
			return nil, errors.New(ErrInvalidInput)
		}
		if _, pathErr := localChatAttachmentPath(input.FileURL); pathErr != nil && !allowForwarded {
			return nil, errors.New(ErrChatNoPermission)
		}
		key := input.FileURL + "\x00" + input.RelativePath
		if seen[key] {
			continue
		}
		seen[key] = true
		result = append(result, input)
	}
	return result, nil
}

func (s *ChatService) authorizeAndClaimAttachment(tx *gorm.DB, userid string, forwardedFromMessageID *uint64, messageID uint64, input request.ChatAttachmentInput) (productionAttachmentRecord, error) {
	if forwardedFromMessageID != nil {
		var source productionAttachmentRecord
		sourceQuery := tx.Table("chat_message_attachments AS a").
			Select("a.id, a.message_id, a.file_name, a.file_url, a.file_size, a.mime_type, a.relative_path, a.deleted_at, a.deleted_by, a.created_at").
			Joins("JOIN chat_messages m ON m.id = a.message_id").
			Joins("JOIN chat_members source_member ON source_member.conversation_id = m.conversation_id AND source_member.userid = ?", userid).
			Where("a.message_id = ? AND a.file_url = ? AND a.deleted_at IS NULL AND m.deleted_at IS NULL", *forwardedFromMessageID, input.FileURL).
			Where("NOT EXISTS (SELECT 1 FROM chat_message_user_deletions d WHERE d.message_id = m.id AND d.userid = ?)", userid)
		if tx.Dialector.Name() == "mysql" {
			sourceQuery = sourceQuery.Clauses(clause.Locking{Strength: "UPDATE"})
		}
		if sourceErr := sourceQuery.Take(&source).Error; sourceErr == nil {
			source.ID = 0
			source.MessageID = messageID
			source.DeletedAt = nil
			source.DeletedBy = ""
			return source, nil
		} else if !errors.Is(sourceErr, gorm.ErrRecordNotFound) {
			return productionAttachmentRecord{}, sourceErr
		}
	}
	var pending productionPendingUploadRecord
	query := tx.Table("chat_pending_uploads").Where("userid = ? AND file_url = ?", userid, input.FileURL)
	if tx.Dialector.Name() == "mysql" {
		query = query.Clauses(clause.Locking{Strength: "UPDATE"})
	}
	if err := query.Take(&pending).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return productionAttachmentRecord{}, errors.New(ErrChatNoPermission)
		}
		return productionAttachmentRecord{}, err
	}
	if pending.ClaimedMessageID != nil && *pending.ClaimedMessageID != messageID {
		return productionAttachmentRecord{}, errors.New(ErrChatNoPermission)
	}
	if pending.ClaimedMessageID == nil {
		result := tx.Table("chat_pending_uploads").Where("id = ? AND claimed_message_id IS NULL", pending.ID).Update("claimed_message_id", messageID)
		if result.Error != nil {
			return productionAttachmentRecord{}, result.Error
		}
		if result.RowsAffected != 1 {
			return productionAttachmentRecord{}, errors.New(ErrChatNoPermission)
		}
	}
	return productionAttachmentRecord{
		MessageID: messageID, FileName: pending.FileName, FileURL: pending.FileURL, FileSize: pending.FileSize,
		MimeType: pending.MimeType, RelativePath: pending.RelativePath,
	}, nil
}

func (s *ChatService) findMessageByClientID(db *gorm.DB, senderUserid, clientMessageID string) (*productionMessageRecord, error) {
	var record productionMessageRecord
	err := db.Table("chat_messages").Where("sender_userid = ? AND client_message_id = ?", senderUserid, clientMessageID).Take(&record).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &record, nil
}

func (s *ChatService) MarkRead(currentUserid string, conversationID, requestedMessageID uint64) (*types.ChatConversationReadState, error) {
	if requestedMessageID == 0 {
		return nil, errors.New(ErrInvalidInput)
	}
	db, err := s.productionDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}
	var state types.ChatConversationReadState
	var effectiveMessageID uint64
	err = db.Transaction(func(tx *gorm.DB) error {
		var member productionMemberState
		query := tx.Table("chat_members").Where("conversation_id = ? AND userid = ?", conversationID, currentUserid)
		if tx.Dialector.Name() == "mysql" {
			query = query.Clauses(clause.Locking{Strength: "UPDATE"})
		}
		if takeErr := query.Take(&member).Error; takeErr != nil {
			if errors.Is(takeErr, gorm.ErrRecordNotFound) {
				return errors.New(ErrChatNoPermission)
			}
			return takeErr
		}
		var target productionMessageRecord
		if takeErr := tx.Table("chat_messages").Where("id = ? AND conversation_id = ?", requestedMessageID, conversationID).Take(&target).Error; takeErr != nil {
			if errors.Is(takeErr, gorm.ErrRecordNotFound) {
				return errors.New(ErrChatMessageNotFound)
			}
			return takeErr
		}
		previousID := uint64(0)
		if member.LastReadMessageID != nil {
			previousID = *member.LastReadMessageID
		}
		effectiveID := requestedMessageID
		if member.LastReadMessageID != nil && *member.LastReadMessageID > effectiveID {
			effectiveID = *member.LastReadMessageID
		}
		effectiveMessageID = effectiveID
		now := time.Now().UTC()
		if receiptErr := s.updateReceiptSnapshotThrough(tx, currentUserid, conversationID, previousID, effectiveID, now, true); receiptErr != nil {
			return receiptErr
		}
		var unread int64
		if countErr := tx.Table("chat_messages AS m").
			Where("m.conversation_id = ? AND m.id > ? AND m.sender_userid <> ? AND m.message_type <> 'system' AND m.deleted_at IS NULL", conversationID, effectiveID, currentUserid).
			Where("NOT EXISTS (SELECT 1 FROM chat_message_user_deletions d WHERE d.message_id = m.id AND d.userid = ?)", currentUserid).
			Count(&unread).Error; countErr != nil {
			return countErr
		}
		effectiveDeliveredID := effectiveID
		if member.LastDeliveredMessageID != nil && *member.LastDeliveredMessageID > effectiveDeliveredID {
			effectiveDeliveredID = *member.LastDeliveredMessageID
		}
		if updateErr := tx.Table("chat_members").Where("conversation_id = ? AND userid = ?", conversationID, currentUserid).Updates(map[string]interface{}{
			"last_delivered_message_id": effectiveDeliveredID,
			"last_read_message_id":      effectiveID,
			"last_read_at":              now,
			"unread_count":              unread,
		}).Error; updateErr != nil {
			return updateErr
		}
		state = types.ChatConversationReadState{ConversationID: conversationID, Userid: currentUserid, LastReadMessageID: &effectiveID, LastReadAt: &now, UnreadCount: int(unread)}
		return nil
	})
	if err != nil {
		return nil, normalizeProductionError(err)
	}
	s.broadcastReceipt(db, "read.receipt", currentUserid, conversationID, effectiveMessageID, map[string]interface{}{"readState": state})
	return &state, nil
}

func (s *ChatService) MarkDelivered(currentUserid string, conversationID, messageID uint64) error {
	if conversationID == 0 || messageID == 0 {
		return errors.New(ErrInvalidInput)
	}
	db, err := s.productionDB()
	if err != nil {
		return errors.New(ErrSystem)
	}
	now := time.Now().UTC()
	var effectiveMessageID uint64
	if err := db.Transaction(func(tx *gorm.DB) error {
		var member productionMemberState
		memberQuery := tx.Table("chat_members").Where("conversation_id = ? AND userid = ?", conversationID, currentUserid)
		if tx.Dialector.Name() == "mysql" {
			memberQuery = memberQuery.Clauses(clause.Locking{Strength: "UPDATE"})
		}
		if takeErr := memberQuery.Take(&member).Error; takeErr != nil {
			if errors.Is(takeErr, gorm.ErrRecordNotFound) {
				return errors.New(ErrChatNoPermission)
			}
			return takeErr
		}
		var target productionMessageRecord
		if takeErr := tx.Table("chat_messages").Where("id = ? AND conversation_id = ?", messageID, conversationID).Take(&target).Error; takeErr != nil {
			if errors.Is(takeErr, gorm.ErrRecordNotFound) {
				return errors.New(ErrChatMessageNotFound)
			}
			return takeErr
		}
		previousID := uint64(0)
		if member.LastDeliveredMessageID != nil {
			previousID = *member.LastDeliveredMessageID
		}
		effectiveID := messageID
		if previousID > effectiveID {
			effectiveID = previousID
		}
		effectiveMessageID = effectiveID
		if err := s.updateReceiptSnapshotThrough(tx, currentUserid, conversationID, previousID, effectiveID, now, false); err != nil {
			return err
		}
		return tx.Table("chat_members").Where("conversation_id = ? AND userid = ?", conversationID, currentUserid).Update("last_delivered_message_id", effectiveID).Error
	}); err != nil {
		return normalizeProductionError(err)
	}
	s.broadcastReceipt(db, "delivery.receipt", currentUserid, conversationID, effectiveMessageID, map[string]interface{}{"userid": currentUserid, "messageId": effectiveMessageID, "deliveredAt": now})
	return nil
}

func (s *ChatService) updateReceiptSnapshotThrough(tx *gorm.DB, userid string, conversationID, afterMessageID, throughMessageID uint64, at time.Time, read bool) error {
	updates := map[string]interface{}{"delivered_at": gorm.Expr("COALESCE(delivered_at, ?)", at), "updated_at": at}
	if read {
		updates["read_at"] = gorm.Expr("COALESCE(read_at, ?)", at)
	}
	query := tx.Table("chat_message_receipts").Where("conversation_id = ? AND userid = ? AND message_id <= ?", conversationID, userid, throughMessageID)
	if afterMessageID > 0 {
		query = query.Where("message_id > ?", afterMessageID)
	}
	if read {
		query = query.Where("(delivered_at IS NULL OR read_at IS NULL)")
	} else {
		query = query.Where("delivered_at IS NULL")
	}
	return query.Updates(updates).Error
}

func (s *ChatService) broadcastReceipt(db *gorm.DB, eventType, userid string, conversationID, messageID uint64, payload map[string]interface{}) {
	userids, err := s.conversationMemberUserids(db, conversationID)
	if err != nil {
		return
	}
	if payload == nil {
		payload = map[string]interface{}{}
	}
	payload["userid"] = userid
	payload["messageId"] = messageID
	if message, loadErr := s.loadMessageByID(db, userid, messageID); loadErr == nil {
		payload["status"] = message.Status
		payload["receiptSummary"] = message.ReceiptSummary
		payload["totalRecipients"] = message.ReceiptSummary.TotalRecipients
		payload["deliveredCount"] = message.ReceiptSummary.DeliveredRecipients
		payload["readCount"] = message.ReceiptSummary.ReadRecipients
	}
	RealtimeHubInstance.BroadcastToUsers(userids, RealtimeEvent{Type: eventType, ConversationID: conversationID, MessageID: messageID, Userid: userid, Payload: payload})
}

func (s *ChatService) CatchUpMessages(currentUserid string, conversationID, afterMessageID, afterSequence uint64, limit int) ([]types.ChatMessage, types.ChatCatchUpCursor, bool, error) {
	db, err := s.productionDB()
	if err != nil {
		return nil, types.ChatCatchUpCursor{}, false, errors.New(ErrSystem)
	}
	if ok, checkErr := s.isConversationMember(db, conversationID, currentUserid); checkErr != nil {
		return nil, types.ChatCatchUpCursor{}, false, errors.New(ErrSystem)
	} else if !ok {
		return nil, types.ChatCatchUpCursor{}, false, errors.New(ErrChatNoPermission)
	}
	if limit <= 0 {
		limit = 100
	}
	if limit > 500 {
		limit = 500
	}
	query := baseProductionMessageQuery() + `
		WHERE m.conversation_id = ?
			AND NOT EXISTS (SELECT 1 FROM chat_message_user_deletions d WHERE d.message_id = m.id AND d.userid = ?)`
	args := []interface{}{currentUserid, conversationID, currentUserid}
	if afterSequence > 0 {
		// server_sequence is assigned from the immutable message ID. Using the
		// ID key keeps reconnect pagination indexed while also recovering rows
		// written by an old replica with a NULL server_sequence.
		query += " AND m.id > ?"
		args = append(args, afterSequence)
	} else if afterMessageID > 0 {
		query += " AND m.id > ?"
		args = append(args, afterMessageID)
	}
	query += " ORDER BY m.id ASC LIMIT ?"
	args = append(args, limit+1)
	var rows []messageRow
	if scanErr := db.Raw(query, args...).Scan(&rows).Error; scanErr != nil {
		return nil, types.ChatCatchUpCursor{}, false, errors.New(ErrSystem)
	}
	hasMore := len(rows) > limit
	if hasMore {
		rows = rows[:limit]
	}
	messages, buildErr := s.buildMessages(db, currentUserid, rows)
	if buildErr != nil {
		return nil, types.ChatCatchUpCursor{}, false, buildErr
	}
	cursor := types.ChatCatchUpCursor{AfterMessageID: afterMessageID, AfterSequence: afterSequence}
	if len(messages) > 0 {
		cursor.AfterMessageID = messages[len(messages)-1].ID
		cursor.AfterSequence = messages[len(messages)-1].ServerSequence
	}
	return messages, cursor, hasMore, nil
}

func baseProductionMessageQuery() string {
	return `SELECT m.id, m.conversation_id, m.sender_userid,
		CASE WHEN c.type = 'direct' THEN COALESCE(NULLIF(cc_sender.nickname, ''), u.fullname, m.sender_userid)
			ELSE COALESCE(NULLIF(cm_sender.nickname, ''), u.fullname, m.sender_userid) END AS sender_name,
		COALESCE(u.avatar, '') AS sender_avatar, m.message_type, COALESCE(m.content, '') AS content,
		m.reply_to_message_id, m.forwarded_from_message_id, m.created_at
		FROM chat_messages m
		JOIN chat_conversations c ON c.id = m.conversation_id
		LEFT JOIN chat_members cm_sender ON cm_sender.conversation_id = m.conversation_id AND cm_sender.userid = m.sender_userid
		LEFT JOIN chat_contacts cc_sender ON cc_sender.owner_userid = ? AND cc_sender.contact_userid = m.sender_userid
		LEFT JOIN users u ON u.userid = m.sender_userid `
}

func (s *ChatService) EditMessage(currentUserid string, messageID uint64, req request.EditChatMessageRequest) (*types.ChatMessage, error) {
	content := strings.TrimSpace(req.Content)
	if content == "" {
		return nil, errors.New(ErrChatEmptyMessage)
	}
	db, err := s.productionDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}
	var original productionMessageRecord
	if err := db.Table("chat_messages").Where("id = ?", messageID).Take(&original).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New(ErrChatMessageNotFound)
		}
		return nil, errors.New(ErrSystem)
	}
	if original.SenderUserid != currentUserid || original.MessageType == "system" || original.MessageType == "poll" {
		return nil, errors.New(ErrChatNoPermission)
	}
	if member, checkErr := s.isConversationMember(db, original.ConversationID, currentUserid); checkErr != nil {
		return nil, errors.New(ErrSystem)
	} else if !member {
		return nil, errors.New(ErrChatNoPermission)
	}
	if original.DeletedAt != nil {
		return nil, errors.New(ErrChatNoPermission)
	}
	if req.Version != nil && *req.Version != original.Version {
		return nil, errors.New(ErrChatMessageVersionConflict)
	}
	now := time.Now().UTC()
	newVersion := original.Version + 1
	err = db.Transaction(func(tx *gorm.DB) error {
		if lockErr := lockChatConversationRows(tx, original.ConversationID); lockErr != nil {
			return lockErr
		}
		snapshot, _ := json.Marshal(map[string]interface{}{
			"content":          original.Content,
			"previousContent":  original.Content,
			"newContent":       content,
			"previousEditedAt": original.EditedAt,
		})
		if auditErr := tx.Table("chat_message_audit").Create(&productionAuditRecord{MessageID: original.ID, ConversationID: original.ConversationID, ActorUserid: currentUserid, Action: "edit", PreviousVersion: original.Version, NewVersion: newVersion, SnapshotJSON: string(snapshot), CreatedAt: now}).Error; auditErr != nil {
			return auditErr
		}
		query := tx.Table("chat_messages").Where("id = ? AND sender_userid = ? AND deleted_at IS NULL AND version = ?", messageID, currentUserid, original.Version).
			Where("EXISTS (SELECT 1 FROM chat_members cm WHERE cm.conversation_id = chat_messages.conversation_id AND cm.userid = ?)", currentUserid)
		result := query.Updates(map[string]interface{}{"content": content, "edited_at": now, "version": newVersion})
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected != 1 {
			return errors.New(ErrChatMessageVersionConflict)
		}
		return nil
	})
	if err != nil {
		return nil, normalizeProductionError(err)
	}
	message, err := s.loadMessageByID(db, currentUserid, messageID)
	if err != nil {
		return nil, err
	}
	s.broadcastMessageEvent(db, "message.updated", message)
	return message, nil
}

func (s *ChatService) GetMessageEditHistory(currentUserid string, messageID uint64) ([]types.ChatMessageEditHistoryEntry, error) {
	db, err := s.productionDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}
	var message productionMessageRecord
	if err := db.Table("chat_messages").Where("id = ?", messageID).Take(&message).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New(ErrChatMessageNotFound)
		}
		return nil, errors.New(ErrSystem)
	}
	if message.DeletedAt != nil {
		return nil, errors.New(ErrChatNoPermission)
	}
	if ok, checkErr := s.isConversationMember(db, message.ConversationID, currentUserid); checkErr != nil {
		return nil, errors.New(ErrSystem)
	} else if !ok {
		return nil, errors.New(ErrChatNoPermission)
	}
	var deletionCount int64
	if err := db.Table("chat_message_user_deletions").
		Where("message_id = ? AND userid = ?", messageID, currentUserid).
		Count(&deletionCount).Error; err != nil {
		return nil, errors.New(ErrSystem)
	}
	if deletionCount > 0 {
		return nil, errors.New(ErrChatNoPermission)
	}

	var rows []editHistoryRow
	if err := db.Table("chat_message_audit AS a").
		Select(`a.id, a.message_id, a.conversation_id, a.actor_userid, a.action,
			a.previous_version, a.new_version, a.snapshot_json, a.created_at,
			COALESCE(NULLIF(cm.nickname, ''), NULLIF(u.fullname, ''), a.actor_userid) AS editor_name,
			COALESCE(u.avatar, '') AS editor_avatar`).
		Joins("LEFT JOIN chat_members cm ON cm.conversation_id = a.conversation_id AND cm.userid = a.actor_userid").
		Joins("LEFT JOIN users u ON u.userid = a.actor_userid").
		Where("a.message_id = ? AND a.action = ?", messageID, "edit").
		Order("a.id DESC").
		Limit(500).
		Scan(&rows).Error; err != nil {
		return nil, errors.New(ErrSystem)
	}
	for left, right := 0, len(rows)-1; left < right; left, right = left+1, right-1 {
		rows[left], rows[right] = rows[right], rows[left]
	}
	if len(rows) == 0 {
		return []types.ChatMessageEditHistoryEntry{}, nil
	}

	previousContents := make([]string, len(rows))
	newContents := make([]string, len(rows))
	for index, row := range rows {
		var snapshot map[string]interface{}
		if unmarshalErr := json.Unmarshal([]byte(row.SnapshotJSON), &snapshot); unmarshalErr == nil {
			previousContents[index] = firstStringValue(snapshot, "previousContent", "content")
			newContents[index] = firstStringValue(snapshot, "newContent")
		}
	}
	entries := make([]types.ChatMessageEditHistoryEntry, 0, len(rows))
	for index, row := range rows {
		content := newContents[index]
		if content == "" {
			if index+1 < len(rows) {
				content = previousContents[index+1]
			} else {
				content = message.Content
			}
		}
		entries = append(entries, types.ChatMessageEditHistoryEntry{
			AuditID:         row.ID,
			MessageID:       row.MessageID,
			PreviousVersion: row.PreviousVersion,
			Version:         row.NewVersion,
			PreviousContent: previousContents[index],
			Content:         content,
			EditorUserid:    row.ActorUserid,
			EditorName:      row.EditorName,
			EditorAvatar:    row.EditorAvatar,
			EditedAt:        row.CreatedAt,
		})
	}
	return entries, nil
}

func firstStringValue(values map[string]interface{}, keys ...string) string {
	for _, key := range keys {
		if value, ok := values[key].(string); ok {
			return value
		}
	}
	return ""
}

func (s *ChatService) RecallMessage(currentUserid string, messageID uint64) (*types.ChatMessage, error) {
	return s.RecallMessageVersion(currentUserid, messageID, nil)
}

func (s *ChatService) RecallMessageVersion(currentUserid string, messageID uint64, expectedVersion *uint) (*types.ChatMessage, error) {
	db, err := s.productionDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}
	var original productionMessageRecord
	if err := db.Table("chat_messages").Where("id = ?", messageID).Take(&original).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New(ErrChatMessageNotFound)
		}
		return nil, errors.New(ErrSystem)
	}
	if original.SenderUserid != currentUserid || original.MessageType == "system" || original.MessageType == "poll" {
		return nil, errors.New(ErrChatNoPermission)
	}
	if member, checkErr := s.isConversationMember(db, original.ConversationID, currentUserid); checkErr != nil {
		return nil, errors.New(ErrSystem)
	} else if !member {
		return nil, errors.New(ErrChatNoPermission)
	}
	if original.DeletedAt != nil {
		message, loadErr := s.loadMessageByID(db, currentUserid, messageID)
		return message, loadErr
	}
	if expectedVersion != nil && *expectedVersion != original.Version {
		return nil, errors.New(ErrChatMessageVersionConflict)
	}
	if time.Since(original.CreatedAt) > recallWindow() {
		return nil, errors.New(ErrChatRecallWindowExpired)
	}
	var attachments []productionAttachmentRecord
	if err := db.Table("chat_message_attachments").Where("message_id = ? AND deleted_at IS NULL", messageID).Find(&attachments).Error; err != nil {
		return nil, errors.New(ErrSystem)
	}
	now := time.Now().UTC()
	newVersion := original.Version + 1
	err = db.Transaction(func(tx *gorm.DB) error {
		if lockErr := lockChatConversationRows(tx, original.ConversationID); lockErr != nil {
			return lockErr
		}
		snapshot, _ := json.Marshal(map[string]interface{}{"content": original.Content, "messageType": original.MessageType, "attachments": attachments})
		if auditErr := tx.Table("chat_message_audit").Create(&productionAuditRecord{MessageID: original.ID, ConversationID: original.ConversationID, ActorUserid: currentUserid, Action: "recall", PreviousVersion: original.Version, NewVersion: newVersion, SnapshotJSON: string(snapshot), CreatedAt: now}).Error; auditErr != nil {
			return auditErr
		}
		result := tx.Table("chat_messages").Where("id = ? AND sender_userid = ? AND deleted_at IS NULL AND version = ?", messageID, currentUserid, original.Version).
			Where("EXISTS (SELECT 1 FROM chat_members cm WHERE cm.conversation_id = chat_messages.conversation_id AND cm.userid = ?)", currentUserid).
			Updates(map[string]interface{}{
				"content": "", "deleted_at": now, "deleted_by": currentUserid, "version": newVersion,
			})
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected != 1 {
			return errors.New(ErrChatMessageVersionConflict)
		}
		if updateErr := tx.Table("chat_message_attachments").Where("message_id = ? AND deleted_at IS NULL", messageID).Updates(map[string]interface{}{"deleted_at": now, "deleted_by": currentUserid}).Error; updateErr != nil {
			return updateErr
		}
		return tx.Table("chat_members").Where("conversation_id = ? AND userid <> ? AND (last_read_message_id IS NULL OR last_read_message_id < ?)", original.ConversationID, currentUserid, messageID).
			Where("NOT EXISTS (SELECT 1 FROM chat_message_user_deletions d WHERE d.message_id = ? AND d.userid = chat_members.userid)", messageID).
			UpdateColumn("unread_count", gorm.Expr("CASE WHEN unread_count > 0 THEN unread_count - 1 ELSE 0 END")).Error
	})
	if err != nil {
		return nil, normalizeProductionError(err)
	}
	for _, attachment := range attachments {
		hasLiveReference, countErr := hasLiveChatFileReference(db, attachment.FileURL)
		if countErr != nil {
			continue
		}
		if !hasLiveReference {
			if cleanupErr := cleanupLocalChatAttachment(attachment.FileURL); cleanupErr != nil {
				// Keep the ownership record as a durable signal that this claimed
				// upload still needs operator cleanup instead of losing the path.
				continue
			}
		}
		_ = db.Table("chat_pending_uploads").Where("file_url = ? AND claimed_message_id = ?", attachment.FileURL, messageID).Delete(&productionPendingUploadRecord{}).Error
	}
	message, err := s.loadMessageByID(db, currentUserid, messageID)
	if err != nil {
		return nil, err
	}
	s.broadcastMessageEvent(db, "message.recalled", message)
	return message, nil
}

func (s *ChatService) DeleteMessageForMe(currentUserid string, messageID uint64) error {
	db, err := s.productionDB()
	if err != nil {
		return errors.New(ErrSystem)
	}
	var preflight struct {
		ConversationID uint64 `gorm:"column:conversation_id"`
	}
	if takeErr := db.Table("chat_messages").Select("conversation_id").Where("id = ?", messageID).Take(&preflight).Error; takeErr != nil {
		if errors.Is(takeErr, gorm.ErrRecordNotFound) {
			return errors.New(ErrChatMessageNotFound)
		}
		return errors.New(ErrSystem)
	}
	var message productionMessageRecord
	now := time.Now().UTC()
	err = db.Transaction(func(tx *gorm.DB) error {
		if lockErr := lockChatConversationRows(tx, preflight.ConversationID); lockErr != nil {
			return lockErr
		}
		messageQuery := tx.Table("chat_messages").Where("id = ? AND conversation_id = ?", messageID, preflight.ConversationID)
		if tx.Dialector.Name() == "mysql" {
			messageQuery = messageQuery.Clauses(clause.Locking{Strength: "UPDATE"})
		}
		if takeErr := messageQuery.Take(&message).Error; takeErr != nil {
			if errors.Is(takeErr, gorm.ErrRecordNotFound) {
				return errors.New(ErrChatMessageNotFound)
			}
			return takeErr
		}
		var memberCount int64
		if countErr := tx.Table("chat_members").Where("conversation_id = ? AND userid = ?", message.ConversationID, currentUserid).Count(&memberCount).Error; countErr != nil {
			return countErr
		}
		if memberCount == 0 {
			return errors.New(ErrChatNoPermission)
		}
		deletion := productionUserDeletionRecord{MessageID: messageID, ConversationID: message.ConversationID, Userid: currentUserid, DeletedAt: now}
		result := tx.Table("chat_message_user_deletions").Clauses(clause.OnConflict{Columns: []clause.Column{{Name: "message_id"}, {Name: "userid"}}, DoNothing: true}).Create(&deletion)
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected == 0 {
			return nil
		}
		if message.SenderUserid != currentUserid && message.MessageType != "system" && message.DeletedAt == nil {
			if updateErr := tx.Table("chat_members").Where("conversation_id = ? AND userid = ? AND (last_read_message_id IS NULL OR last_read_message_id < ?)", message.ConversationID, currentUserid, messageID).
				UpdateColumn("unread_count", gorm.Expr("CASE WHEN unread_count > 0 THEN unread_count - 1 ELSE 0 END")).Error; updateErr != nil {
				return updateErr
			}
		}
		snapshot, _ := json.Marshal(map[string]interface{}{"deleteForMe": true})
		return tx.Table("chat_message_audit").Create(&productionAuditRecord{MessageID: messageID, ConversationID: message.ConversationID, ActorUserid: currentUserid, Action: "delete_for_me", PreviousVersion: message.Version, NewVersion: message.Version, SnapshotJSON: string(snapshot), CreatedAt: now}).Error
	})
	if err != nil {
		return normalizeProductionError(err)
	}
	RealtimeHubInstance.BroadcastToUsers([]string{currentUserid}, RealtimeEvent{Type: "message.deleted", ConversationID: message.ConversationID, MessageID: messageID, Payload: map[string]interface{}{"messageId": messageID, "deleteForMe": true}})
	return nil
}

func (s *ChatService) SetReaction(currentUserid string, messageID uint64, emoji string, add bool) ([]types.ChatReaction, error) {
	emoji = strings.TrimSpace(emoji)
	if emoji == "" || len([]rune(emoji)) > maxReactionRunes {
		return nil, errors.New(ErrInvalidInput)
	}
	db, err := s.productionDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}
	var preflight struct {
		ConversationID uint64 `gorm:"column:conversation_id"`
	}
	if takeErr := db.Table("chat_messages").Select("conversation_id").Where("id = ?", messageID).Take(&preflight).Error; takeErr != nil {
		if errors.Is(takeErr, gorm.ErrRecordNotFound) {
			return nil, errors.New(ErrChatMessageNotFound)
		}
		return nil, errors.New(ErrSystem)
	}
	now := time.Now().UTC()
	var message productionMessageRecord
	err = db.Transaction(func(tx *gorm.DB) error {
		if lockErr := lockChatConversationRows(tx, preflight.ConversationID); lockErr != nil {
			return lockErr
		}
		messageQuery := tx.Table("chat_messages").Where("id = ? AND conversation_id = ?", messageID, preflight.ConversationID)
		if tx.Dialector.Name() == "mysql" {
			messageQuery = messageQuery.Clauses(clause.Locking{Strength: "UPDATE"})
		}
		if takeErr := messageQuery.Take(&message).Error; takeErr != nil {
			if errors.Is(takeErr, gorm.ErrRecordNotFound) {
				return errors.New(ErrChatMessageNotFound)
			}
			return takeErr
		}
		if message.DeletedAt != nil {
			return errors.New(ErrChatNoPermission)
		}
		var member productionMemberState
		memberQuery := tx.Table("chat_members").Where("conversation_id = ? AND userid = ?", message.ConversationID, currentUserid)
		if tx.Dialector.Name() == "mysql" {
			memberQuery = memberQuery.Clauses(clause.Locking{Strength: "UPDATE"})
		}
		if takeErr := memberQuery.Take(&member).Error; takeErr != nil {
			if errors.Is(takeErr, gorm.ErrRecordNotFound) {
				return errors.New(ErrChatNoPermission)
			}
			return takeErr
		}
		if add {
			record := productionReactionRecord{MessageID: messageID, ConversationID: message.ConversationID, Userid: currentUserid, Emoji: emoji, CreatedAt: now, UpdatedAt: now}
			return tx.Table("chat_message_reactions").Clauses(clause.OnConflict{Columns: []clause.Column{{Name: "userid"}, {Name: "message_id"}, {Name: "emoji"}}, DoNothing: true}).Create(&record).Error
		}
		return tx.Table("chat_message_reactions").Where("message_id = ? AND userid = ? AND emoji = ?", messageID, currentUserid, emoji).Delete(&productionReactionRecord{}).Error
	})
	if err != nil {
		return nil, normalizeProductionError(err)
	}
	loaded, err := s.loadMessageByID(db, currentUserid, messageID)
	if err != nil {
		return nil, err
	}
	s.broadcastMessageEventWithPayload(db, "reaction.updated", loaded, map[string]interface{}{"messageId": messageID, "actorUserid": currentUserid})
	return loaded.Reactions, nil
}

func (s *ChatService) UpdateConversationUserSettings(currentUserid string, conversationID uint64, req request.UpdateConversationUserSettingsRequest) (*types.ChatConversationUserSettings, error) {
	updates := map[string]interface{}{}
	if req.MuteUntil.Set {
		updates["mute_until"] = req.MuteUntil.Value
	}
	if req.PinnedAt.Set {
		updates["pinned_at"] = req.PinnedAt.Value
	}
	if req.ArchivedAt.Set {
		updates["archived_at"] = req.ArchivedAt.Value
	}
	if len(updates) == 0 {
		return nil, errors.New(ErrInvalidInput)
	}
	db, err := s.productionDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}
	result := db.Table("chat_members").Where("conversation_id = ? AND userid = ?", conversationID, currentUserid).Updates(updates)
	if result.Error != nil {
		return nil, errors.New(ErrSystem)
	}
	if result.RowsAffected == 0 {
		if ok, _ := s.isConversationMember(db, conversationID, currentUserid); !ok {
			return nil, errors.New(ErrChatNoPermission)
		}
	}
	var member productionMemberState
	if err := db.Table("chat_members").Where("conversation_id = ? AND userid = ?", conversationID, currentUserid).Take(&member).Error; err != nil {
		return nil, errors.New(ErrSystem)
	}
	settings := &types.ChatConversationUserSettings{ConversationID: conversationID, Userid: currentUserid, MuteUntil: member.MuteUntil, PinnedAt: member.PinnedAt, ArchivedAt: member.ArchivedAt}
	RealtimeHubInstance.BroadcastToUsers([]string{currentUserid}, RealtimeEvent{Type: "conversation.settings.updated", ConversationID: conversationID, Payload: map[string]interface{}{"settings": settings}})
	return settings, nil
}

func (s *ChatService) SetTyping(currentUserid string, conversationID uint64, isTyping bool) error {
	db, err := s.productionDB()
	if err != nil {
		return errors.New(ErrSystem)
	}
	if ok, checkErr := s.isConversationMember(db, conversationID, currentUserid); checkErr != nil {
		return errors.New(ErrSystem)
	} else if !ok {
		return errors.New(ErrChatNoPermission)
	}
	userids, err := s.conversationMemberUserids(db, conversationID)
	if err != nil {
		return errors.New(ErrSystem)
	}
	recipients := make([]string, 0, len(userids))
	for _, userid := range userids {
		if userid != currentUserid {
			recipients = append(recipients, userid)
		}
	}
	RealtimeHubInstance.PublishTyping(currentUserid, conversationID, isTyping, recipients)
	return nil
}

func (s *ChatService) SetPinnedMessage(currentUserid string, conversationID, messageID uint64) (*types.ChatPinnedMessageState, error) {
	if messageID == 0 {
		return s.updatePinnedMessageList(currentUserid, conversationID, 0, false)
	}
	return s.updatePinnedMessageList(currentUserid, conversationID, messageID, true)

	// Legacy single-pin implementation is intentionally retained below as
	// unreachable migration context for older deployments.
	db, err := s.productionDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}

	type pinRecord struct {
		PinnedMessageID *uint64    `gorm:"column:pinned_message_id"`
		PinnedBy        string     `gorm:"column:message_pinned_by"`
		PinnedAt        *time.Time `gorm:"column:message_pinned_at"`
	}

	var previousMessageID uint64
	var systemMessageID uint64
	var resulting pinRecord
	changed := false
	now := time.Now().UTC()
	err = db.Transaction(func(tx *gorm.DB) error {
		if lockErr := lockChatConversationRows(tx, conversationID); lockErr != nil {
			return lockErr
		}
		isMember, memberErr := s.isConversationMember(tx, conversationID, currentUserid)
		if memberErr != nil {
			return memberErr
		}
		if !isMember {
			return errors.New(ErrChatNoPermission)
		}

		var existing pinRecord
		if takeErr := tx.Table("chat_conversations").
			Select("pinned_message_id, COALESCE(message_pinned_by, '') AS message_pinned_by, message_pinned_at").
			Where("id = ?", conversationID).
			Take(&existing).Error; takeErr != nil {
			return takeErr
		}
		if existing.PinnedMessageID != nil {
			previousMessageID = *existing.PinnedMessageID
		}

		if messageID > 0 {
			accessible, accessErr := s.messageInConversation(tx, currentUserid, conversationID, messageID)
			if accessErr != nil {
				return accessErr
			}
			if !accessible {
				return errors.New(ErrChatMessageNotFound)
			}
		}

		if previousMessageID == messageID {
			resulting = existing
			return nil
		}

		updates := map[string]interface{}{
			"pinned_message_id": nil,
			"message_pinned_by": nil,
			"message_pinned_at": nil,
			"updated_at":        now,
		}
		if messageID > 0 {
			updates["pinned_message_id"] = messageID
			updates["message_pinned_by"] = currentUserid
			updates["message_pinned_at"] = now
			pinnedID := messageID
			resulting = pinRecord{PinnedMessageID: &pinnedID, PinnedBy: currentUserid, PinnedAt: &now}
		} else {
			resulting = pinRecord{}
		}
		if updateErr := tx.Table("chat_conversations").Where("id = ?", conversationID).Updates(updates).Error; updateErr != nil {
			return updateErr
		}

		auditMessageID := messageID
		action := "pin"
		if messageID == 0 {
			auditMessageID = previousMessageID
			action = "unpin"
		}
		snapshot, _ := json.Marshal(map[string]interface{}{
			"previousPinnedMessageId": previousMessageID,
			"pinnedMessageId":         messageID,
		})
		if auditMessageID > 0 {
			if auditErr := tx.Table("chat_message_audit").Create(&productionAuditRecord{
				MessageID: auditMessageID, ConversationID: conversationID, ActorUserid: currentUserid,
				Action: action, PreviousVersion: 1, NewVersion: 1, SnapshotJSON: string(snapshot), CreatedAt: now,
			}).Error; auditErr != nil {
				return auditErr
			}
		}
		actorName, actorNameErr := s.conversationUserDisplayName(tx, conversationID, currentUserid)
		if actorNameErr != nil {
			return actorNameErr
		}
		systemContent := actorName + " đã ghim một tin nhắn"
		if messageID == 0 {
			systemContent = actorName + " đã bỏ ghim tin nhắn"
		}
		var createErr error
		systemMessageID, createErr = s.createSystemMessage(tx, conversationID, currentUserid, systemContent, now)
		if createErr != nil {
			return createErr
		}
		changed = true
		return nil
	})
	if err != nil {
		return nil, normalizeProductionError(err)
	}

	actorName, nameErr := s.userDisplayName(db, currentUserid)
	if nameErr != nil || strings.TrimSpace(actorName) == "" {
		actorName = currentUserid
	}
	state := &types.ChatPinnedMessageState{
		ConversationID: conversationID,
		PinnedBy:       resulting.PinnedBy,
		PinnedAt:       resulting.PinnedAt,
		ActorUserid:    currentUserid,
		ActorName:      actorName,
	}
	if resulting.PinnedBy != "" {
		pinnedByName, pinnedNameErr := s.userDisplayName(db, resulting.PinnedBy)
		if pinnedNameErr != nil || strings.TrimSpace(pinnedByName) == "" {
			pinnedByName = resulting.PinnedBy
		}
		state.PinnedByName = pinnedByName
	}
	if resulting.PinnedMessageID != nil && *resulting.PinnedMessageID > 0 {
		references, referenceErr := s.loadMessageReferences(db, currentUserid, []uint64{*resulting.PinnedMessageID})
		if referenceErr != nil {
			return nil, errors.New(ErrSystem)
		}
		state.PinnedMessage = references[*resulting.PinnedMessageID]
	}
	if systemMessageID > 0 {
		systemMessage, systemMessageErr := s.loadMessageByID(db, currentUserid, systemMessageID)
		if systemMessageErr != nil {
			return nil, systemMessageErr
		}
		state.SystemMessage = systemMessage
	}

	if changed {
		recipients, recipientsErr := s.conversationMemberUserids(db, conversationID)
		if recipientsErr == nil {
			eventType := "message.pinned"
			eventMessageID := messageID
			if messageID == 0 {
				eventType = "message.unpinned"
				eventMessageID = previousMessageID
			}
			for _, recipient := range recipients {
				var pinnedMessage *types.ChatMessageReference
				if resulting.PinnedMessageID != nil && *resulting.PinnedMessageID > 0 {
					references, referenceErr := s.loadMessageReferences(db, recipient, []uint64{*resulting.PinnedMessageID})
					if referenceErr != nil {
						continue
					}
					pinnedMessage = references[*resulting.PinnedMessageID]
				}
				RealtimeHubInstance.BroadcastToUsers([]string{recipient}, RealtimeEvent{
					Type: eventType, ConversationID: conversationID, MessageID: eventMessageID, Userid: currentUserid,
					Payload: map[string]interface{}{
						"conversationId": conversationID,
						"pinnedMessage":  pinnedMessage,
						"pinnedBy":       state.PinnedBy,
						"pinnedByName":   state.PinnedByName,
						"pinnedAt":       state.PinnedAt,
						"actorUserid":    state.ActorUserid,
						"actorName":      state.ActorName,
					},
				})
			}
		}
	}
	if state.SystemMessage != nil {
		s.broadcastMessageCreated(db, conversationID, state.SystemMessage)
	}
	return state, nil
}

func (s *ChatService) RemovePinnedMessage(currentUserid string, conversationID, messageID uint64) (*types.ChatPinnedMessageState, error) {
	return s.updatePinnedMessageList(currentUserid, conversationID, messageID, false)
}

func (s *ChatService) updatePinnedMessageList(currentUserid string, conversationID, messageID uint64, pinned bool) (*types.ChatPinnedMessageState, error) {
	db, err := s.productionDB()
	if err != nil {
		return nil, errors.New(ErrSystem)
	}
	now := time.Now().UTC()
	changed := false
	var affectedMessageID uint64
	var systemMessageID uint64

	err = db.Transaction(func(tx *gorm.DB) error {
		if err := lockChatConversationRows(tx, conversationID); err != nil {
			return err
		}
		isMember, err := s.isConversationMember(tx, conversationID, currentUserid)
		if err != nil {
			return err
		}
		if !isMember {
			return errors.New(ErrChatNoPermission)
		}

		if pinned {
			accessible, err := s.messageInConversation(tx, currentUserid, conversationID, messageID)
			if err != nil {
				return err
			}
			if !accessible {
				return errors.New(ErrChatMessageNotFound)
			}
			var count int64
			if err := tx.Table("chat_pinned_messages").Where("conversation_id = ? AND message_id = ?", conversationID, messageID).Count(&count).Error; err != nil {
				return err
			}
			if count == 0 {
				record := chatPinnedMessageRecord{ConversationID: conversationID, MessageID: messageID, PinnedBy: currentUserid, PinnedAt: now}
				if err := tx.Table("chat_pinned_messages").Create(&record).Error; err != nil {
					return err
				}
				changed = true
			}
			affectedMessageID = messageID
		} else {
			if messageID == 0 {
				var latest chatPinnedMessageRecord
				if err := tx.Table("chat_pinned_messages").Where("conversation_id = ?", conversationID).Order("pinned_at DESC, id DESC").Take(&latest).Error; err != nil {
					if errors.Is(err, gorm.ErrRecordNotFound) {
						return nil
					}
					return err
				}
				messageID = latest.MessageID
			}
			result := tx.Table("chat_pinned_messages").Where("conversation_id = ? AND message_id = ?", conversationID, messageID).Delete(&chatPinnedMessageRecord{})
			if result.Error != nil {
				return result.Error
			}
			changed = result.RowsAffected > 0
			affectedMessageID = messageID
		}

		if !changed {
			return nil
		}
		updates := map[string]interface{}{
			"pinned_message_id": nil,
			"message_pinned_by": nil,
			"message_pinned_at": nil,
			"updated_at":        now,
		}
		var latest chatPinnedMessageRecord
		if err := tx.Table("chat_pinned_messages").Where("conversation_id = ?", conversationID).Order("pinned_at DESC, id DESC").Take(&latest).Error; err == nil {
			updates["pinned_message_id"] = latest.MessageID
			updates["message_pinned_by"] = latest.PinnedBy
			updates["message_pinned_at"] = latest.PinnedAt
		} else if !errors.Is(err, gorm.ErrRecordNotFound) {
			return err
		}
		if err := tx.Table("chat_conversations").Where("id = ?", conversationID).Updates(updates).Error; err != nil {
			return err
		}

		action := "pin"
		if !pinned {
			action = "unpin"
		}
		snapshot, _ := json.Marshal(map[string]interface{}{"messageId": affectedMessageID, "pinned": pinned})
		if err := tx.Table("chat_message_audit").Create(&productionAuditRecord{
			MessageID: affectedMessageID, ConversationID: conversationID, ActorUserid: currentUserid,
			Action: action, PreviousVersion: 1, NewVersion: 1, SnapshotJSON: string(snapshot), CreatedAt: now,
		}).Error; err != nil {
			return err
		}
		actorName, err := s.conversationUserDisplayName(tx, conversationID, currentUserid)
		if err != nil {
			return err
		}
		content := actorName + " đã ghim một tin nhắn"
		if !pinned {
			content = actorName + " đã bỏ ghim tin nhắn"
		}
		systemMessageID, err = s.createSystemMessage(tx, conversationID, currentUserid, content, now)
		return err
	})
	if err != nil {
		return nil, normalizeProductionError(err)
	}

	state, err := s.loadPinnedMessageState(db, currentUserid, conversationID)
	if err != nil {
		return nil, errors.New(ErrSystem)
	}
	state.ActorUserid = currentUserid
	state.ActorName, _ = s.userDisplayName(db, currentUserid)
	if state.ActorName == "" {
		state.ActorName = currentUserid
	}
	if systemMessageID > 0 {
		state.SystemMessage, err = s.loadMessageByID(db, currentUserid, systemMessageID)
		if err != nil {
			return nil, err
		}
	}

	if changed {
		recipients, _ := s.conversationMemberUserids(db, conversationID)
		eventType := "message.pinned"
		if !pinned {
			eventType = "message.unpinned"
		}
		for _, recipient := range recipients {
			recipientState, loadErr := s.loadPinnedMessageState(db, recipient, conversationID)
			if loadErr != nil {
				continue
			}
			recipientState.ActorUserid = state.ActorUserid
			recipientState.ActorName = state.ActorName
			RealtimeHubInstance.BroadcastToUsers([]string{recipient}, RealtimeEvent{
				Type: eventType, ConversationID: conversationID, MessageID: affectedMessageID,
				Userid: currentUserid, Payload: recipientState,
			})
		}
	}
	if state.SystemMessage != nil {
		s.broadcastMessageCreated(db, conversationID, state.SystemMessage)
	}
	return state, nil
}

func (s *ChatService) loadPinnedMessageState(db *gorm.DB, currentUserid string, conversationID uint64) (*types.ChatPinnedMessageState, error) {
	var pins []chatPinnedMessageRecord
	if err := db.Table("chat_pinned_messages").Where("conversation_id = ?", conversationID).Order("pinned_at DESC, id DESC").Find(&pins).Error; err != nil {
		return nil, err
	}
	state := &types.ChatPinnedMessageState{
		ConversationID: conversationID,
		PinnedMessages: []*types.ChatMessageReference{},
		PinnedCount:    len(pins),
	}
	ids := make([]uint64, 0, len(pins))
	for _, pin := range pins {
		ids = append(ids, pin.MessageID)
	}
	references, err := s.loadMessageReferences(db, currentUserid, ids)
	if err != nil {
		return nil, err
	}
	var latestVisiblePin *chatPinnedMessageRecord
	for _, pin := range pins {
		if reference := references[pin.MessageID]; reference != nil {
			state.PinnedMessages = append(state.PinnedMessages, reference)
			if latestVisiblePin == nil {
				pinCopy := pin
				latestVisiblePin = &pinCopy
			}
		}
	}
	state.PinnedCount = len(state.PinnedMessages)
	if len(state.PinnedMessages) > 0 && latestVisiblePin != nil {
		state.PinnedMessage = state.PinnedMessages[0]
		state.PinnedBy = latestVisiblePin.PinnedBy
		state.PinnedAt = &latestVisiblePin.PinnedAt
		state.PinnedByName, _ = s.userDisplayName(db, latestVisiblePin.PinnedBy)
		if state.PinnedByName == "" {
			state.PinnedByName = latestVisiblePin.PinnedBy
		}
	}
	return state, nil
}

func (s *ChatService) SearchConversationMessages(currentUserid string, conversationID uint64, filter request.SearchConversationMessagesRequest) ([]types.ChatMessage, uint64, bool, error) {
	db, err := s.productionDB()
	if err != nil {
		return nil, 0, false, errors.New(ErrSystem)
	}
	if ok, checkErr := s.isConversationMember(db, conversationID, currentUserid); checkErr != nil {
		return nil, 0, false, errors.New(ErrSystem)
	} else if !ok {
		return nil, 0, false, errors.New(ErrChatNoPermission)
	}
	limit := filter.Limit
	if limit <= 0 {
		limit = 50
	}
	if limit > 100 {
		limit = 100
	}
	attachmentPredicate, attachmentArg, hasAttachmentFilter := normalizeAttachmentFilter(filter.AttachmentType)
	if !hasAttachmentFilter && strings.TrimSpace(filter.AttachmentType) != "" {
		return nil, 0, false, errors.New(ErrInvalidInput)
	}
	query := baseProductionMessageQuery() + ` WHERE m.conversation_id = ? AND m.deleted_at IS NULL
		AND NOT EXISTS (SELECT 1 FROM chat_message_user_deletions d WHERE d.message_id = m.id AND d.userid = ?)`
	args := []interface{}{currentUserid, conversationID, currentUserid}
	keyword := strings.TrimSpace(filter.Keyword)
	if keyword != "" {
		if db.Dialector.Name() == "mysql" {
			booleanQuery := mysqlBooleanSearch(keyword)
			if booleanQuery == "" {
				return []types.ChatMessage{}, 0, false, nil
			}
			query += ` AND (MATCH(m.content) AGAINST (? IN BOOLEAN MODE) OR EXISTS (
				SELECT 1 FROM chat_message_attachments ax WHERE ax.message_id = m.id AND ax.deleted_at IS NULL
				AND MATCH(ax.file_name, ax.relative_path) AGAINST (? IN BOOLEAN MODE)))`
			args = append(args, booleanQuery, booleanQuery)
		} else {
			like := "%" + keyword + "%"
			query += ` AND (m.content LIKE ? OR EXISTS (SELECT 1 FROM chat_message_attachments ax WHERE ax.message_id = m.id AND ax.deleted_at IS NULL AND (ax.file_name LIKE ? OR ax.relative_path LIKE ?)))`
			args = append(args, like, like, like)
		}
	}
	if sender := strings.TrimSpace(filter.SenderUserid); sender != "" {
		query += " AND m.sender_userid = ?"
		args = append(args, sender)
	}
	if filter.From != nil {
		query += " AND m.created_at >= ?"
		args = append(args, *filter.From)
	}
	if filter.To != nil {
		query += " AND m.created_at <= ?"
		args = append(args, *filter.To)
	}
	if filter.BeforeID > 0 {
		query += " AND m.id < ?"
		args = append(args, filter.BeforeID)
	}
	if hasAttachmentFilter {
		// m is already constrained by conversation and the keyset cursor. The
		// message_id probe avoids materializing a global DISTINCT attachment set,
		// especially for attachmentType=any.
		query += " AND EXISTS (SELECT 1 FROM chat_message_attachments af WHERE af.message_id = m.id AND af.deleted_at IS NULL AND " + attachmentPredicate + ")"
		args = append(args, attachmentArg)
	}
	query += " ORDER BY m.id DESC LIMIT ?"
	args = append(args, limit+1)
	var rows []messageRow
	if err := db.Raw(query, args...).Scan(&rows).Error; err != nil {
		return nil, 0, false, errors.New(ErrSystem)
	}
	hasMore := len(rows) > limit
	if hasMore {
		rows = rows[:limit]
	}
	messages, err := s.buildMessages(db, currentUserid, rows)
	if err != nil {
		return nil, 0, false, err
	}
	next := uint64(0)
	if len(messages) > 0 {
		next = messages[len(messages)-1].ID
	}
	return messages, next, hasMore, nil
}

func mysqlBooleanSearch(keyword string) string {
	parts := strings.FieldsFunc(keyword, func(r rune) bool {
		return !unicode.IsLetter(r) && !unicode.IsNumber(r)
	})
	terms := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part != "" {
			terms = append(terms, "+"+part+"*")
		}
		if len(terms) == 8 {
			break
		}
	}
	return strings.Join(terms, " ")
}

func normalizeAttachmentFilter(value string) (string, interface{}, bool) {
	normalized := strings.ToLower(strings.TrimSpace(value))
	switch normalized {
	case "image", "images":
		return "af.mime_type LIKE ?", "image/%", true
	case "video", "videos":
		return "af.mime_type LIKE ?", "video/%", true
	case "audio", "voice":
		return "af.mime_type LIKE ?", "audio/%", true
	case "document", "documents":
		return "(af.mime_type LIKE ?)", "application/%", true
	case "pdf":
		return "af.mime_type = ?", "application/pdf", true
	case "archive", "archives":
		return "af.mime_type IN ?", []string{"application/zip", "application/x-rar-compressed", "application/x-7z-compressed"}, true
	case "file", "files", "any":
		return "af.id > ?", 0, true
	default:
		if strings.Contains(normalized, "/") && len(normalized) <= 160 {
			return "af.mime_type = ?", normalized, true
		}
		return "", "", false
	}
}

func (s *ChatService) enrichMessages(db *gorm.DB, currentUserid string, messages []types.ChatMessage) error {
	if len(messages) == 0 {
		return nil
	}
	ids := make([]uint64, 0, len(messages))
	messageByID := make(map[uint64]*types.ChatMessage, len(messages))
	conversationIDs := make([]uint64, 0)
	seenConversations := map[uint64]bool{}
	for index := range messages {
		ids = append(ids, messages[index].ID)
		messageByID[messages[index].ID] = &messages[index]
		messages[index].Version = 1
		messages[index].Status = "sent"
		if messages[index].Attachments == nil {
			messages[index].Attachments = []types.ChatAttachment{}
		}
		messages[index].Receipts = []types.ChatMessageReceipt{}
		messages[index].Reactions = []types.ChatReaction{}
		recallUntil := messages[index].CreatedAt.Add(recallWindow())
		messages[index].RecallUntil = &recallUntil
		messages[index].CanRecall = messages[index].SenderUserid == currentUserid && messages[index].Type != "system" && messages[index].Type != "poll" && time.Now().Before(recallUntil)
		if !seenConversations[messages[index].ConversationID] {
			seenConversations[messages[index].ConversationID] = true
			conversationIDs = append(conversationIDs, messages[index].ConversationID)
		}
	}
	var metadata []messageProductionMetadata
	if err := db.Raw(`SELECT id, COALESCE(client_message_id, '') AS client_message_id,
		COALESCE(NULLIF(server_sequence, 0), id) AS server_sequence, COALESCE(version, 1) AS version,
		edited_at, deleted_at, COALESCE(deleted_by, '') AS deleted_by FROM chat_messages WHERE id IN ?`, ids).Scan(&metadata).Error; err != nil {
		return err
	}
	for _, row := range metadata {
		message := messageByID[row.ID]
		if message == nil {
			continue
		}
		message.ClientMessageID, message.ServerSequence, message.Version = row.ClientMessageID, row.ServerSequence, row.Version
		message.EditedAt, message.DeletedAt, message.DeletedBy = row.EditedAt, row.DeletedAt, row.DeletedBy
		if message.Version == 0 {
			message.Version = 1
		}
		if message.ServerSequence == 0 {
			message.ServerSequence = message.ID
		}
		if row.DeletedAt != nil {
			message.IsRecalled = true
			message.CanRecall = false
			message.Content = ""
			message.Attachments = []types.ChatAttachment{}
			message.Poll = nil
			message.ReplyTo = nil
			message.ForwardedFrom = nil
			message.Reactions = []types.ChatReaction{}
		}
	}
	var activeMemberRows []struct {
		ConversationID uint64 `gorm:"column:conversation_id"`
		Userid         string `gorm:"column:userid"`
	}
	if err := db.Table("chat_members").Select("conversation_id, userid").Where("conversation_id IN ?", conversationIDs).Scan(&activeMemberRows).Error; err != nil {
		return err
	}
	activeMembers := map[uint64][]string{}
	for _, row := range activeMemberRows {
		activeMembers[row.ConversationID] = append(activeMembers[row.ConversationID], row.Userid)
	}
	var receipts []receiptDisplayRow
	if err := db.Raw(`SELECT r.message_id, r.userid, COALESCE(u.fullname, r.userid) AS fullname, COALESCE(u.avatar, '') AS avatar, r.delivered_at, r.read_at
		FROM chat_message_receipts r LEFT JOIN users u ON u.userid = r.userid WHERE r.message_id IN ? ORDER BY r.message_id, r.id`, ids).Scan(&receipts).Error; err != nil {
		return err
	}
	totalByMessage := map[uint64]int{}
	for _, row := range receipts {
		message := messageByID[row.MessageID]
		if message == nil {
			continue
		}
		totalByMessage[row.MessageID]++
		message.Receipts = append(message.Receipts, types.ChatMessageReceipt{Userid: row.Userid, Fullname: row.Fullname, Avatar: row.Avatar, DeliveredAt: row.DeliveredAt, ReadAt: row.ReadAt})
		if row.DeliveredAt != nil {
			message.ReceiptSummary.DeliveredRecipients++
		}
		if row.ReadAt != nil {
			message.ReceiptSummary.ReadRecipients++
		}
	}
	var reactionRows []reactionDisplayRow
	if err := db.Table("chat_message_reactions AS r").
		Select(`r.message_id, r.userid, r.emoji, r.updated_at,
			COALESCE(NULLIF(cm.nickname, ''), NULLIF(u.fullname, ''), r.userid) AS fullname,
			COALESCE(u.avatar, '') AS avatar`).
		Joins("LEFT JOIN chat_members cm ON cm.conversation_id = r.conversation_id AND cm.userid = r.userid").
		Joins("LEFT JOIN users u ON u.userid = r.userid").
		Where("r.message_id IN ?", ids).
		Order("r.message_id, r.emoji, r.id").
		Scan(&reactionRows).Error; err != nil {
		return err
	}
	type reactionKey struct {
		messageID uint64
		emoji     string
	}
	reactionIndex := map[reactionKey]int{}
	for _, row := range reactionRows {
		message := messageByID[row.MessageID]
		if message == nil || message.IsRecalled {
			continue
		}
		key := reactionKey{row.MessageID, row.Emoji}
		position, exists := reactionIndex[key]
		if !exists {
			message.Reactions = append(message.Reactions, types.ChatReaction{Emoji: row.Emoji, Userids: []string{}, Users: []types.ChatReactionUser{}, UpdatedAt: row.UpdatedAt})
			position = len(message.Reactions) - 1
			reactionIndex[key] = position
		}
		reaction := &message.Reactions[position]
		reaction.Count++
		reaction.Userids = append(reaction.Userids, row.Userid)
		reaction.Users = append(reaction.Users, types.ChatReactionUser{Userid: row.Userid, Fullname: row.Fullname, Avatar: row.Avatar})
		if row.Userid == currentUserid {
			reaction.ReactedByMe = true
		}
		if row.UpdatedAt.After(reaction.UpdatedAt) {
			reaction.UpdatedAt = row.UpdatedAt
		}
	}
	for index := range messages {
		total := totalByMessage[messages[index].ID]
		if total == 0 && messages[index].ClientMessageID == "" {
			for _, userid := range activeMembers[messages[index].ConversationID] {
				if userid != messages[index].SenderUserid {
					total++
				}
			}
		}
		messages[index].ReceiptSummary.TotalRecipients = total
		if total > 0 && messages[index].ReceiptSummary.ReadRecipients >= total {
			messages[index].Status = "read"
		} else if total > 0 && messages[index].ReceiptSummary.DeliveredRecipients >= total {
			messages[index].Status = "delivered"
		}
	}
	return nil
}

func (s *ChatService) enrichConversations(db *gorm.DB, currentUserid string, conversations []types.ChatConversation) error {
	if len(conversations) == 0 {
		return nil
	}
	ids := make([]uint64, 0, len(conversations))
	indexByID := map[uint64]int{}
	for index := range conversations {
		ids = append(ids, conversations[index].ID)
		indexByID[conversations[index].ID] = index
	}
	var states []productionMemberState
	if err := db.Table("chat_members").Where("userid = ? AND conversation_id IN ?", currentUserid, ids).Scan(&states).Error; err != nil {
		return err
	}
	for _, state := range states {
		index, ok := indexByID[state.ConversationID]
		if !ok {
			continue
		}
		conversation := &conversations[index]
		conversation.LastReadMessageID, conversation.LastReadAt, conversation.UnreadCount = state.LastReadMessageID, state.LastReadAt, state.UnreadCount
		conversation.MuteUntil, conversation.PinnedAt, conversation.ArchivedAt = state.MuteUntil, state.PinnedAt, state.ArchivedAt
	}
	lastMessages := make([]types.ChatMessage, 0, len(conversations))
	for index := range conversations {
		if conversations[index].LastMessage != nil {
			lastMessages = append(lastMessages, *conversations[index].LastMessage)
		}
	}
	if err := s.enrichMessages(db, currentUserid, lastMessages); err != nil {
		return err
	}
	lastByConversation := map[uint64]types.ChatMessage{}
	for _, message := range lastMessages {
		lastByConversation[message.ConversationID] = message
	}
	for index := range conversations {
		if message, ok := lastByConversation[conversations[index].ID]; ok {
			copy := message
			conversations[index].LastMessage = &copy
		}
	}
	sort.SliceStable(conversations, func(i, j int) bool {
		if (conversations[i].PinnedAt != nil) != (conversations[j].PinnedAt != nil) {
			return conversations[i].PinnedAt != nil
		}
		if conversations[i].PinnedAt != nil && conversations[j].PinnedAt != nil && !conversations[i].PinnedAt.Equal(*conversations[j].PinnedAt) {
			return conversations[i].PinnedAt.After(*conversations[j].PinnedAt)
		}
		return false
	})
	return nil
}

func (s *ChatService) broadcastMessageEvent(db *gorm.DB, eventType string, message *types.ChatMessage) {
	s.broadcastMessageEventWithPayload(db, eventType, message, map[string]interface{}{"message": message})
}

func (s *ChatService) broadcastMessageEventWithPayload(db *gorm.DB, eventType string, message *types.ChatMessage, payload map[string]interface{}) {
	if message == nil {
		return
	}
	userids, err := s.conversationMemberUserids(db, message.ConversationID)
	if err != nil {
		return
	}
	for _, userid := range userids {
		personalized, loadErr := s.loadMessageByID(db, userid, message.ID)
		if loadErr != nil {
			continue
		}
		personalizedPayload := make(map[string]interface{}, len(payload)+2)
		for key, value := range payload {
			personalizedPayload[key] = value
		}
		personalizedPayload["message"] = personalized
		if eventType == "reaction.updated" {
			personalizedPayload["reactions"] = personalized.Reactions
		}
		RealtimeHubInstance.BroadcastToUsers([]string{userid}, RealtimeEvent{Type: eventType, ConversationID: message.ConversationID, MessageID: message.ID, Message: personalized, Payload: personalizedPayload})
	}
}

func recallWindow() time.Duration {
	if configuration := config.GetConfig(); configuration != nil && configuration.Chat.RecallWindowSeconds > 0 {
		return time.Duration(configuration.Chat.RecallWindowSeconds) * time.Second
	}
	return defaultRecallWindow
}

func hasLiveChatFileReference(db *gorm.DB, fileURL string) (bool, error) {
	var attachmentReferences int64
	if err := db.Table("chat_message_attachments").Where("file_url = ? AND deleted_at IS NULL", fileURL).Count(&attachmentReferences).Error; err != nil {
		return false, err
	}
	if attachmentReferences > 0 {
		return true, nil
	}
	var conversationReferences int64
	if err := db.Table("chat_conversations").Where("avatar = ? OR background = ?", fileURL, fileURL).Count(&conversationReferences).Error; err != nil {
		return false, err
	}
	return conversationReferences > 0, nil
}

func localChatAttachmentPath(fileURL string) (string, error) {
	value := strings.TrimSpace(fileURL)
	if value == "" || strings.ContainsAny(value, "?#\\") || !strings.HasPrefix(value, "/uploads/chat/") {
		return "", errors.New(ErrInvalidInput)
	}
	relativeValue := strings.TrimPrefix(value, "/")
	root, err := filepath.Abs(filepath.Join("uploads", "chat"))
	if err != nil {
		return "", err
	}
	target, err := filepath.Abs(filepath.Clean(filepath.FromSlash(relativeValue)))
	if err != nil {
		return "", err
	}
	relative, err := filepath.Rel(root, target)
	if err != nil || relative == "." || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return "", errors.New(ErrInvalidInput)
	}
	resolvedRoot := root
	if resolved, resolveErr := filepath.EvalSymlinks(root); resolveErr == nil {
		resolvedRoot = resolved
	} else if !errors.Is(resolveErr, os.ErrNotExist) {
		return "", resolveErr
	}
	resolvedTarget := target
	if resolved, resolveErr := filepath.EvalSymlinks(target); resolveErr == nil {
		resolvedTarget = resolved
	} else if !errors.Is(resolveErr, os.ErrNotExist) {
		return "", resolveErr
	} else if resolvedParent, parentErr := filepath.EvalSymlinks(filepath.Dir(target)); parentErr == nil {
		resolvedTarget = filepath.Join(resolvedParent, filepath.Base(target))
	} else if !errors.Is(parentErr, os.ErrNotExist) {
		return "", parentErr
	}
	resolvedRelative, err := filepath.Rel(resolvedRoot, resolvedTarget)
	if err != nil || resolvedRelative == "." || resolvedRelative == ".." || strings.HasPrefix(resolvedRelative, ".."+string(filepath.Separator)) {
		return "", errors.New(ErrInvalidInput)
	}
	return target, nil
}

func cleanupLocalChatAttachment(fileURL string) error {
	target, err := localChatAttachmentPath(fileURL)
	if err != nil {
		return err
	}
	if err := os.Remove(target); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}

func normalizeProductionError(err error) error {
	if err == nil {
		return nil
	}
	switch err.Error() {
	case ErrChatConversationNotFound, ErrChatNoPermission, ErrChatMessageNotFound, ErrChatMessageVersionConflict, ErrChatClientMessageIDConflict, ErrChatRecallWindowExpired:
		return err
	default:
		return errors.New(ErrSystem)
	}
}

func coalesceTime(value *time.Time, fallback time.Time) time.Time {
	if value != nil {
		return *value
	}
	return fallback
}
