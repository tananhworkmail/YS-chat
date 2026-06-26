package services

import (
	"context"
	"fmt"
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

	tokens, err := s.deviceTokens(db, conversationID, senderUserid)
	if err != nil || len(tokens) == 0 {
		return
	}

	title := s.notificationTitle(db, conversationID, senderUserid)
	body := notificationBody(messageType, content)
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

		_, _ = client.SendEachForMulticast(ctx, &messaging.MulticastMessage{
			Tokens: tokens[start:end],
			Notification: &messaging.Notification{
				Title: title,
				Body:  body,
			},
			Data: data,
			Android: &messaging.AndroidConfig{
				Priority: "high",
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
	}
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

func (s *PushService) deviceTokens(db *gorm.DB, conversationID uint64, senderUserid string) ([]string, error) {
	var tokens []string
	err := db.Raw(`
		SELECT DISTINCT dt.token
		FROM chat_device_tokens dt
		JOIN chat_members cm ON cm.userid = dt.userid
		WHERE cm.conversation_id = ?
			AND dt.userid <> ?
			AND dt.token <> ''
	`, conversationID, senderUserid).Scan(&tokens).Error
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

func intPtr(value int) *int {
	return &value
}
