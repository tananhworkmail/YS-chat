package services

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"web-api/internal/pkg/config"
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
	userid        string
	conn          *websocket.Conn
	send          chan RealtimeEvent
	subscriptions map[uint64]struct{}
	hub           *RealtimeHub
}

type RealtimeHubOptions struct {
	PingInterval time.Duration
	PongWait     time.Duration
	WriteWait    time.Duration
	MaxMessage   int64
	SendQueue    int
}

type RealtimeMetrics struct {
	ActiveConnections int64 `json:"activeConnections"`
	DroppedEvents     int64 `json:"droppedEvents"`
	Reconnects        int64 `json:"reconnects"`
}

type RealtimeHub struct {
	mu                sync.RWMutex
	clients           map[string]map[*realtimeClient]struct{}
	typingMu          sync.Mutex
	typing            map[string]*time.Timer
	bus               RealtimeEventBus
	options           RealtimeHubOptions
	activeConnections atomic.Int64
	droppedEvents     atomic.Int64
	reconnects        atomic.Int64
	inboundMu         sync.Mutex
	inboundEventIDs   map[string]time.Time
	shuttingDown      atomic.Bool
}

var RealtimeHubInstance = NewRealtimeHub()

func NewRealtimeHub() *RealtimeHub {
	hub, err := NewRealtimeHubWithBus(NewInMemoryRealtimeEventBus(), RealtimeHubOptions{})
	if err != nil {
		panic(err)
	}
	return hub
}

func NewRealtimeHubWithBus(bus RealtimeEventBus, options RealtimeHubOptions) (*RealtimeHub, error) {
	if bus == nil {
		bus = NewInMemoryRealtimeEventBus()
	}
	options = normalizeRealtimeHubOptions(options)
	hub := &RealtimeHub{
		clients:         make(map[string]map[*realtimeClient]struct{}),
		typing:          make(map[string]*time.Timer),
		bus:             bus,
		options:         options,
		inboundEventIDs: make(map[string]time.Time),
	}
	if err := bus.Subscribe(hub.deliver); err != nil {
		_ = bus.Close()
		return nil, err
	}
	return hub, nil
}

func ConfigureRealtimeHub(configuration config.RealtimeConfiguration) error {
	var bus RealtimeEventBus = NewInMemoryRealtimeEventBus()
	if strings.EqualFold(strings.TrimSpace(configuration.EventBus), "redis") {
		redisBus, err := NewRedisRealtimeEventBus(
			firstNonEmpty(os.Getenv("YS_REDIS_URL"), configuration.RedisURL),
			firstNonEmpty(os.Getenv("YS_REDIS_CHANNEL"), configuration.RedisChannel),
		)
		if err != nil {
			return err
		}
		bus = redisBus
	}
	hub, err := NewRealtimeHubWithBus(bus, RealtimeHubOptions{
		PingInterval: secondsOrZero(configuration.PingIntervalSeconds),
		PongWait:     secondsOrZero(configuration.PongWaitSeconds),
		WriteWait:    secondsOrZero(configuration.WriteWaitSeconds),
		MaxMessage:   configuration.MaxMessageBytes,
		SendQueue:    configuration.SendQueueSize,
	})
	if err != nil {
		return err
	}
	oldHub := RealtimeHubInstance
	RealtimeHubInstance = hub
	if oldHub != nil {
		_ = oldHub.bus.Close()
	}
	return nil
}

func secondsOrZero(value int) time.Duration {
	if value <= 0 {
		return 0
	}
	return time.Duration(value) * time.Second
}

func normalizeRealtimeHubOptions(options RealtimeHubOptions) RealtimeHubOptions {
	if options.PingInterval <= 0 {
		options.PingInterval = 25 * time.Second
	}
	if options.PongWait <= options.PingInterval {
		options.PongWait = 60 * time.Second
	}
	if options.WriteWait <= 0 {
		options.WriteWait = 10 * time.Second
	}
	if options.MaxMessage <= 0 {
		options.MaxMessage = 64 * 1024
	}
	if options.SendQueue <= 0 {
		options.SendQueue = 64
	}
	return options
}

func (h *RealtimeHub) Serve(userid string, conn *websocket.Conn, reconnect bool) {
	userid = normalizeRealtimeUserid(userid)
	if userid == "" || h.shuttingDown.Load() {
		_ = conn.Close()
		return
	}

	client := &realtimeClient{
		userid:        userid,
		conn:          conn,
		send:          make(chan RealtimeEvent, h.options.SendQueue),
		subscriptions: make(map[uint64]struct{}),
		hub:           h,
	}
	if reconnect {
		h.reconnects.Add(1)
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
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := h.bus.Publish(ctx, RealtimeEnvelope{Userids: userids, Event: event}); err != nil {
		h.droppedEvents.Add(1)
	}
}

func (h *RealtimeHub) deliver(envelope RealtimeEnvelope) {
	event := envelope.Event

	seen := make(map[string]bool, len(envelope.Userids))
	h.mu.RLock()
	defer h.mu.RUnlock()

	for _, userid := range envelope.Userids {
		userid = normalizeRealtimeUserid(userid)
		if userid == "" || seen[userid] {
			continue
		}
		seen[userid] = true

		for client := range h.clients[userid] {
			select {
			case client.send <- event:
			default:
				h.droppedEvents.Add(1)
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
	h.activeConnections.Add(1)
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
			h.activeConnections.Add(-1)
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

	client.conn.SetReadLimit(h.options.MaxMessage)
	_ = client.conn.SetReadDeadline(time.Now().Add(h.options.PongWait))
	client.conn.SetPongHandler(func(string) error {
		_ = client.conn.SetReadDeadline(time.Now().Add(h.options.PongWait))
		return nil
	})

	for {
		var event RealtimeEvent
		if err := client.conn.ReadJSON(&event); err != nil {
			return
		}
		if !h.rememberInboundEvent(client.userid, event.EventID) {
			continue
		}
		h.handleClientEvent(client, event)
	}
}

func (h *RealtimeHub) handleClientEvent(client *realtimeClient, event RealtimeEvent) {
	event.SourceDeviceID = strings.TrimSpace(event.SourceDeviceID)
	switch strings.TrimSpace(event.Type) {
	case "subscription.restore":
		client.subscriptions = conversationIDSet(event.Payload)
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

func conversationIDSet(payload interface{}) map[uint64]struct{} {
	result := make(map[uint64]struct{})
	values, ok := payload.(map[string]interface{})
	if !ok {
		return result
	}
	raw, ok := values["conversationIds"].([]interface{})
	if !ok {
		return result
	}
	for _, value := range raw {
		var id uint64
		switch typed := value.(type) {
		case float64:
			if typed > 0 {
				id = uint64(typed)
			}
		case json.Number:
			parsed, _ := strconv.ParseUint(typed.String(), 10, 64)
			id = parsed
		}
		if id > 0 {
			result[id] = struct{}{}
		}
	}
	return result
}

func (h *RealtimeHub) rememberInboundEvent(userid, eventID string) bool {
	eventID = strings.TrimSpace(eventID)
	if eventID == "" {
		return true
	}
	key := userid + ":" + eventID
	now := time.Now()
	h.inboundMu.Lock()
	defer h.inboundMu.Unlock()
	if expires, exists := h.inboundEventIDs[key]; exists && expires.After(now) {
		return false
	}
	h.inboundEventIDs[key] = now.Add(5 * time.Minute)
	if len(h.inboundEventIDs) > 4096 {
		for stored, expires := range h.inboundEventIDs {
			if expires.Before(now) {
				delete(h.inboundEventIDs, stored)
			}
		}
	}
	return true
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

	transition, err := CallServiceInstance.ProcessEvent(userid, event)
	if err != nil {
		return err
	}
	if !transition.ShouldBroadcast {
		return nil
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
		"status":         transition.Call.Status,
	}
	if len(event.Signal) > 0 {
		event.Payload.(map[string]interface{})["signal"] = event.Signal
	}

	h.BroadcastToUsers(transition.Audience, event)
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
	ticker := time.NewTicker(client.hub.options.PingInterval)
	defer func() {
		ticker.Stop()
		_ = client.conn.Close()
	}()

	for {
		select {
		case event, ok := <-client.send:
			_ = client.conn.SetWriteDeadline(time.Now().Add(client.hub.options.WriteWait))
			if !ok {
				_ = client.conn.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, "disconnect"))
				return
			}
			if err := client.conn.WriteJSON(event); err != nil {
				return
			}
		case <-ticker.C:
			_ = client.conn.SetWriteDeadline(time.Now().Add(client.hub.options.WriteWait))
			if err := client.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

func (h *RealtimeHub) Metrics() RealtimeMetrics {
	return RealtimeMetrics{
		ActiveConnections: h.activeConnections.Load(),
		DroppedEvents:     h.droppedEvents.Load(),
		Reconnects:        h.reconnects.Load(),
	}
}

func (h *RealtimeHub) Shutdown(ctx context.Context) error {
	if !h.shuttingDown.CompareAndSwap(false, true) {
		return nil
	}
	h.mu.RLock()
	clients := make([]*realtimeClient, 0, int(h.activeConnections.Load()))
	for _, userClients := range h.clients {
		for client := range userClients {
			clients = append(clients, client)
		}
	}
	h.mu.RUnlock()
	deadline := time.Now().Add(h.options.WriteWait)
	for _, client := range clients {
		_ = client.conn.WriteControl(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseGoingAway, "server shutdown"), deadline)
		_ = client.conn.Close()
	}
	for h.activeConnections.Load() > 0 {
		select {
		case <-ctx.Done():
			_ = h.bus.Close()
			return ctx.Err()
		case <-time.After(10 * time.Millisecond):
		}
	}
	return h.bus.Close()
}
