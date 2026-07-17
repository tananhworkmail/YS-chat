package controllers

import (
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"web-api/internal/api/middlewares"
	"web-api/internal/api/services"
	"web-api/internal/pkg/models/request"
	"web-api/internal/pkg/models/types"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

type ChatController struct {
	BaseController
}

var Chat = &ChatController{}

var chatRealtimeUpgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

func (h *ChatController) SearchUsers(c *gin.Context) {
	users, err := services.ChatServiceInstance.SearchUsers(currentUserid(c), c.Query("keyword"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"users": users})
}

func (h *ChatController) Search(c *gin.Context) {
	if conversationID := firstUintQuery(c, "conversationId"); conversationID > 0 {
		limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
		from, parseErr := parseOptionalTimeQuery(firstNonEmptyQuery(c, "from", "dateFrom"), false)
		if parseErr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
			return
		}
		to, parseErr := parseOptionalTimeQuery(firstNonEmptyQuery(c, "to", "dateTo"), true)
		if parseErr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
			return
		}
		messages, next, hasMore, searchErr := services.ChatServiceInstance.SearchConversationMessages(currentUserid(c), conversationID, request.SearchConversationMessagesRequest{
			Keyword: c.Query("keyword"), SenderUserid: c.Query("senderUserid"), From: from, To: to,
			AttachmentType: c.Query("attachmentType"), BeforeID: firstUintQuery(c, "beforeId"), Limit: limit,
		})
		if searchErr != nil {
			writeChatError(c, searchErr)
			return
		}
		results := &types.ChatSearchResults{Contacts: []types.ChatUser{}, Messages: messages, Files: []types.ChatMessage{}}
		c.JSON(http.StatusOK, gin.H{"results": results, "messages": messages, "nextBeforeId": next, "hasMore": hasMore})
		return
	}
	results, err := services.ChatServiceInstance.Search(currentUserid(c), c.Query("keyword"), c.Query("scope"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"results": results})
}

func (h *ChatController) ListContacts(c *gin.Context) {
	contacts, err := services.ChatServiceInstance.ListContacts(currentUserid(c))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"contacts": contacts})
}

func (h *ChatController) AddContact(c *gin.Context) {
	var req request.AddContactRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}

	contact, err := services.ChatServiceInstance.AddContact(currentUserid(c), req)
	if err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"contact": contact})
}

func (h *ChatController) UpdateContactNickname(c *gin.Context) {
	targetUserid := strings.TrimSpace(c.Param("userid"))
	if targetUserid == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}

	var req request.UpdateContactNicknameRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}

	contact, err := services.ChatServiceInstance.UpdateContactNickname(currentUserid(c), targetUserid, req)
	if err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"contact": contact})
}

func (h *ChatController) Realtime(c *gin.Context) {
	conn, err := chatRealtimeUpgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return
	}
	services.RealtimeHubInstance.Serve(currentUserid(c), conn, c.Query("reconnect") == "1")
}

func (h *ChatController) RealtimeTicket(c *gin.Context) {
	fullname, _ := c.Get("fullname")
	fullnameString, _ := fullname.(string)
	ticket, expiresIn, err := middlewares.IssueRealtimeTicket(currentUserid(c), strings.TrimSpace(fullnameString))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": services.ErrSystem})
		return
	}
	c.Header("Cache-Control", "no-store")
	c.JSON(http.StatusOK, gin.H{"ticket": ticket, "expiresIn": expiresIn})
}

func (h *ChatController) RealtimeHealth(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"ok":      true,
		"userid":  currentUserid(c),
		"metrics": services.RealtimeHubInstance.Metrics(),
	})
}

func (h *ChatController) RegisterDeviceToken(c *gin.Context) {
	var req request.RegisterDeviceTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}

	if err := services.ChatServiceInstance.RegisterDeviceToken(currentUserid(c), req); err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "DEVICE_TOKEN_REGISTERED"})
}

func (h *ChatController) UnregisterDeviceToken(c *gin.Context) {
	var req request.UnregisterDeviceTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}

	if err := services.ChatServiceInstance.UnregisterDeviceToken(currentUserid(c), req); err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "DEVICE_TOKEN_UNREGISTERED"})
}

func (h *ChatController) SendCallEvent(c *gin.Context) {
	var req request.SendCallEventRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}

	err := services.RealtimeHubInstance.RelayCallControlEvent(
		currentUserid(c),
		req.Type,
		req.ConversationID,
		req.CallID,
		req.DeviceID,
		req.Token,
	)
	if err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "CALL_EVENT_SENT"})
}

func (h *ChatController) ICEConfiguration(c *gin.Context) {
	c.Header("Cache-Control", "private, no-store")
	c.JSON(http.StatusOK, services.BuildICEConfiguration(currentUserid(c)))
}

func (h *ChatController) CallHistory(c *gin.Context) {
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	calls, err := services.CallServiceInstance.History(currentUserid(c), limit)
	if err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"calls": calls})
}

func (h *ChatController) GetCall(c *gin.Context) {
	call, err := services.CallServiceInstance.Get(currentUserid(c), c.Param("id"))
	if err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"call": call})
}

func (h *ChatController) ListConversations(c *gin.Context) {
	conversations, err := services.ChatServiceInstance.ListConversations(currentUserid(c))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"conversations": conversations})
}

func (h *ChatController) CreateDirectConversation(c *gin.Context) {
	var req request.CreateDirectConversationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}

	conversation, err := services.ChatServiceInstance.CreateDirectConversation(currentUserid(c), req)
	if err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"conversation": conversation})
}

func (h *ChatController) CreateGroupConversation(c *gin.Context) {
	var req request.CreateGroupConversationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}

	conversation, err := services.ChatServiceInstance.CreateGroupConversation(currentUserid(c), req)
	if err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"conversation": conversation})
}

func (h *ChatController) UpdateConversationSettings(c *gin.Context) {
	conversationID, ok := parseConversationID(c)
	if !ok {
		return
	}

	var req request.UpdateConversationSettingsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}

	conversation, err := services.ChatServiceInstance.UpdateConversationSettings(currentUserid(c), conversationID, req)
	if err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"conversation": conversation})
}

func (h *ChatController) AddMembers(c *gin.Context) {
	conversationID, ok := parseConversationID(c)
	if !ok {
		return
	}

	var req request.AddConversationMembersRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}

	conversation, err := services.ChatServiceInstance.AddMembers(currentUserid(c), conversationID, req)
	if err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"conversation": conversation})
}

func (h *ChatController) UpdateMemberNickname(c *gin.Context) {
	conversationID, ok := parseConversationID(c)
	if !ok {
		return
	}

	targetUserid := strings.TrimSpace(c.Param("userid"))
	if targetUserid == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}

	var req request.UpdateConversationMemberNicknameRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}

	conversation, err := services.ChatServiceInstance.UpdateMemberNickname(currentUserid(c), conversationID, targetUserid, req)
	if err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"conversation": conversation})
}

func (h *ChatController) RemoveMember(c *gin.Context) {
	conversationID, ok := parseConversationID(c)
	if !ok {
		return
	}

	targetUserid := strings.TrimSpace(c.Param("userid"))
	if targetUserid == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}

	conversation, err := services.ChatServiceInstance.RemoveMember(currentUserid(c), conversationID, targetUserid)
	if err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"conversation": conversation})
}

func (h *ChatController) ListMessages(c *gin.Context) {
	conversationID, ok := parseConversationID(c)
	if !ok {
		return
	}

	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	beforeID, _ := strconv.ParseUint(c.DefaultQuery("beforeId", "0"), 10, 64)
	messages, hasMore, err := services.ChatServiceInstance.ListMessages(currentUserid(c), conversationID, limit, beforeID)
	if err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"messages": messages,
		"hasMore":  hasMore,
	})
}

func (h *ChatController) SendMessage(c *gin.Context) {
	conversationID, ok := parseConversationID(c)
	if !ok {
		return
	}

	var req request.SendChatMessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}

	if req.ClientMessageID == "" {
		req.ClientMessageID = strings.TrimSpace(c.GetHeader("Idempotency-Key"))
	}
	message, replay, err := services.ChatServiceInstance.SendMessageIdempotent(currentUserid(c), conversationID, req)
	if err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": message, "idempotentReplay": replay})
}

func (h *ChatController) MarkRead(c *gin.Context) {
	conversationID, ok := parseConversationID(c)
	if !ok {
		return
	}
	var req request.MarkConversationReadRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}
	state, err := services.ChatServiceInstance.MarkRead(currentUserid(c), conversationID, req.LastReadMessageID)
	if err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"readState": state})
}

func (h *ChatController) MarkDelivered(c *gin.Context) {
	conversationID, ok := parseConversationID(c)
	if !ok {
		return
	}
	var req request.MarkConversationDeliveredRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}
	if err := services.ChatServiceInstance.MarkDelivered(currentUserid(c), conversationID, req.MessageID); err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "DELIVERY_RECORDED"})
}

func (h *ChatController) CatchUpMessages(c *gin.Context) {
	conversationID, ok := parseConversationID(c)
	if !ok {
		return
	}
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "100"))
	afterMessageID := firstUintQuery(c, "afterMessageId", "afterId")
	afterSequence := firstUintQuery(c, "afterSequence")
	messages, cursor, hasMore, err := services.ChatServiceInstance.CatchUpMessages(currentUserid(c), conversationID, afterMessageID, afterSequence, limit)
	if err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"messages": messages, "nextCursor": cursor, "hasMore": hasMore})
}

func (h *ChatController) SearchConversationMessages(c *gin.Context) {
	conversationID, ok := parseConversationID(c)
	if !ok {
		return
	}
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	beforeID := firstUintQuery(c, "beforeId")
	from, err := parseOptionalTimeQuery(c.Query("from"), false)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}
	to, err := parseOptionalTimeQuery(c.Query("to"), true)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}
	messages, nextBeforeID, hasMore, err := services.ChatServiceInstance.SearchConversationMessages(currentUserid(c), conversationID, request.SearchConversationMessagesRequest{
		Keyword: c.Query("keyword"), SenderUserid: c.Query("senderUserid"), From: from, To: to,
		AttachmentType: c.Query("attachmentType"), BeforeID: beforeID, Limit: limit,
	})
	if err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"messages": messages, "nextBeforeId": nextBeforeID, "hasMore": hasMore})
}

func (h *ChatController) EditMessage(c *gin.Context) {
	messageID, ok := parseMessageID(c)
	if !ok {
		return
	}
	var req request.EditChatMessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}
	message, err := services.ChatServiceInstance.EditMessage(currentUserid(c), messageID, req)
	if err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": message})
}

func (h *ChatController) GetMessageEditHistory(c *gin.Context) {
	messageID, ok := parseMessageID(c)
	if !ok {
		return
	}
	history, err := services.ChatServiceInstance.GetMessageEditHistory(currentUserid(c), messageID)
	if err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"history": history})
}

func (h *ChatController) RecallMessage(c *gin.Context) {
	messageID, ok := parseMessageID(c)
	if !ok {
		return
	}
	var req request.RecallChatMessageRequest
	if c.Request.ContentLength != 0 {
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
			return
		}
	}
	message, err := services.ChatServiceInstance.RecallMessageVersion(currentUserid(c), messageID, req.Version)
	if err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": message})
}

func (h *ChatController) DeleteMessageForMe(c *gin.Context) {
	messageID, ok := parseMessageID(c)
	if !ok {
		return
	}
	if err := services.ChatServiceInstance.DeleteMessageForMe(currentUserid(c), messageID); err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "MESSAGE_DELETED_FOR_ME"})
}

func (h *ChatController) AddReaction(c *gin.Context)    { h.setReaction(c, true) }
func (h *ChatController) RemoveReaction(c *gin.Context) { h.setReaction(c, false) }

func (h *ChatController) setReaction(c *gin.Context, add bool) {
	messageID, ok := parseMessageID(c)
	if !ok {
		return
	}
	emoji := strings.TrimSpace(c.Param("emoji"))
	if emoji == "" {
		var req request.ChatReactionRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
			return
		}
		emoji = req.Emoji
	}
	reactions, err := services.ChatServiceInstance.SetReaction(currentUserid(c), messageID, emoji, add)
	if err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"reactions": reactions})
}

func (h *ChatController) UpdateConversationUserSettings(c *gin.Context) {
	conversationID, ok := parseConversationID(c)
	if !ok {
		return
	}
	var req request.UpdateConversationUserSettingsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}
	settings, err := services.ChatServiceInstance.UpdateConversationUserSettings(currentUserid(c), conversationID, req)
	if err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"settings": settings})
}

func (h *ChatController) SetTyping(c *gin.Context) {
	conversationID, ok := parseConversationID(c)
	if !ok {
		return
	}
	var req request.SetTypingRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}
	if err := services.ChatServiceInstance.SetTyping(currentUserid(c), conversationID, req.IsTyping); err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"isTyping": req.IsTyping})
}

func (h *ChatController) CreatePoll(c *gin.Context) {
	conversationID, ok := parseConversationID(c)
	if !ok {
		return
	}

	var req request.CreatePollRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}

	message, err := services.ChatServiceInstance.CreatePoll(currentUserid(c), conversationID, req)
	if err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": message})
}

func (h *ChatController) VotePoll(c *gin.Context) {
	messageID, ok := parseConversationID(c)
	if !ok {
		return
	}

	var req request.VotePollRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}

	message, err := services.ChatServiceInstance.VotePoll(currentUserid(c), messageID, req)
	if err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": message})
}

func (h *ChatController) ClosePoll(c *gin.Context) {
	messageID, ok := parseConversationID(c)
	if !ok {
		return
	}

	message, err := services.ChatServiceInstance.ClosePoll(currentUserid(c), messageID)
	if err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": message})
}

func (h *ChatController) UploadFiles(c *gin.Context) {
	form, err := c.MultipartForm()
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}

	files := form.File["files"]
	if len(files) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return
	}

	relativePaths := form.Value["relativePaths"]
	uploadDay := time.Now().Format("20060102")
	uploadDir := filepath.Join("uploads", "chat", uploadDay)
	if err := os.MkdirAll(uploadDir, 0755); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": services.ErrSystem})
		return
	}

	attachments := make([]types.ChatAttachment, 0, len(files))
	savedPaths := make([]string, 0, len(files))
	cleanupSavedPaths := func() {
		for _, savedPath := range savedPaths {
			_ = os.Remove(savedPath)
		}
	}
	for index, file := range files {
		cleanName := sanitizeFilename(file.Filename)
		destination, err := saveUploadedFileRandom(file, uploadDir, cleanName, "")
		if err != nil {
			cleanupSavedPaths()
			c.JSON(http.StatusInternalServerError, gin.H{"error": services.ErrSystem})
			return
		}
		savedPaths = append(savedPaths, destination)

		relativePath := cleanName
		if index < len(relativePaths) && strings.TrimSpace(relativePaths[index]) != "" {
			relativePath = filepath.ToSlash(strings.TrimSpace(relativePaths[index]))
		}

		attachments = append(attachments, types.ChatAttachment{
			FileName:     cleanName,
			FileURL:      "/" + filepath.ToSlash(destination),
			FileSize:     file.Size,
			MimeType:     file.Header.Get("Content-Type"),
			RelativePath: relativePath,
			CreatedAt:    time.Now(),
		})
	}
	if err := services.ChatServiceInstance.RegisterPendingUploads(currentUserid(c), attachments); err != nil {
		cleanupSavedPaths()
		writeChatError(c, err)
		return
	}

	c.JSON(http.StatusOK, gin.H{"attachments": attachments})
}

func currentUserid(c *gin.Context) string {
	if value, ok := c.Get("userid"); ok {
		if userid, ok := value.(string); ok {
			return userid
		}
	}
	return ""
}

func parseConversationID(c *gin.Context) (uint64, bool) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 64)
	if err != nil || id == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": services.ErrInvalidInput})
		return 0, false
	}
	return id, true
}

func parseMessageID(c *gin.Context) (uint64, bool) { return parseConversationID(c) }

func firstUintQuery(c *gin.Context, names ...string) uint64 {
	for _, name := range names {
		if value, err := strconv.ParseUint(strings.TrimSpace(c.Query(name)), 10, 64); err == nil && value > 0 {
			return value
		}
	}
	return 0
}

func firstNonEmptyQuery(c *gin.Context, names ...string) string {
	for _, name := range names {
		if value := strings.TrimSpace(c.Query(name)); value != "" {
			return value
		}
	}
	return ""
}

func parseOptionalTimeQuery(value string, endOfDay bool) (*time.Time, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil, nil
	}
	if parsed, err := time.Parse(time.RFC3339, value); err == nil {
		return &parsed, nil
	}
	parsed, err := time.ParseInLocation("2006-01-02", value, time.Local)
	if err != nil {
		return nil, err
	}
	if endOfDay {
		parsed = parsed.Add(24*time.Hour - time.Nanosecond)
	}
	return &parsed, nil
}

func writeChatError(c *gin.Context, err error) {
	status := http.StatusBadRequest
	switch err.Error() {
	case services.ErrChatNoPermission, services.ErrChatOnlyOwnerCanManageMembers:
		status = http.StatusForbidden
	case services.ErrChatConversationNotFound, services.ErrChatUserNotFound, services.ErrChatMemberNotFound, services.ErrChatPollNotFound, services.ErrChatMessageNotFound:
		status = http.StatusNotFound
	case services.ErrChatMessageVersionConflict, services.ErrChatClientMessageIDConflict,
		services.ErrCallConflict, services.ErrCallInvalidTransition:
		status = http.StatusConflict
	case services.ErrCallNotFound:
		status = http.StatusNotFound
	case services.ErrChatRecallWindowExpired:
		status = http.StatusGone
	case services.ErrSystem:
		status = http.StatusInternalServerError
	}
	c.JSON(status, gin.H{"error": err.Error()})
}

func sanitizeFilename(filename string) string {
	filename = filepath.Base(filename)
	filename = strings.TrimSpace(filename)
	if filename == "" || filename == "." || filename == string(filepath.Separator) {
		return "file"
	}

	replacer := strings.NewReplacer("/", "_", "\\", "_", ":", "_", "*", "_", "?", "_", "\"", "_", "<", "_", ">", "_", "|", "_")
	return replacer.Replace(filename)
}
