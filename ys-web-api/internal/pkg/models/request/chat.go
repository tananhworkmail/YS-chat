package request

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

type AddContactRequest struct {
	Userid string `json:"userid" binding:"required"`
}

type RegisterDeviceTokenRequest struct {
	Token    string `json:"token" binding:"required"`
	Platform string `json:"platform"`
}

type SendChatMessageRequest struct {
	Type        string                `json:"type" binding:"required"`
	Content     string                `json:"content"`
	Attachments []ChatAttachmentInput `json:"attachments"`
}

type ChatAttachmentInput struct {
	FileName     string `json:"fileName"`
	FileURL      string `json:"fileUrl"`
	FileSize     int64  `json:"fileSize"`
	MimeType     string `json:"mimeType"`
	RelativePath string `json:"relativePath"`
}
