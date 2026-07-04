package controllers

import (
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

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

func (h *ChatController) Realtime(c *gin.Context) {
	conn, err := chatRealtimeUpgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return
	}
	services.RealtimeHubInstance.Serve(currentUserid(c), conn)
}

func (h *ChatController) RealtimeHealth(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"ok":     true,
		"userid": currentUserid(c),
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

	message, err := services.ChatServiceInstance.SendMessage(currentUserid(c), conversationID, req)
	if err != nil {
		writeChatError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": message})
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
	for index, file := range files {
		cleanName := sanitizeFilename(file.Filename)
		destination, err := saveUploadedFileRandom(file, uploadDir, cleanName, "")
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": services.ErrSystem})
			return
		}

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

func writeChatError(c *gin.Context, err error) {
	status := http.StatusBadRequest
	switch err.Error() {
	case services.ErrChatNoPermission, services.ErrChatOnlyOwnerCanManageMembers:
		status = http.StatusForbidden
	case services.ErrChatConversationNotFound, services.ErrChatUserNotFound, services.ErrChatMemberNotFound, services.ErrChatPollNotFound:
		status = http.StatusNotFound
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
