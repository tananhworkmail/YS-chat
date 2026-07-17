package services

import (
	"context"
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"
	"gorm.io/gorm"
)

type PushService struct {
	mu            sync.Mutex
	messaging     *messaging.Client
	initialized   bool
	configMissing bool
}

var PushServiceInstance = &PushService{}

func (s *PushService) SendChatMessageNotification(db *gorm.DB, senderUserid string, conversationID uint64, messageID uint64, messageType string, content string) {
	if db == nil {
		return
	}

	client, ok := s.client()
	if !ok {
		return
	}

	tokens, err := s.deviceTokens(db, conversationID, senderUserid, "", "", false)
	if err != nil || len(tokens) == 0 {
		return
	}

	title := s.notificationTitle(db, conversationID, senderUserid)
	body := cleanNotificationBody(messageType, content)
	data := map[string]string{
		"type":           "chat.message.created",
		"conversationId": strconv.FormatUint(conversationID, 10),
		"messageId":      strconv.FormatUint(messageID, 10),
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	for start := 0; start < len(tokens); start += 500 {
		end := start + 500
		if end > len(tokens) {
			end = len(tokens)
		}

		response, err := client.SendEachForMulticast(ctx, &messaging.MulticastMessage{
			Tokens: tokens[start:end],
			Notification: &messaging.Notification{
				Title: title,
				Body:  body,
			},
			Data: data,
			Android: &messaging.AndroidConfig{
				Priority:     "high",
				DirectBootOK: true,
				Notification: &messaging.AndroidNotification{
					Title:     title,
					Body:      body,
					Icon:      "ic_launcher",
					Color:     "#0891B2",
					Sound:     "default",
					ChannelID: "ys_chat_messages",
				},
			},
			APNS: &messaging.APNSConfig{
				Payload: &messaging.APNSPayload{
					Aps: &messaging.Aps{
						Sound: "default",
						Badge: intPtr(1),
					},
				},
			},
		})
		s.logMulticastResult(db, "chat.message.created", tokens[start:end], response, err)
	}
}

func (s *PushService) SendCallInvitationNotification(db *gorm.DB, senderUserid string, conversationID uint64, callID string, sourceDeviceID string, sourceToken string) {
	if db == nil {
		return
	}

	client, ok := s.client()
	if !ok {
		return
	}

	tokens, err := s.deviceTokens(db, conversationID, senderUserid, sourceDeviceID, sourceToken, false)
	if err != nil || len(tokens) == 0 {
		return
	}

	title := s.notificationTitle(db, conversationID, senderUserid)
	avatarURL := s.notificationAvatar(db, senderUserid)
	body := "Cuộc gọi đến"
	data := map[string]string{
		"type":           "call.invite",
		"avatarUrl":      avatarURL,
		"conversationId": strconv.FormatUint(conversationID, 10),
		"callId":         callID,
		"fromUserid":     senderUserid,
		"callerName":     title,
		"title":          title,
		"body":           body,
	}
	ttl := 45 * time.Second

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	for start := 0; start < len(tokens); start += 500 {
		end := start + 500
		if end > len(tokens) {
			end = len(tokens)
		}

		response, err := client.SendEachForMulticast(ctx, &messaging.MulticastMessage{
			Tokens: tokens[start:end],
			Data:   data,
			Android: &messaging.AndroidConfig{
				Priority:     "high",
				TTL:          &ttl,
				DirectBootOK: true,
			},
			APNS: &messaging.APNSConfig{
				Headers: map[string]string{
					"apns-priority":   "10",
					"apns-expiration": strconv.FormatInt(time.Now().Add(ttl).Unix(), 10),
				},
				Payload: &messaging.APNSPayload{
					Aps: &messaging.Aps{
						Alert: &messaging.ApsAlert{
							Title: title,
							Body:  body,
						},
						Sound:            "default",
						Badge:            intPtr(1),
						ContentAvailable: true,
					},
				},
			},
		})
		s.logMulticastResult(db, "call.invite", tokens[start:end], response, err)
	}
}

func (s *PushService) SendCallControlNotification(db *gorm.DB, senderUserid string, conversationID uint64, callID string, eventType string, sourceDeviceID string, sourceToken string) {
	if db == nil {
		return
	}

	switch eventType {
	case "call.accept", "call.reject", "call.busy", "call.cancel", "call.end":
	default:
		return
	}

	client, ok := s.client()
	if !ok {
		return
	}
	// Control events are delivered to every installation in the conversation,
	// including other installations of the account that performed the action.
	// The originating installation is excluded to avoid duplicate local actions.
	tokens, err := s.deviceTokens(db, conversationID, senderUserid, sourceDeviceID, sourceToken, true)
	if err != nil || len(tokens) == 0 {
		return
	}

	data := map[string]string{
		"type":           eventType,
		"conversationId": strconv.FormatUint(conversationID, 10),
		"callId":         callID,
		"fromUserid":     senderUserid,
		"sourceDeviceId": sourceDeviceID,
	}
	ttl := 45 * time.Second
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	for start := 0; start < len(tokens); start += 500 {
		end := start + 500
		if end > len(tokens) {
			end = len(tokens)
		}
		response, err := client.SendEachForMulticast(ctx, &messaging.MulticastMessage{
			Tokens: tokens[start:end],
			Data:   data,
			Android: &messaging.AndroidConfig{
				Priority:     "high",
				TTL:          &ttl,
				DirectBootOK: true,
			},
			APNS: &messaging.APNSConfig{
				Headers: map[string]string{"apns-priority": "5"},
				Payload: &messaging.APNSPayload{
					Aps: &messaging.Aps{ContentAvailable: true},
				},
			},
		})
		s.logMulticastResult(db, eventType, tokens[start:end], response, err)
	}
}

func (s *PushService) logMulticastResult(
	db *gorm.DB,
	kind string,
	tokens []string,
	response *messaging.BatchResponse,
	err error,
) {
	if err != nil {
		log.Printf("firebase push %s failed for %d token(s): %v", kind, len(tokens), err)
		return
	}
	if response == nil {
		log.Printf("firebase push %s returned an empty response for %d token(s)", kind, len(tokens))
		return
	}
	if response.FailureCount == 0 {
		log.Printf("firebase push %s accepted by FCM: success=%d", kind, response.SuccessCount)
		return
	}

	logged := 0
	for index, item := range response.Responses {
		if item == nil || item.Success || item.Error == nil {
			continue
		}
		token := "unknown"
		if index < len(tokens) {
			token = tokenHint(tokens[index])
		}
		shouldLog := logged < 5
		if shouldLog {
			log.Printf("firebase push %s token %s rejected: %v", kind, token, item.Error)
			logged++
		}
		if isInvalidRegistrationToken(item.Error) && index < len(tokens) {
			if deleteErr := db.Exec(
				"DELETE FROM chat_device_tokens WHERE token = ?",
				tokens[index],
			).Error; deleteErr != nil {
				if shouldLog {
					log.Printf("failed to remove invalid Firebase token %s: %v", token, deleteErr)
				}
			}
		}
	}
	log.Printf("firebase push %s partial failure: success=%d failure=%d", kind, response.SuccessCount, response.FailureCount)
}

func isInvalidRegistrationToken(err error) bool {
	if err == nil {
		return false
	}
	message := strings.ToLower(err.Error())
	return strings.Contains(message, "requested entity was not found") ||
		strings.Contains(message, "registration-token-not-registered") ||
		strings.Contains(message, "invalid-registration-token") ||
		strings.Contains(message, "unregistered")
}

func tokenHint(token string) string {
	if len(token) <= 8 {
		return token
	}
	return "..." + token[len(token)-8:]
}

func (s *PushService) client() (*messaging.Client, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.initialized {
		return s.messaging, s.messaging != nil
	}
	if s.configMissing {
		return nil, false
	}

	credentialsJSON := strings.TrimSpace(os.Getenv("FIREBASE_SERVICE_ACCOUNT_JSON"))
	credentialsFile := strings.TrimSpace(os.Getenv("GOOGLE_APPLICATION_CREDENTIALS"))
	if credentialsJSON == "" && credentialsFile == "" {
		s.configMissing = true
		return nil, false
	}

	opts := make([]option.ClientOption, 0, 1)
	if credentialsJSON != "" {
		opts = append(opts, option.WithCredentialsJSON([]byte(credentialsJSON)))
	} else {
		opts = append(opts, option.WithCredentialsFile(credentialsFile))
	}

	config := &firebase.Config{}
	if projectID := strings.TrimSpace(os.Getenv("FIREBASE_PROJECT_ID")); projectID != "" {
		config.ProjectID = projectID
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	app, err := firebase.NewApp(ctx, config, opts...)
	if err != nil {
		s.configMissing = true
		return nil, false
	}

	client, err := app.Messaging(ctx)
	if err != nil {
		s.configMissing = true
		return nil, false
	}

	s.messaging = client
	s.initialized = true
	return s.messaging, true
}

func (s *PushService) deviceTokens(
	db *gorm.DB,
	conversationID uint64,
	senderUserid string,
	sourceDeviceID string,
	sourceToken string,
	includeSender bool,
) ([]string, error) {
	var tokens []string
	whereSender := "AND dt.userid <> ?"
	args := []interface{}{conversationID, senderUserid}
	if includeSender {
		whereSender = ""
		args = []interface{}{conversationID}
	}
	query := `
		SELECT DISTINCT dt.token
		FROM chat_device_tokens dt
		JOIN chat_members cm ON cm.userid = dt.userid
		WHERE cm.conversation_id = ?
			` + whereSender + `
			AND (cm.mute_until IS NULL OR cm.mute_until <= ?)
			AND dt.token <> ''
			AND (dt.device_id = '' OR dt.device_id <> ?)
			AND dt.token <> ?
	`
	args = append(args, time.Now(), sourceDeviceID, sourceToken)
	err := db.Raw(query, args...).Scan(&tokens).Error
	return tokens, err
}

func (s *PushService) notificationTitle(db *gorm.DB, conversationID uint64, senderUserid string) string {
	var sender struct {
		Fullname string
	}
	_ = db.Table("users").
		Select("COALESCE(fullname, userid) AS fullname").
		Where("userid = ?", senderUserid).
		Scan(&sender).Error
	if strings.TrimSpace(sender.Fullname) == "" {
		sender.Fullname = senderUserid
	}

	var conversation struct {
		Type string
		Name string
	}
	_ = db.Table("chat_conversations").
		Select("type, COALESCE(name, '') AS name").
		Where("id = ?", conversationID).
		Scan(&conversation).Error

	if conversation.Type == "group" && strings.TrimSpace(conversation.Name) != "" {
		return fmt.Sprintf("%s - %s", conversation.Name, sender.Fullname)
	}
	return sender.Fullname
}

func (s *PushService) notificationAvatar(db *gorm.DB, senderUserid string) string {
	var sender struct {
		Avatar string
	}
	_ = db.Table("users").
		Select("COALESCE(avatar, '') AS avatar").
		Where("userid = ?", senderUserid).
		Scan(&sender).Error
	return strings.TrimSpace(sender.Avatar)
}

func notificationBody(messageType, content string) string {
	switch messageType {
	case "file":
		return "Đã gửi tệp"
	case "folder":
		return "Đã gửi thư mục"
	case "voice":
		return "Voice chat"
	case "link":
		return "Đã gửi liên kết"
	default:
		content = strings.TrimSpace(content)
		if len([]rune(content)) > 120 {
			return string([]rune(content)[:120]) + "..."
		}
		if content == "" {
			return "Tin nhắn mới"
		}
		return content
	}
}

func cleanNotificationBody(messageType, content string) string {
	switch messageType {
	case "call":
		return "Thông tin cuộc gọi"
	case "file":
		return "Da gui tep"
	case "folder":
		return "Da gui thu muc"
	case "voice":
		return "Da gui tin nhan thoai"
	case "link":
		return "Da gui lien ket"
	default:
		content = strings.TrimSpace(content)
		if len([]rune(content)) > 120 {
			return string([]rune(content)[:120]) + "..."
		}
		if content == "" {
			return "Tin nhan moi"
		}
		return content
	}
}

func intPtr(value int) *int {
	return &value
}
