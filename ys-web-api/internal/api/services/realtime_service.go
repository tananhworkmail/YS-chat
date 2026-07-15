package services

import (
	"encoding/json"
	"errors"
	"strconv"
	"strings"
	"sync"
	"time"

	"web-api/internal/pkg/models/types"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
)

type RealtimeEvent struct {
	EventID         string                  `json:"eventId"`
	Type            string                  `json:"type"`
	Version         int                     `json:"version"`
	ServerTimestamp time.Time               `json:"serverTimestamp"`
	ConversationID  uint64                  `json:"conversationId,omitempty"`
	MessageID       uint64                  `json:"messageId,omitempty"`
	Payload         interface{}             `json:"payload,omitempty"`
	Userid          string                  `json:"userid,omitempty"`
	FromUserid      string                  `json:"fromUserid,omitempty"`
	CallID          string                  `json:"callId,omitempty"`
	SourceDeviceID  string                  `json:"sourceDeviceId,omitempty"`
	SourceToken     string                  `json:"-"`
	Signal          json.RawMessage         `json:"signal,omitempty"`
	IsOnline        bool                    `json:"isOnline,omitempty"`
	Message         *types.ChatMessage      `json:"message,omitempty"`
	Conversation    *types.ChatConversation `json:"conversation,omitempty"`
	SentAt          time.Time               `json:"sentAt"`
}

type realtimeClient struct {
	userid string
	conn   *websocket.Conn
	send   chan RealtimeEvent
}

type RealtimeHub struct {
	mu       sync.RWMutex
	clients  map[string]map[*realtimeClient]struct{}
	typingMu sync.Mutex
	typing   map[string]*time.Timer
}

var RealtimeHubInstance = NewRealtimeHub()

func NewRealtimeHub() *RealtimeHub {
	return &RealtimeHub{
		clients: make(map[string]map[*realtimeClient]struct{}),
		typing:  make(map[string]*time.Timer),
	}
}

func (h *RealtimeHub) Serve(userid string, conn *websocket.Conn) {
	userid = normalizeRealtimeUserid(userid)
	if userid == "" {
		_ = conn.Close()
		return
	}

	client := &realtimeClient{
		userid: userid,
		conn:   conn,
		send:   make(chan RealtimeEvent, 16),
	}
	h.register(client)

	go client.writePump()
	client.readPump(h)
}

func (h *RealtimeHub) IsOnline(userid string) bool {
	userid = normalizeRealtimeUserid(userid)
	if userid == "" {
		return false
	}

	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.clients[userid]) > 0
}

func (h *RealtimeHub) OnlineSet(userids []string) map[string]bool {
	result := make(map[string]bool, len(userids))
	h.mu.RLock()
	defer h.mu.RUnlock()

	for _, userid := range userids {
		normalizedUserid := normalizeRealtimeUserid(userid)
		if normalizedUserid == "" {
			continue
		}
		isOnline := len(h.clients[normalizedUserid]) > 0
		result[userid] = isOnline
		result[normalizedUserid] = isOnline
	}
	return result
}

func (h *RealtimeHub) BroadcastToUsers(userids []string, event RealtimeEvent) {
	event = normalizeRealtimeEvent(event)

	seen := make(map[string]bool, len(userids))
	h.mu.RLock()
	defer h.mu.RUnlock()

	for _, userid := range userids {
		userid = normalizeRealtimeUserid(userid)
		if userid == "" || seen[userid] {
			continue
		}
		seen[userid] = true

		for client := range h.clients[userid] {
			select {
			case client.send <- event:
			default:
				go h.unregister(client)
			}
		}
	}
}

func normalizeRealtimeEvent(event RealtimeEvent) RealtimeEvent {
	now := time.Now().UTC()
	// These fields are server-owned. Always replace inbound values so a client
	// cannot spoof ordering, deduplication identity, or schema version.
	event.EventID = uuid.NewString()
	event.Version = 1
	event.ServerTimestamp = now
	event.SentAt = now
	if event.MessageID == 0 && event.Message != nil {
		event.MessageID = event.Message.ID
	}
	if event.Payload == nil {
		switch {
		case event.Message != nil:
			event.Payload = map[string]interface{}{"message": event.Message}
		case event.Conversation != nil:
			event.Payload = map[string]interface{}{"conversation": event.Conversation}
		default:
			event.Payload = map[string]interface{}{}
		}
	}
	return event
}

func (h *RealtimeHub) register(client *realtimeClient) {
	firstConnection := false

	h.mu.Lock()
	if h.clients[client.userid] == nil {
		h.clients[client.userid] = make(map[*realtimeClient]struct{})
		firstConnection = true
	}
	h.clients[client.userid][client] = struct{}{}
	h.mu.Unlock()

	if firstConnection {
		h.broadcastPresence(client.userid, true)
	}
}

func (h *RealtimeHub) unregister(client *realtimeClient) {
	lastConnection := false

	h.mu.Lock()
	if clients, ok := h.clients[client.userid]; ok {
		if _, exists := clients[client]; exists {
			delete(clients, client)
			close(client.send)
			_ = client.conn.Close()
		}
		if len(clients) == 0 {
			delete(h.clients, client.userid)
			lastConnection = true
		}
	}
	h.mu.Unlock()

	if lastConnection {
		h.broadcastPresence(client.userid, false)
	}
}

func (h *RealtimeHub) broadcastPresence(userid string, isOnline bool) {
	userid = normalizeRealtimeUserid(userid)
	if userid == "" {
		return
	}

	userids, err := ChatServiceInstance.PresenceAudience(userid)
	if err != nil || len(userids) == 0 {
		return
	}

	h.BroadcastToUsers(userids, RealtimeEvent{
		Type:     "chat.presence.changed",
		Userid:   userid,
		IsOnline: isOnline,
		Payload:  map[string]interface{}{"userid": userid, "isOnline": isOnline},
	})
}

func normalizeRealtimeUserid(userid string) string {
	return strings.TrimSpace(userid)
}

func (client *realtimeClient) readPump(h *RealtimeHub) {
	defer h.unregister(client)

	client.conn.SetReadLimit(512 * 1024)
	_ = client.conn.SetReadDeadline(time.Now().Add(70 * time.Second))
	client.conn.SetPongHandler(func(string) error {
		_ = client.conn.SetReadDeadline(time.Now().Add(70 * time.Second))
		return nil
	})

	for {
		var event RealtimeEvent
		if err := client.conn.ReadJSON(&event); err != nil {
			return
		}
		h.handleClientEvent(client, event)
	}
}

func (h *RealtimeHub) handleClientEvent(client *realtimeClient, event RealtimeEvent) {
	event.SourceDeviceID = strings.TrimSpace(event.SourceDeviceID)
	switch strings.TrimSpace(event.Type) {
	case "typing.start":
		_ = ChatServiceInstance.SetTyping(client.userid, event.ConversationID, true)
	case "typing.stop":
		_ = ChatServiceInstance.SetTyping(client.userid, event.ConversationID, false)
	case "delivery.receipt", "message.delivered":
		messageID := event.MessageID
		if messageID == 0 {
			messageID = uint64PayloadValue(event.Payload, "messageId")
		}
		_ = ChatServiceInstance.MarkDelivered(client.userid, event.ConversationID, messageID)
	default:
		_ = h.relayCallEvent(client.userid, event)
	}
}

func uint64PayloadValue(payload interface{}, key string) uint64 {
	values, ok := payload.(map[string]interface{})
	if !ok {
		return 0
	}
	value, ok := values[key]
	if !ok {
		return 0
	}
	switch typed := value.(type) {
	case float64:
		if typed > 0 {
			return uint64(typed)
		}
	case json.Number:
		parsed, _ := typed.Int64()
		if parsed > 0 {
			return uint64(parsed)
		}
	}
	return 0
}

func (h *RealtimeHub) PublishTyping(userid string, conversationID uint64, isTyping bool, recipients []string) {
	key := strings.TrimSpace(userid) + ":" + fmtUint(conversationID)
	h.typingMu.Lock()
	if timer := h.typing[key]; timer != nil {
		timer.Stop()
		delete(h.typing, key)
	}
	h.typingMu.Unlock()

	typeName := "typing.stop"
	expiresAt := time.Time{}
	if isTyping {
		typeName = "typing.start"
		expiresAt = time.Now().UTC().Add(8 * time.Second)
		var timer *time.Timer
		timer = time.AfterFunc(8*time.Second, func() {
			h.typingMu.Lock()
			if h.typing[key] != timer {
				h.typingMu.Unlock()
				return
			}
			delete(h.typing, key)
			h.typingMu.Unlock()
			h.BroadcastToUsers(recipients, RealtimeEvent{Type: "typing.stop", ConversationID: conversationID, Userid: userid, Payload: map[string]interface{}{"userid": userid, "isTyping": false, "expired": true}})
		})
		h.typingMu.Lock()
		h.typing[key] = timer
		h.typingMu.Unlock()
	}
	payload := map[string]interface{}{"userid": userid, "isTyping": isTyping}
	if !expiresAt.IsZero() {
		payload["expiresAt"] = expiresAt
	}
	h.BroadcastToUsers(recipients, RealtimeEvent{Type: typeName, ConversationID: conversationID, Userid: userid, Payload: payload})
}

func fmtUint(value uint64) string {
	return strconv.FormatUint(value, 10)
}

func (h *RealtimeHub) RelayCallControlEvent(userid string, eventType string, conversationID uint64, callID string, sourceDeviceID string, sourceToken string) error {
	switch strings.TrimSpace(eventType) {
	case "call.invite", "call.accept", "call.reject", "call.busy", "call.cancel", "call.end":
	default:
		return errors.New(ErrInvalidInput)
	}
	return h.relayCallEvent(userid, RealtimeEvent{
		Type:           eventType,
		ConversationID: conversationID,
		CallID:         callID,
		SourceDeviceID: strings.TrimSpace(sourceDeviceID),
		SourceToken:    strings.TrimSpace(sourceToken),
	})
}

func (h *RealtimeHub) relayCallEvent(userid string, event RealtimeEvent) error {
	event.Type = strings.TrimSpace(event.Type)
	if !isCallRealtimeType(event.Type) {
		return errors.New(ErrInvalidInput)
	}

	event.CallID = strings.TrimSpace(event.CallID)
	if event.ConversationID == 0 || event.CallID == "" || len(event.CallID) > 128 {
		return errors.New(ErrInvalidInput)
	}

	recipients, err := ChatServiceInstance.DirectCallRecipients(userid, event.ConversationID)
	if err != nil {
		return err
	}
	if len(recipients) == 0 {
		return errors.New(ErrChatNoPermission)
	}

	event.Userid = userid
	event.FromUserid = userid
	event.Message = nil
	event.Conversation = nil
	event.IsOnline = false
	event.Payload = map[string]interface{}{
		"fromUserid":     userid,
		"userid":         userid,
		"callId":         event.CallID,
		"sourceDeviceId": event.SourceDeviceID,
	}
	if len(event.Signal) > 0 {
		event.Payload.(map[string]interface{})["signal"] = event.Signal
	}

	h.BroadcastToUsers(recipients, event)
	if db, err := ChatServiceInstance.chatDB(); err == nil {
		if event.Type == "call.invite" {
			PushServiceInstance.SendCallInvitationNotification(
				db,
				userid,
				event.ConversationID,
				event.CallID,
				event.SourceDeviceID,
				event.SourceToken,
			)
		} else {
			PushServiceInstance.SendCallControlNotification(
				db,
				userid,
				event.ConversationID,
				event.CallID,
				event.Type,
				event.SourceDeviceID,
				event.SourceToken,
			)
		}
	}
	return nil
}

func isCallRealtimeType(eventType string) bool {
	switch eventType {
	case "call.invite",
		"call.accept",
		"call.reject",
		"call.busy",
		"call.cancel",
		"call.end",
		"call.offer",
		"call.answer",
		"call.ice":
		return true
	default:
		return false
	}
}

func (client *realtimeClient) writePump() {
	ticker := time.NewTicker(30 * time.Second)
	defer func() {
		ticker.Stop()
		_ = client.conn.Close()
	}()

	for {
		select {
		case event, ok := <-client.send:
			_ = client.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if !ok {
				_ = client.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := client.conn.WriteJSON(event); err != nil {
				return
			}
		case <-ticker.C:
			_ = client.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := client.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}
