package services

import (
	"encoding/json"
	"strings"
	"sync"
	"time"

	"web-api/internal/pkg/models/types"

	"github.com/gorilla/websocket"
)

type RealtimeEvent struct {
	Type           string                  `json:"type"`
	ConversationID uint64                  `json:"conversationId,omitempty"`
	Userid         string                  `json:"userid,omitempty"`
	FromUserid     string                  `json:"fromUserid,omitempty"`
	CallID         string                  `json:"callId,omitempty"`
	Signal         json.RawMessage         `json:"signal,omitempty"`
	IsOnline       bool                    `json:"isOnline,omitempty"`
	Message        *types.ChatMessage      `json:"message,omitempty"`
	Conversation   *types.ChatConversation `json:"conversation,omitempty"`
	SentAt         time.Time               `json:"sentAt"`
}

type realtimeClient struct {
	userid string
	conn   *websocket.Conn
	send   chan RealtimeEvent
}

type RealtimeHub struct {
	mu      sync.RWMutex
	clients map[string]map[*realtimeClient]struct{}
}

var RealtimeHubInstance = NewRealtimeHub()

func NewRealtimeHub() *RealtimeHub {
	return &RealtimeHub{
		clients: make(map[string]map[*realtimeClient]struct{}),
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
	if event.SentAt.IsZero() {
		event.SentAt = time.Now()
	}

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
		SentAt:   time.Now(),
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
	event.Type = strings.TrimSpace(event.Type)
	if !isCallRealtimeType(event.Type) {
		return
	}

	event.CallID = strings.TrimSpace(event.CallID)
	if event.ConversationID == 0 || event.CallID == "" || len(event.CallID) > 128 {
		return
	}

	recipients, err := ChatServiceInstance.DirectCallRecipients(client.userid, event.ConversationID)
	if err != nil || len(recipients) == 0 {
		return
	}

	event.Userid = client.userid
	event.FromUserid = client.userid
	event.Message = nil
	event.Conversation = nil
	event.IsOnline = false
	event.SentAt = time.Now()

	h.BroadcastToUsers(recipients, event)
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
