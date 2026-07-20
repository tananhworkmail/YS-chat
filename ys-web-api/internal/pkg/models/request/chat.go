package request

import (
	"bytes"
	"encoding/json"
	"time"
)

type CreateDirectConversationRequest struct {
	Userid string `json:"userid" binding:"required"`
}

type CreateGroupConversationRequest struct {
	Name          string   `json:"name" binding:"required"`
	MemberUserids []string `json:"memberUserids"`
}

type AddConversationMembersRequest struct {
	Userids []string `json:"userids" binding:"required"`
}

type UpdateConversationMemberNicknameRequest struct {
	Nickname string `json:"nickname"`
}

type UpdateConversationSettingsRequest struct {
	Avatar     string `json:"avatar"`
	Background string `json:"background"`
}

type AddContactRequest struct {
	Userid string `json:"userid" binding:"required"`
}

type UpdateContactNicknameRequest struct {
	Nickname string `json:"nickname"`
}

type RegisterDeviceTokenRequest struct {
	Token    string `json:"token" binding:"required"`
	Platform string `json:"platform"`
	DeviceID string `json:"deviceId" binding:"required"`
}

type UnregisterDeviceTokenRequest struct {
	Token    string `json:"token"`
	DeviceID string `json:"deviceId" binding:"required"`
}

type SendCallEventRequest struct {
	Type           string `json:"type" binding:"required"`
	ConversationID uint64 `json:"conversationId" binding:"required"`
	CallID         string `json:"callId" binding:"required"`
	DeviceID       string `json:"deviceId" binding:"required"`
	MediaType      string `json:"mediaType"`
	Token          string `json:"token"`
}

type SendChatMessageRequest struct {
	ClientMessageID        string                `json:"clientMessageId"`
	Type                   string                `json:"type" binding:"required"`
	Content                string                `json:"content"`
	ReplyToMessageID       uint64                `json:"replyToMessageId"`
	ForwardedFromMessageID uint64                `json:"forwardedFromMessageId"`
	Attachments            []ChatAttachmentInput `json:"attachments"`
}

type MarkConversationReadRequest struct {
	LastReadMessageID uint64 `json:"lastReadMessageId" binding:"required"`
}

type MarkConversationDeliveredRequest struct {
	MessageID uint64 `json:"messageId" binding:"required"`
}

type EditChatMessageRequest struct {
	Content string `json:"content" binding:"required"`
	Version *uint  `json:"version"`
}

type RecallChatMessageRequest struct {
	Version *uint `json:"version"`
}

type ChatReactionRequest struct {
	Emoji string `json:"emoji"`
}

type OptionalNullableTime struct {
	Set   bool
	Value *time.Time
}

func (value *OptionalNullableTime) UnmarshalJSON(data []byte) error {
	value.Set = true
	if bytes.Equal(bytes.TrimSpace(data), []byte("null")) {
		value.Value = nil
		return nil
	}
	var parsed time.Time
	if err := json.Unmarshal(data, &parsed); err != nil {
		return err
	}
	value.Value = &parsed
	return nil
}

type UpdateConversationUserSettingsRequest struct {
	MuteUntil  OptionalNullableTime `json:"muteUntil"`
	PinnedAt   OptionalNullableTime `json:"pinnedAt"`
	ArchivedAt OptionalNullableTime `json:"archivedAt"`
}

type SetTypingRequest struct {
	IsTyping bool `json:"isTyping"`
}

type SetPinnedMessageRequest struct {
	MessageID uint64 `json:"messageId"`
	Pinned    *bool  `json:"pinned"`
}

type CreateReminderRequest struct {
	Title      string    `json:"title"`
	RemindAt   time.Time `json:"remindAt"`
	RepeatType string    `json:"repeatType"`
}

type SearchConversationMessagesRequest struct {
	Keyword        string
	SenderUserid   string
	From           *time.Time
	To             *time.Time
	AttachmentType string
	BeforeID       uint64
	Limit          int
}

type CreatePollRequest struct {
	Question           string   `json:"question" binding:"required"`
	Options            []string `json:"options" binding:"required"`
	AllowCustomOptions bool     `json:"allowCustomOptions"`
	AllowMultiple      bool     `json:"allowMultiple"`
	ShowVoters         bool     `json:"showVoters"`
}

type VotePollRequest struct {
	OptionIDs    []uint64 `json:"optionIds"`
	CustomOption string   `json:"customOption"`
}

type ChatAttachmentInput struct {
	FileName     string `json:"fileName"`
	FileURL      string `json:"fileUrl"`
	FileSize     int64  `json:"fileSize"`
	MimeType     string `json:"mimeType"`
	RelativePath string `json:"relativePath"`
}
