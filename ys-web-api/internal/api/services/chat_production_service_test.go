package services

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"web-api/internal/pkg/models/request"
	"web-api/internal/pkg/models/types"

	"github.com/glebarez/sqlite"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

func setupProductionChatTestDB(t *testing.T) *gorm.DB {
	t.Helper()
	dsn := fmt.Sprintf("file:chat-production-%s?mode=memory&cache=shared&_busy_timeout=10000", uuid.NewString())
	db, err := gorm.Open(sqlite.Open(dsn), &gorm.Config{})
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatalf("get sql db: %v", err)
	}
	// One connection makes SQLite serialize transactions in the same way the
	// member-row lock serializes mark-read updates on MySQL.
	sqlDB.SetMaxOpenConns(1)

	statements := []string{
		`CREATE TABLE users (userid TEXT PRIMARY KEY, fullname TEXT, avatar TEXT)`,
		`CREATE TABLE chat_conversations (id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL, name TEXT, avatar TEXT, background TEXT, pinned_message_id INTEGER, message_pinned_by TEXT, message_pinned_at DATETIME, created_by TEXT, created_at DATETIME, updated_at DATETIME)`,
		`CREATE TABLE chat_members (id INTEGER PRIMARY KEY AUTOINCREMENT, conversation_id INTEGER NOT NULL, userid TEXT NOT NULL, role TEXT, nickname TEXT, last_delivered_message_id INTEGER, last_read_message_id INTEGER, last_read_at DATETIME, unread_count INTEGER NOT NULL DEFAULT 0, mute_until DATETIME, pinned_at DATETIME, archived_at DATETIME, joined_at DATETIME, UNIQUE(conversation_id, userid))`,
		`CREATE TABLE chat_contacts (id INTEGER PRIMARY KEY AUTOINCREMENT, owner_userid TEXT, contact_userid TEXT, nickname TEXT, created_at DATETIME, UNIQUE(owner_userid, contact_userid))`,
		`CREATE TABLE chat_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, conversation_id INTEGER NOT NULL, sender_userid TEXT NOT NULL, message_type TEXT NOT NULL, content TEXT, reply_to_message_id INTEGER, forwarded_from_message_id INTEGER, client_message_id TEXT, server_sequence INTEGER, version INTEGER NOT NULL DEFAULT 1, edited_at DATETIME, deleted_at DATETIME, deleted_by TEXT, created_at DATETIME, UNIQUE(sender_userid, client_message_id), UNIQUE(conversation_id, server_sequence))`,
		`CREATE TABLE chat_message_attachments (id INTEGER PRIMARY KEY AUTOINCREMENT, message_id INTEGER NOT NULL, file_name TEXT, file_url TEXT, file_size INTEGER, mime_type TEXT, relative_path TEXT, deleted_at DATETIME, deleted_by TEXT, created_at DATETIME)`,
		`CREATE TABLE chat_pending_uploads (id INTEGER PRIMARY KEY AUTOINCREMENT, userid TEXT NOT NULL, file_url TEXT NOT NULL UNIQUE, file_name TEXT NOT NULL, file_size INTEGER, mime_type TEXT, relative_path TEXT, claimed_message_id INTEGER, created_at DATETIME)`,
		`CREATE TABLE chat_message_receipts (id INTEGER PRIMARY KEY AUTOINCREMENT, message_id INTEGER NOT NULL, conversation_id INTEGER NOT NULL, userid TEXT NOT NULL, delivered_at DATETIME, read_at DATETIME, created_at DATETIME, updated_at DATETIME, UNIQUE(message_id, userid))`,
		`CREATE TABLE chat_message_user_deletions (id INTEGER PRIMARY KEY AUTOINCREMENT, message_id INTEGER NOT NULL, conversation_id INTEGER NOT NULL, userid TEXT NOT NULL, deleted_at DATETIME, UNIQUE(message_id, userid))`,
		`CREATE TABLE chat_message_reactions (id INTEGER PRIMARY KEY AUTOINCREMENT, message_id INTEGER NOT NULL, conversation_id INTEGER NOT NULL, userid TEXT NOT NULL, emoji TEXT NOT NULL, created_at DATETIME, updated_at DATETIME, UNIQUE(userid, message_id, emoji))`,
		`CREATE TABLE chat_message_audit (id INTEGER PRIMARY KEY AUTOINCREMENT, message_id INTEGER NOT NULL, conversation_id INTEGER NOT NULL, actor_userid TEXT NOT NULL, action TEXT NOT NULL, previous_version INTEGER, new_version INTEGER, snapshot_json TEXT, created_at DATETIME)`,
		`CREATE TABLE chat_calls (call_id TEXT PRIMARY KEY, conversation_id INTEGER NOT NULL, caller_userid TEXT NOT NULL, callee_userid TEXT NOT NULL, accepted_by_device_id TEXT, started_at DATETIME NOT NULL, answered_at DATETIME, ended_at DATETIME, status TEXT NOT NULL, duration_seconds INTEGER NOT NULL DEFAULT 0, end_reason TEXT, updated_at DATETIME)`,
		`CREATE TABLE chat_polls (id INTEGER PRIMARY KEY AUTOINCREMENT, message_id INTEGER, conversation_id INTEGER, question TEXT, allow_custom_options INTEGER, allow_multiple INTEGER, show_voters INTEGER, is_closed INTEGER, closed_by TEXT, closed_at DATETIME, created_by TEXT, created_at DATETIME, updated_at DATETIME)`,
		`CREATE TABLE chat_poll_options (id INTEGER PRIMARY KEY AUTOINCREMENT, poll_id INTEGER, option_text TEXT, created_by TEXT, is_custom INTEGER, created_at DATETIME)`,
		`CREATE TABLE chat_poll_votes (id INTEGER PRIMARY KEY AUTOINCREMENT, poll_id INTEGER, option_id INTEGER, userid TEXT, created_at DATETIME)`,
	}
	for _, statement := range statements {
		if err := db.Exec(statement).Error; err != nil {
			t.Fatalf("create schema: %v\n%s", err, statement)
		}
	}
	now := time.Now().UTC()
	for _, user := range []struct{ id, name string }{{"alice", "Alice"}, {"bob", "Bob"}, {"carol", "Carol"}} {
		if err := db.Exec("INSERT INTO users (userid, fullname, avatar) VALUES (?, ?, '')", user.id, user.name).Error; err != nil {
			t.Fatal(err)
		}
	}
	if err := db.Exec("INSERT INTO chat_conversations (id, type, name, created_by, created_at, updated_at) VALUES (1, 'group', 'Team', 'alice', ?, ?)", now, now).Error; err != nil {
		t.Fatal(err)
	}
	for _, user := range []string{"alice", "bob", "carol"} {
		role := "member"
		if user == "alice" {
			role = "owner"
		}
		if err := db.Exec("INSERT INTO chat_members (conversation_id, userid, role, joined_at) VALUES (1, ?, ?, ?)", user, role, now).Error; err != nil {
			t.Fatal(err)
		}
	}
	chatDBOverride = db
	t.Cleanup(func() { chatDBOverride = nil; _ = sqlDB.Close() })
	return db
}

func sendTestMessage(t *testing.T, sender, content string) uint64 {
	t.Helper()
	message, replay, err := ChatServiceInstance.SendMessageIdempotent(sender, 1, request.SendChatMessageRequest{ClientMessageID: uuid.NewString(), Type: "text", Content: content})
	if err != nil {
		t.Fatalf("send message: %v", err)
	}
	if replay {
		t.Fatal("first send reported replay")
	}
	return message.ID
}

func TestIdempotentSendDoesNotDuplicateOrDoubleUnread(t *testing.T) {
	db := setupProductionChatTestDB(t)
	clientID := uuid.NewString()
	req := request.SendChatMessageRequest{ClientMessageID: clientID, Type: "text", Content: "hello"}
	first, replay, err := ChatServiceInstance.SendMessageIdempotent("alice", 1, req)
	if err != nil || replay {
		t.Fatalf("first send: replay=%v err=%v", replay, err)
	}
	second, replay, err := ChatServiceInstance.SendMessageIdempotent("alice", 1, req)
	if err != nil || !replay {
		t.Fatalf("retry: replay=%v err=%v", replay, err)
	}
	if first.ID != second.ID {
		t.Fatalf("duplicate IDs: %d != %d", first.ID, second.ID)
	}
	var messageCount, receiptCount int64
	if err := db.Table("chat_messages").Count(&messageCount).Error; err != nil {
		t.Fatal(err)
	}
	if err := db.Table("chat_message_receipts").Where("message_id = ?", first.ID).Count(&receiptCount).Error; err != nil {
		t.Fatal(err)
	}
	if messageCount != 1 || receiptCount != 2 {
		t.Fatalf("messages=%d receipts=%d", messageCount, receiptCount)
	}
	for _, userid := range []string{"bob", "carol"} {
		var unread int
		if err := db.Table("chat_members").Select("unread_count").Where("conversation_id = 1 AND userid = ?", userid).Scan(&unread).Error; err != nil {
			t.Fatal(err)
		}
		if unread != 1 {
			t.Fatalf("%s unread=%d, want 1", userid, unread)
		}
	}
}

func TestPinnedMessageIsSharedAndBroadcastsPinChanges(t *testing.T) {
	db := setupProductionChatTestDB(t)
	messageID := sendTestMessage(t, "alice", "shared pin")

	hub, err := NewRealtimeHubWithBus(NewInMemoryRealtimeEventBus(), RealtimeHubOptions{})
	if err != nil {
		t.Fatalf("create realtime hub: %v", err)
	}
	previousHub := RealtimeHubInstance
	RealtimeHubInstance = hub
	t.Cleanup(func() {
		RealtimeHubInstance = previousHub
		_ = hub.bus.Close()
	})
	bobClient := &realtimeClient{userid: "bob", send: make(chan RealtimeEvent, 4), hub: hub}
	hub.clients["bob"] = map[*realtimeClient]struct{}{bobClient: {}}

	state, err := ChatServiceInstance.SetPinnedMessage("alice", 1, messageID)
	if err != nil {
		t.Fatalf("pin message: %v", err)
	}
	if state.PinnedMessage == nil || state.PinnedMessage.ID != messageID || state.ActorUserid != "alice" {
		t.Fatalf("unexpected pin state: %+v", state)
	}

	for _, userid := range []string{"bob", "carol"} {
		conversations, listErr := ChatServiceInstance.ListConversations(userid)
		if listErr != nil {
			t.Fatalf("list conversations for %s: %v", userid, listErr)
		}
		if len(conversations) != 1 || conversations[0].PinnedMessage == nil || conversations[0].PinnedMessage.ID != messageID {
			t.Fatalf("%s did not receive shared pin: %+v", userid, conversations)
		}
	}

	pinEvent := <-bobClient.send
	if pinEvent.Type != "message.pinned" || pinEvent.MessageID != messageID || pinEvent.Userid != "alice" {
		t.Fatalf("unexpected pin event: %+v", pinEvent)
	}
	pinNoticeEvent := <-bobClient.send
	if pinNoticeEvent.Type != "chat.message.created" || pinNoticeEvent.Message == nil || pinNoticeEvent.Message.Type != "system" || !strings.Contains(pinNoticeEvent.Message.Content, "đã ghim một tin nhắn") {
		t.Fatalf("unexpected pin conversation notice: %+v", pinNoticeEvent)
	}

	state, err = ChatServiceInstance.SetPinnedMessage("bob", 1, 0)
	if err != nil {
		t.Fatalf("unpin message: %v", err)
	}
	if state.PinnedMessage != nil || state.ActorUserid != "bob" {
		t.Fatalf("unexpected unpin state: %+v", state)
	}
	conversations, err := ChatServiceInstance.ListConversations("alice")
	if err != nil {
		t.Fatalf("list conversations after unpin: %v", err)
	}
	if len(conversations) != 1 || conversations[0].PinnedMessage != nil {
		t.Fatalf("shared pin remained after unpin: %+v", conversations)
	}
	unpinEvent := <-bobClient.send
	if unpinEvent.Type != "message.unpinned" || unpinEvent.MessageID != messageID || unpinEvent.Userid != "bob" {
		t.Fatalf("unexpected unpin event: %+v", unpinEvent)
	}
	unpinNoticeEvent := <-bobClient.send
	if unpinNoticeEvent.Type != "chat.message.created" || unpinNoticeEvent.Message == nil || unpinNoticeEvent.Message.Type != "system" || !strings.Contains(unpinNoticeEvent.Message.Content, "đã bỏ ghim tin nhắn") {
		t.Fatalf("unexpected unpin conversation notice: %+v", unpinNoticeEvent)
	}

	var auditCount int64
	if err := db.Table("chat_message_audit").Where("message_id = ? AND action IN ?", messageID, []string{"pin", "unpin"}).Count(&auditCount).Error; err != nil {
		t.Fatal(err)
	}
	if auditCount != 2 {
		t.Fatalf("pin audit rows=%d, want 2", auditCount)
	}
}

func TestConcurrentMarkReadIsMonotonicAndUnreadConsistent(t *testing.T) {
	db := setupProductionChatTestDB(t)
	ids := []uint64{sendTestMessage(t, "alice", "one"), sendTestMessage(t, "alice", "two"), sendTestMessage(t, "alice", "three")}
	requests := []uint64{ids[2], ids[0], ids[1], ids[2]}
	errs := make(chan error, len(requests))
	var wait sync.WaitGroup
	for _, id := range requests {
		wait.Add(1)
		go func(messageID uint64) {
			defer wait.Done()
			_, err := ChatServiceInstance.MarkRead("bob", 1, messageID)
			errs <- err
		}(id)
	}
	wait.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatalf("mark read: %v", err)
		}
	}
	var state productionMemberState
	if err := db.Table("chat_members").Where("conversation_id = 1 AND userid = 'bob'").Take(&state).Error; err != nil {
		t.Fatal(err)
	}
	if state.LastReadMessageID == nil || *state.LastReadMessageID != ids[2] ||
		state.LastDeliveredMessageID == nil || *state.LastDeliveredMessageID != ids[2] || state.UnreadCount != 0 {
		t.Fatalf("state=%+v", state)
	}
	var readCount int64
	if err := db.Table("chat_message_receipts").Where("userid = 'bob' AND read_at IS NOT NULL").Count(&readCount).Error; err != nil {
		t.Fatal(err)
	}
	if readCount != 3 {
		t.Fatalf("read receipts=%d, want 3", readCount)
	}
}

func TestGroupReceiptRequiresEveryRecipient(t *testing.T) {
	setupProductionChatTestDB(t)
	id := sendTestMessage(t, "alice", "group state")
	load := func() string {
		message, err := ChatServiceInstance.loadMessageByID(chatDBOverride, "alice", id)
		if err != nil {
			t.Fatal(err)
		}
		if message.ReceiptSummary.TotalRecipients != 2 {
			t.Fatalf("summary=%+v", message.ReceiptSummary)
		}
		return message.Status
	}
	if got := load(); got != "sent" {
		t.Fatalf("initial=%s", got)
	}
	if err := ChatServiceInstance.MarkDelivered("bob", 1, id); err != nil {
		t.Fatal(err)
	}
	if got := load(); got != "sent" {
		t.Fatalf("partial delivery=%s", got)
	}
	if err := ChatServiceInstance.MarkDelivered("carol", 1, id); err != nil {
		t.Fatal(err)
	}
	if got := load(); got != "delivered" {
		t.Fatalf("all delivered=%s", got)
	}
	if _, err := ChatServiceInstance.MarkRead("bob", 1, id); err != nil {
		t.Fatal(err)
	}
	if got := load(); got != "delivered" {
		t.Fatalf("partial read=%s", got)
	}
	if _, err := ChatServiceInstance.MarkRead("carol", 1, id); err != nil {
		t.Fatal(err)
	}
	if got := load(); got != "read" {
		t.Fatalf("all read=%s", got)
	}
}

func TestEditRecallPermissionsVersionAndAudit(t *testing.T) {
	db := setupProductionChatTestDB(t)
	id := sendTestMessage(t, "alice", "original")
	version := uint(1)
	if _, err := ChatServiceInstance.EditMessage("bob", id, request.EditChatMessageRequest{Content: "hijack", Version: &version}); err == nil || err.Error() != ErrChatNoPermission {
		t.Fatalf("edit permission err=%v", err)
	}
	if _, err := ChatServiceInstance.RecallMessage("bob", id); err == nil || err.Error() != ErrChatNoPermission {
		t.Fatalf("recall permission err=%v", err)
	}
	edited, err := ChatServiceInstance.EditMessage("alice", id, request.EditChatMessageRequest{Content: "edited", Version: &version})
	if err != nil || edited.Version != 2 || edited.EditedAt == nil {
		t.Fatalf("edited=%+v err=%v", edited, err)
	}
	if _, err := ChatServiceInstance.EditMessage("alice", id, request.EditChatMessageRequest{Content: "stale", Version: &version}); err == nil || err.Error() != ErrChatMessageVersionConflict {
		t.Fatalf("stale err=%v", err)
	}
	recalled, err := ChatServiceInstance.RecallMessage("alice", id)
	if err != nil || !recalled.IsRecalled || recalled.Content != "" || recalled.DeletedAt == nil {
		t.Fatalf("recalled=%+v err=%v", recalled, err)
	}
	var auditCount int64
	if err := db.Table("chat_message_audit").Where("message_id = ?", id).Count(&auditCount).Error; err != nil {
		t.Fatal(err)
	}
	if auditCount != 2 {
		t.Fatalf("audit=%d, want edit+recall", auditCount)
	}
	second := sendTestMessage(t, "alice", "before leaving")
	if err := db.Exec("DELETE FROM chat_members WHERE conversation_id = 1 AND userid = 'alice'").Error; err != nil {
		t.Fatal(err)
	}
	if _, err := ChatServiceInstance.EditMessage("alice", second, request.EditChatMessageRequest{Content: "after leaving"}); err == nil || err.Error() != ErrChatNoPermission {
		t.Fatalf("removed sender edit err=%v", err)
	}
}

func TestEditHistoryIsVisibleToConversationMembers(t *testing.T) {
	setupProductionChatTestDB(t)
	id := sendTestMessage(t, "alice", "original")
	version := uint(1)
	if _, err := ChatServiceInstance.EditMessage("alice", id, request.EditChatMessageRequest{Content: "second", Version: &version}); err != nil {
		t.Fatal(err)
	}
	version = 2
	if _, err := ChatServiceInstance.EditMessage("alice", id, request.EditChatMessageRequest{Content: "final", Version: &version}); err != nil {
		t.Fatal(err)
	}
	history, err := ChatServiceInstance.GetMessageEditHistory("bob", id)
	if err != nil {
		t.Fatal(err)
	}
	if len(history) != 2 {
		t.Fatalf("history=%+v", history)
	}
	if history[0].PreviousVersion != 1 || history[0].Version != 2 || history[0].PreviousContent != "original" || history[0].Content != "second" {
		t.Fatalf("first edit=%+v", history[0])
	}
	if history[1].PreviousVersion != 2 || history[1].Version != 3 || history[1].PreviousContent != "second" || history[1].Content != "final" || history[1].EditorName != "Alice" {
		t.Fatalf("second edit=%+v", history[1])
	}
	if _, err := ChatServiceInstance.GetMessageEditHistory("mallory", id); err == nil || err.Error() != ErrChatNoPermission {
		t.Fatalf("outsider history err=%v", err)
	}
}

func TestReactionIncludesMemberIdentity(t *testing.T) {
	setupProductionChatTestDB(t)
	id := sendTestMessage(t, "alice", "react here")
	if _, err := ChatServiceInstance.SetReaction("bob", id, "👍", true); err != nil {
		t.Fatal(err)
	}
	reactions, err := ChatServiceInstance.SetReaction("carol", id, "👍", true)
	if err != nil {
		t.Fatal(err)
	}
	if len(reactions) != 1 || reactions[0].Count != 2 || len(reactions[0].Users) != 2 {
		t.Fatalf("reactions=%+v", reactions)
	}
	if reactions[0].Users[0].Fullname != "Bob" || reactions[0].Users[1].Fullname != "Carol" {
		t.Fatalf("reaction users=%+v", reactions[0].Users)
	}
}

func TestCatchUpKeysetRecoversMissedMessages(t *testing.T) {
	setupProductionChatTestDB(t)
	ids := make([]uint64, 0, 5)
	for i := 0; i < 5; i++ {
		ids = append(ids, sendTestMessage(t, "alice", fmt.Sprintf("message %d", i)))
	}
	messages, cursor, hasMore, err := ChatServiceInstance.CatchUpMessages("bob", 1, ids[0], 0, 2)
	if err != nil {
		t.Fatal(err)
	}
	if !hasMore || len(messages) != 2 || messages[0].ID != ids[1] || messages[1].ID != ids[2] {
		t.Fatalf("messages=%v hasMore=%v", []uint64{messages[0].ID, messages[1].ID}, hasMore)
	}
	if cursor.AfterMessageID != ids[2] || cursor.AfterSequence != messages[1].ServerSequence {
		t.Fatalf("cursor=%+v", cursor)
	}
	messages, _, _, err = ChatServiceInstance.CatchUpMessages("bob", 1, 0, cursor.AfterSequence, 10)
	if err != nil || len(messages) != 2 || messages[0].ID != ids[3] || messages[1].ID != ids[4] {
		t.Fatalf("second page=%v err=%v", messages, err)
	}
}

func TestCatchUpUsesMessageIDForLegacyNullSequence(t *testing.T) {
	db := setupProductionChatTestDB(t)
	firstID := sendTestMessage(t, "alice", "before legacy writer")
	legacy := productionMessageRecord{
		ConversationID: 1, SenderUserid: "alice", MessageType: "text", Content: "late null sequence",
		Version: 1, CreatedAt: time.Now().UTC(),
	}
	if err := db.Table("chat_messages").Create(&legacy).Error; err != nil {
		t.Fatal(err)
	}
	lastID := sendTestMessage(t, "alice", "after legacy writer")

	messages, cursor, hasMore, err := ChatServiceInstance.CatchUpMessages("bob", 1, 0, firstID, 10)
	if err != nil {
		t.Fatal(err)
	}
	if hasMore || len(messages) != 2 || messages[0].ID != legacy.ID || messages[1].ID != lastID {
		t.Fatalf("messages=%+v hasMore=%v", messages, hasMore)
	}
	if messages[0].ServerSequence != legacy.ID {
		t.Fatalf("effective legacy sequence=%d, want %d", messages[0].ServerSequence, legacy.ID)
	}
	if cursor.AfterMessageID != lastID || cursor.AfterSequence != lastID {
		t.Fatalf("cursor=%+v", cursor)
	}
}

func TestConcurrentAddMemberAndSendHasAtomicRecipientSnapshot(t *testing.T) {
	db := setupProductionChatTestDB(t)
	if err := db.Exec("INSERT INTO users (userid, fullname, avatar) VALUES ('dave', 'Dave', '')").Error; err != nil {
		t.Fatal(err)
	}

	start := make(chan struct{})
	errs := make(chan error, 2)
	messageIDs := make(chan uint64, 1)
	go func() {
		<-start
		message, _, err := ChatServiceInstance.SendMessageIdempotent("alice", 1, request.SendChatMessageRequest{
			ClientMessageID: uuid.NewString(), Type: "text", Content: "recipient snapshot",
		})
		if err == nil {
			messageIDs <- message.ID
		}
		errs <- err
	}()
	go func() {
		<-start
		_, err := ChatServiceInstance.AddMembers("alice", 1, request.AddConversationMembersRequest{Userids: []string{"dave"}})
		errs <- err
	}()
	close(start)
	for i := 0; i < 2; i++ {
		if err := <-errs; err != nil {
			t.Fatal(err)
		}
	}
	messageID := <-messageIDs

	var state productionMemberState
	if err := db.Table("chat_members").Where("conversation_id = 1 AND userid = 'dave'").Take(&state).Error; err != nil {
		t.Fatal(err)
	}
	var receiptCount int64
	if err := db.Table("chat_message_receipts").Where("message_id = ? AND userid = 'dave'", messageID).Count(&receiptCount).Error; err != nil {
		t.Fatal(err)
	}
	switch receiptCount {
	case 0:
		if state.UnreadCount != 0 || state.LastReadMessageID == nil || *state.LastReadMessageID != messageID {
			t.Fatalf("send-before-add state=%+v receipts=%d", state, receiptCount)
		}
	case 1:
		if state.UnreadCount != 1 || (state.LastReadMessageID != nil && *state.LastReadMessageID >= messageID) {
			t.Fatalf("add-before-send state=%+v receipts=%d", state, receiptCount)
		}
	default:
		t.Fatalf("duplicate recipient snapshot rows=%d", receiptCount)
	}
}

func TestAttachmentSearchIsConversationScopedAndKeysetStable(t *testing.T) {
	db := setupProductionChatTestDB(t)
	firstID := sendTestMessage(t, "alice", "first attachment")
	_ = sendTestMessage(t, "alice", "without attachment")
	lastID := sendTestMessage(t, "alice", "last attachment")
	now := time.Now().UTC()
	attachments := []productionAttachmentRecord{
		{MessageID: firstID, FileName: "photo.png", FileURL: "/uploads/chat/photo.png", MimeType: "image/png", CreatedAt: now},
		{MessageID: lastID, FileName: "manual.pdf", FileURL: "/uploads/chat/manual.pdf", MimeType: "application/pdf", CreatedAt: now},
	}
	if err := db.Table("chat_message_attachments").Create(&attachments).Error; err != nil {
		t.Fatal(err)
	}

	page, next, hasMore, err := ChatServiceInstance.SearchConversationMessages("bob", 1, request.SearchConversationMessagesRequest{AttachmentType: "any", Limit: 1})
	if err != nil || !hasMore || len(page) != 1 || page[0].ID != lastID || next != lastID {
		t.Fatalf("first page=%+v next=%d hasMore=%v err=%v", page, next, hasMore, err)
	}
	page, _, hasMore, err = ChatServiceInstance.SearchConversationMessages("bob", 1, request.SearchConversationMessagesRequest{AttachmentType: "any", BeforeID: next, Limit: 1})
	if err != nil || hasMore || len(page) != 1 || page[0].ID != firstID {
		t.Fatalf("second page=%+v hasMore=%v err=%v", page, hasMore, err)
	}
	page, _, _, err = ChatServiceInstance.SearchConversationMessages("bob", 1, request.SearchConversationMessagesRequest{AttachmentType: "image", Limit: 10})
	if err != nil || len(page) != 1 || page[0].ID != firstID {
		t.Fatalf("image page=%+v err=%v", page, err)
	}
}

func TestDeleteForMeAndSharedAttachmentCleanup(t *testing.T) {
	db := setupProductionChatTestDB(t)
	directory := filepath.Join("uploads", "chat", "test-"+uuid.NewString())
	if err := os.MkdirAll(directory, 0o755); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(directory) })
	path := filepath.Join(directory, "shared.txt")
	if err := os.WriteFile(path, []byte("shared"), 0o600); err != nil {
		t.Fatal(err)
	}
	fileURL := "/" + filepath.ToSlash(path)
	registered := types.ChatAttachment{FileName: "shared.txt", FileURL: fileURL, FileSize: 6, MimeType: "text/plain", RelativePath: "folder/shared.txt"}
	if err := ChatServiceInstance.RegisterPendingUploads("alice", []types.ChatAttachment{registered}); err != nil {
		t.Fatal(err)
	}
	sendFile := func(forwardedFrom uint64) uint64 {
		req := request.SendChatMessageRequest{
			ClientMessageID: uuid.NewString(), Type: "file", ForwardedFromMessageID: forwardedFrom,
			Attachments: []request.ChatAttachmentInput{{FileName: "forged.exe", FileURL: fileURL, FileSize: 9999, MimeType: "application/x-forged", RelativePath: "forged.exe"}},
		}
		message, _, err := ChatServiceInstance.SendMessageIdempotent("alice", 1, request.SendChatMessageRequest{
			ClientMessageID: req.ClientMessageID, Type: req.Type, ForwardedFromMessageID: req.ForwardedFromMessageID, Attachments: req.Attachments,
		})
		if err != nil {
			t.Fatal(err)
		}
		return message.ID
	}
	first := sendFile(0)
	var canonical productionAttachmentRecord
	if err := db.Table("chat_message_attachments").Where("message_id = ?", first).Take(&canonical).Error; err != nil {
		t.Fatal(err)
	}
	if canonical.FileName != registered.FileName || canonical.FileSize != registered.FileSize || canonical.MimeType != registered.MimeType || canonical.RelativePath != registered.RelativePath {
		t.Fatalf("attachment metadata was not canonical: %+v", canonical)
	}
	second := sendFile(first)
	if err := ChatServiceInstance.DeleteMessageForMe("bob", first); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("delete-for-me removed file: %v", err)
	}
	messages, _, err := ChatServiceInstance.ListMessages("bob", 1, 50, 0)
	if err != nil {
		t.Fatal(err)
	}
	for _, message := range messages {
		if message.ID == first {
			t.Fatal("delete-for-me message still listed")
		}
	}
	if _, err := ChatServiceInstance.RecallMessage("alice", first); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("shared live reference was removed: %v", err)
	}
	if _, err := ChatServiceInstance.RecallMessage("alice", second); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(path); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("unreferenced attachment not removed: %v", err)
	}
	var live int64
	if err := db.Table("chat_message_attachments").Where("file_url = ? AND deleted_at IS NULL", fileURL).Count(&live).Error; err != nil {
		t.Fatal(err)
	}
	if live != 0 {
		t.Fatalf("live attachment rows=%d", live)
	}
}

func TestRecallKeepsAttachmentUsedByConversationAppearance(t *testing.T) {
	db := setupProductionChatTestDB(t)
	directory := filepath.Join("uploads", "chat", "test-"+uuid.NewString())
	if err := os.MkdirAll(directory, 0o755); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(directory) })
	path := filepath.Join(directory, "avatar.png")
	if err := os.WriteFile(path, []byte("avatar"), 0o600); err != nil {
		t.Fatal(err)
	}
	fileURL := "/" + filepath.ToSlash(path)
	attachment := types.ChatAttachment{FileName: "avatar.png", FileURL: fileURL, FileSize: 6, MimeType: "image/png"}
	if err := ChatServiceInstance.RegisterPendingUploads("alice", []types.ChatAttachment{attachment}); err != nil {
		t.Fatal(err)
	}
	message, _, err := ChatServiceInstance.SendMessageIdempotent("alice", 1, request.SendChatMessageRequest{
		ClientMessageID: uuid.NewString(), Type: "file",
		Attachments: []request.ChatAttachmentInput{{FileName: "avatar.png", FileURL: fileURL, FileSize: 6, MimeType: "image/png"}},
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := db.Table("chat_conversations").Where("id = 1").Update("avatar", fileURL).Error; err != nil {
		t.Fatal(err)
	}
	if _, err := ChatServiceInstance.RecallMessage("alice", message.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("conversation appearance file was removed: %v", err)
	}
}

func TestUserSettingsAreIsolated(t *testing.T) {
	db := setupProductionChatTestDB(t)
	mute := time.Now().UTC().Add(time.Hour)
	settings, err := ChatServiceInstance.UpdateConversationUserSettings("bob", 1, request.UpdateConversationUserSettingsRequest{MuteUntil: request.OptionalNullableTime{Set: true, Value: &mute}})
	if err != nil || settings.MuteUntil == nil {
		t.Fatalf("settings=%+v err=%v", settings, err)
	}
	var alice productionMemberState
	if err := db.Table("chat_members").Where("conversation_id = 1 AND userid = 'alice'").Take(&alice).Error; err != nil {
		t.Fatal(err)
	}
	if alice.MuteUntil != nil {
		t.Fatal("bob setting changed alice")
	}
	settings, err = ChatServiceInstance.UpdateConversationUserSettings("bob", 1, request.UpdateConversationUserSettingsRequest{MuteUntil: request.OptionalNullableTime{Set: true, Value: nil}})
	if err != nil || settings.MuteUntil != nil {
		t.Fatalf("clear settings=%+v err=%v", settings, err)
	}
}

func TestRealtimeEnvelopeAlwaysHasIdentityTimestampAndVersion(t *testing.T) {
	event := normalizeRealtimeEvent(RealtimeEvent{EventID: uuid.NewString(), Version: 99, ServerTimestamp: time.Now().Add(24 * time.Hour), Type: "read.receipt", ConversationID: 1, MessageID: 2})
	if _, err := uuid.Parse(event.EventID); err != nil {
		t.Fatalf("event id: %v", err)
	}
	if event.Version != 1 || event.ServerTimestamp.IsZero() || event.ServerTimestamp.After(time.Now().Add(time.Minute)) || event.SentAt.IsZero() || event.Payload == nil {
		t.Fatalf("event=%+v", event)
	}
}

func TestProductionMigrationIsAdditive(t *testing.T) {
	contents, err := os.ReadFile(filepath.Join("..", "..", "..", "migrations", "20260715_001_chat_production_features.sql"))
	if err != nil {
		t.Fatal(err)
	}
	normalized := strings.ToUpper(string(contents))
	for _, destructive := range []string{"DROP TABLE", "DROP COLUMN", "TRUNCATE TABLE", "DELETE FROM CHAT_"} {
		if strings.Contains(normalized, destructive) {
			t.Fatalf("migration contains destructive statement %q", destructive)
		}
	}
	if !strings.Contains(normalized, "SET SERVER_SEQUENCE = ID") {
		t.Fatal("legacy message sequence backfill missing")
	}
}
