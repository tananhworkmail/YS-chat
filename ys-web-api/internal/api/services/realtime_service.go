package services

import (
	"sync"
	"time"

	"web-api/internal/pkg/models/types"

	"github.com/gorilla/websocket"
)

type RealtimeEvent struct {
	Type           string                  `json:"type"`
	ConversationID uint64                  `json:"conversationId,omitempty"`
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
	client := &realtimeClient{
		userid: userid,
		conn:   conn,
		send:   make(chan RealtimeEvent, 16),
	}
	h.register(client)

	go client.writePump()
	client.readPump(h)
}

func (h *RealtimeHub) BroadcastToUsers(userids []string, event RealtimeEvent) {
	if event.SentAt.IsZero() {
		event.SentAt = time.Now()
	}

	seen := make(map[string]bool, len(userids))
	h.mu.RLock()
	defer h.mu.RUnlock()

	for _, userid := range userids {
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
	h.mu.Lock()
	defer h.mu.Unlock()

	if h.clients[client.userid] == nil {
		h.clients[client.userid] = make(map[*realtimeClient]struct{})
	}
	h.clients[client.userid][client] = struct{}{}
}

func (h *RealtimeHub) unregister(client *realtimeClient) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if clients, ok := h.clients[client.userid]; ok {
		if _, exists := clients[client]; exists {
			delete(clients, client)
			close(client.send)
			_ = client.conn.Close()
		}
		if len(clients) == 0 {
			delete(h.clients, client.userid)
		}
	}
}

func (client *realtimeClient) readPump(h *RealtimeHub) {
	defer h.unregister(client)

	client.conn.SetReadLimit(1024)
	_ = client.conn.SetReadDeadline(time.Now().Add(70 * time.Second))
	client.conn.SetPongHandler(func(string) error {
		_ = client.conn.SetReadDeadline(time.Now().Add(70 * time.Second))
		return nil
	})

	for {
		if _, _, err := client.conn.NextReader(); err != nil {
			return
		}
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
