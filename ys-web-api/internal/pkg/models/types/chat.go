package types

import "time"

type ChatUser struct {
	Userid    string `json:"userid"`
	Fullname  string `json:"fullname"`
	Nickname  string `json:"nickname,omitempty"`
	Avatar    string `json:"avatar"`
	Role      string `json:"role,omitempty"`
	IsContact bool   `json:"isContact"`
	IsOnline  bool   `json:"isOnline"`
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

type ChatMessageReceipt struct {
	Userid      string     `json:"userid"`
	Fullname    string     `json:"fullname,omitempty"`
	Avatar      string     `json:"avatar,omitempty"`
	DeliveredAt *time.Time `json:"deliveredAt,omitempty"`
	ReadAt      *time.Time `json:"readAt,omitempty"`
}

type ChatMessageReceiptSummary struct {
	TotalRecipients     int `json:"totalRecipients"`
	DeliveredRecipients int `json:"deliveredRecipients"`
	ReadRecipients      int `json:"readRecipients"`
}

type ChatReaction struct {
	Emoji       string             `json:"emoji"`
	Count       int                `json:"count"`
	ReactedByMe bool               `json:"reactedByMe"`
	Userids     []string           `json:"userids,omitempty"`
	Users       []ChatReactionUser `json:"users,omitempty"`
	UpdatedAt   time.Time          `json:"updatedAt"`
}

type ChatReactionUser struct {
	Userid   string `json:"userid"`
	Fullname string `json:"fullname"`
	Avatar   string `json:"avatar,omitempty"`
}

type ChatMessageEditHistoryEntry struct {
	AuditID         uint64    `json:"auditId"`
	MessageID       uint64    `json:"messageId"`
	PreviousVersion uint      `json:"previousVersion"`
	Version         uint      `json:"version"`
	PreviousContent string    `json:"previousContent"`
	Content         string    `json:"content"`
	EditorUserid    string    `json:"editorUserid"`
	EditorName      string    `json:"editorName"`
	EditorAvatar    string    `json:"editorAvatar,omitempty"`
	EditedAt        time.Time `json:"editedAt"`
}

type ChatMessage struct {
	ID              uint64                    `json:"id"`
	ConversationID  uint64                    `json:"conversationId"`
	ClientMessageID string                    `json:"clientMessageId,omitempty"`
	ServerSequence  uint64                    `json:"serverSequence"`
	SenderUserid    string                    `json:"senderUserid"`
	SenderName      string                    `json:"senderName"`
	SenderAvatar    string                    `json:"senderAvatar"`
	Type            string                    `json:"type"`
	Content         string                    `json:"content"`
	ReplyTo         *ChatMessageReference     `json:"replyTo,omitempty"`
	ForwardedFrom   *ChatMessageReference     `json:"forwardedFrom,omitempty"`
	Attachments     []ChatAttachment          `json:"attachments"`
	Poll            *ChatPoll                 `json:"poll,omitempty"`
	Status          string                    `json:"status"`
	ReceiptSummary  ChatMessageReceiptSummary `json:"receiptSummary"`
	Receipts        []ChatMessageReceipt      `json:"receipts"`
	Reactions       []ChatReaction            `json:"reactions"`
	Version         uint                      `json:"version"`
	EditedAt        *time.Time                `json:"editedAt,omitempty"`
	DeletedAt       *time.Time                `json:"deletedAt,omitempty"`
	DeletedBy       string                    `json:"deletedBy,omitempty"`
	IsRecalled      bool                      `json:"isRecalled"`
	CanRecall       bool                      `json:"canRecall"`
	RecallUntil     *time.Time                `json:"recallUntil,omitempty"`
	CreatedAt       time.Time                 `json:"createdAt"`
}

type ChatMessageReference struct {
	ID           uint64 `json:"id"`
	SenderUserid string `json:"senderUserid"`
	SenderName   string `json:"senderName"`
	Type         string `json:"type"`
	Content      string `json:"content"`
}

type ChatPinnedMessageState struct {
	ConversationID uint64                  `json:"conversationId"`
	PinnedMessage  *ChatMessageReference   `json:"pinnedMessage"`
	PinnedMessages []*ChatMessageReference `json:"pinnedMessages"`
	PinnedCount    int                     `json:"pinnedCount"`
	SystemMessage  *ChatMessage            `json:"systemMessage,omitempty"`
	PinnedBy       string                  `json:"pinnedBy,omitempty"`
	PinnedByName   string                  `json:"pinnedByName,omitempty"`
	PinnedAt       *time.Time              `json:"pinnedAt,omitempty"`
	ActorUserid    string                  `json:"actorUserid"`
	ActorName      string                  `json:"actorName"`
}

type ChatPoll struct {
	ID                 uint64           `json:"id"`
	MessageID          uint64           `json:"messageId"`
	Question           string           `json:"question"`
	AllowCustomOptions bool             `json:"allowCustomOptions"`
	AllowMultiple      bool             `json:"allowMultiple"`
	ShowVoters         bool             `json:"showVoters"`
	IsClosed           bool             `json:"isClosed"`
	ClosedBy           string           `json:"closedBy,omitempty"`
	ClosedAt           *time.Time       `json:"closedAt,omitempty"`
	CreatedBy          string           `json:"createdBy"`
	Options            []ChatPollOption `json:"options"`
	MyOptionIDs        []uint64         `json:"myOptionIds"`
	TotalVotes         int              `json:"totalVotes"`
	CreatedAt          time.Time        `json:"createdAt"`
	UpdatedAt          time.Time        `json:"updatedAt"`
}

type ChatPollOption struct {
	ID        uint64          `json:"id"`
	PollID    uint64          `json:"pollId"`
	Text      string          `json:"text"`
	CreatedBy string          `json:"createdBy"`
	IsCustom  bool            `json:"isCustom"`
	VoteCount int             `json:"voteCount"`
	Voters    []ChatPollVoter `json:"voters,omitempty"`
	CreatedAt time.Time       `json:"createdAt"`
}

type ChatPollVoter struct {
	Userid   string `json:"userid"`
	Fullname string `json:"fullname"`
	Avatar   string `json:"avatar"`
}

type ChatConversation struct {
	ID                  uint64                  `json:"id"`
	Type                string                  `json:"type"`
	Name                string                  `json:"name"`
	Avatar              string                  `json:"avatar"`
	Background          string                  `json:"background"`
	MemberCount         int                     `json:"memberCount"`
	Members             []ChatUser              `json:"members"`
	LastMessage         *ChatMessage            `json:"lastMessage"`
	LastReadMessageID   *uint64                 `json:"lastReadMessageId,omitempty"`
	LastReadAt          *time.Time              `json:"lastReadAt,omitempty"`
	UnreadCount         int                     `json:"unreadCount"`
	PinnedMessage       *ChatMessageReference   `json:"pinnedMessage"`
	PinnedMessages      []*ChatMessageReference `json:"pinnedMessages"`
	PinnedCount         int                     `json:"pinnedCount"`
	MessagePinnedBy     string                  `json:"messagePinnedBy,omitempty"`
	MessagePinnedByName string                  `json:"messagePinnedByName,omitempty"`
	MessagePinnedAt     *time.Time              `json:"messagePinnedAt,omitempty"`
	MuteUntil           *time.Time              `json:"muteUntil,omitempty"`
	PinnedAt            *time.Time              `json:"pinnedAt,omitempty"`
	ArchivedAt          *time.Time              `json:"archivedAt,omitempty"`
	CreatedAt           time.Time               `json:"createdAt"`
	UpdatedAt           time.Time               `json:"updatedAt"`
}

type ChatReminder struct {
	ID             uint64     `json:"id"`
	ConversationID uint64     `json:"conversationId"`
	CreatorUserid  string     `json:"creatorUserid"`
	CreatorName    string     `json:"creatorName"`
	Title          string     `json:"title"`
	RemindAt       time.Time  `json:"remindAt"`
	RepeatType     string     `json:"repeatType"`
	Status         string     `json:"status"`
	FiredAt        *time.Time `json:"firedAt,omitempty"`
	CreatedAt      time.Time  `json:"createdAt"`
}

type ChatConversationReadState struct {
	ConversationID    uint64     `json:"conversationId"`
	Userid            string     `json:"userid"`
	LastReadMessageID *uint64    `json:"lastReadMessageId,omitempty"`
	LastReadAt        *time.Time `json:"lastReadAt,omitempty"`
	UnreadCount       int        `json:"unreadCount"`
}

type ChatConversationUserSettings struct {
	ConversationID uint64     `json:"conversationId"`
	Userid         string     `json:"userid"`
	MuteUntil      *time.Time `json:"muteUntil,omitempty"`
	PinnedAt       *time.Time `json:"pinnedAt,omitempty"`
	ArchivedAt     *time.Time `json:"archivedAt,omitempty"`
}

type ChatCatchUpCursor struct {
	AfterMessageID uint64 `json:"afterMessageId"`
	AfterSequence  uint64 `json:"afterSequence"`
}

type ChatSearchResults struct {
	Contacts []ChatUser    `json:"contacts"`
	Messages []ChatMessage `json:"messages"`
	Files    []ChatMessage `json:"files"`
}
