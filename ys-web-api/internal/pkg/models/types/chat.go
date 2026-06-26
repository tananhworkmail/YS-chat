package types

import "time"

type ChatUser struct {
	Userid    string `json:"userid"`
	Fullname  string `json:"fullname"`
	Avatar    string `json:"avatar"`
	Role      string `json:"role,omitempty"`
	IsContact bool   `json:"isContact"`
}

type ChatAttachment struct {
	ID           uint64    `json:"id"`
	MessageID    uint64    `json:"messageId"`
	FileName     string    `json:"fileName"`
	FileURL      string    `json:"fileUrl"`
	FileSize     int64     `json:"fileSize"`
	MimeType     string    `json:"mimeType"`
	RelativePath string    `json:"relativePath"`
	CreatedAt    time.Time `json:"createdAt"`
}

type ChatMessage struct {
	ID             uint64           `json:"id"`
	ConversationID uint64           `json:"conversationId"`
	SenderUserid   string           `json:"senderUserid"`
	SenderName     string           `json:"senderName"`
	SenderAvatar   string           `json:"senderAvatar"`
	Type           string           `json:"type"`
	Content        string           `json:"content"`
	Attachments    []ChatAttachment `json:"attachments"`
	CreatedAt      time.Time        `json:"createdAt"`
}

type ChatConversation struct {
	ID          uint64       `json:"id"`
	Type        string       `json:"type"`
	Name        string       `json:"name"`
	Avatar      string       `json:"avatar"`
	MemberCount int          `json:"memberCount"`
	Members     []ChatUser   `json:"members"`
	LastMessage *ChatMessage `json:"lastMessage"`
	CreatedAt   time.Time    `json:"createdAt"`
	UpdatedAt   time.Time    `json:"updatedAt"`
}
