package services

import (
	"encoding/json"
	"sync"
	"testing"

	"github.com/google/uuid"
)

func setupDirectCallTest(t *testing.T) {
	db := setupProductionChatTestDB(t)
	if err := db.Exec("UPDATE chat_conversations SET type = 'direct' WHERE id = 1").Error; err != nil {
		t.Fatal(err)
	}
	if err := db.Exec("DELETE FROM chat_members WHERE conversation_id = 1 AND userid = 'carol'").Error; err != nil {
		t.Fatal(err)
	}
}

func callEvent(kind, callID, deviceID string) RealtimeEvent {
	event := RealtimeEvent{
		Type: kind, CallID: callID, ConversationID: 1, SourceDeviceID: deviceID,
	}
	if kind == "call.offer" || kind == "call.answer" || kind == "call.ice" {
		event.Signal = json.RawMessage(`{"type":"test"}`)
	}
	return event
}

func TestCallAcceptIsAtomicAcrossDevices(t *testing.T) {
	setupDirectCallTest(t)
	callID := uuid.NewString()
	invite, err := CallServiceInstance.ProcessEvent("alice", callEvent("call.invite", callID, "caller-device"))
	if err != nil || !invite.ShouldBroadcast || invite.Call.Status != "ringing" {
		t.Fatalf("invite failed: transition=%+v err=%v", invite, err)
	}

	type outcome struct {
		device string
		result *CallTransition
		err    error
	}
	results := make(chan outcome, 2)
	var wait sync.WaitGroup
	for _, device := range []string{"bob-phone", "bob-tablet"} {
		wait.Add(1)
		go func(device string) {
			defer wait.Done()
			result, transitionErr := CallServiceInstance.ProcessEvent("bob", callEvent("call.accept", callID, device))
			results <- outcome{device: device, result: result, err: transitionErr}
		}(device)
	}
	wait.Wait()
	close(results)

	winners := 0
	winnerDevice := ""
	conflicts := 0
	for item := range results {
		if item.err == nil && item.result.ShouldBroadcast {
			winners++
			winnerDevice = item.device
		} else if item.err != nil && item.err.Error() == ErrCallConflict {
			conflicts++
		}
	}
	if winners != 1 || conflicts != 1 {
		t.Fatalf("expected one winner and one conflict, got winners=%d conflicts=%d", winners, conflicts)
	}

	duplicate, err := CallServiceInstance.ProcessEvent("bob", callEvent("call.accept", callID, winnerDevice))
	if err != nil || duplicate.ShouldBroadcast {
		t.Fatalf("winning device retry must be idempotent: result=%+v err=%v", duplicate, err)
	}
}

func TestVideoCallMediaTypeIsPersisted(t *testing.T) {
	setupDirectCallTest(t)
	event := callEvent("call.invite", uuid.NewString(), "alice-phone")
	event.MediaType = "video"
	invite, err := CallServiceInstance.ProcessEvent("alice", event)
	if err != nil {
		t.Fatal(err)
	}
	if invite.Call.MediaType != "video" {
		t.Fatalf("expected video media type, got %q", invite.Call.MediaType)
	}
}

func TestCallStateRejectsLateAndOutOfOrderEvents(t *testing.T) {
	setupDirectCallTest(t)
	canceledID := uuid.NewString()
	if _, err := CallServiceInstance.ProcessEvent("alice", callEvent("call.invite", canceledID, "alice-phone")); err != nil {
		t.Fatal(err)
	}
	if _, err := CallServiceInstance.ProcessEvent("alice", callEvent("call.cancel", canceledID, "alice-phone")); err != nil {
		t.Fatal(err)
	}
	if _, err := CallServiceInstance.ProcessEvent("bob", callEvent("call.accept", canceledID, "bob-phone")); err == nil || err.Error() != ErrCallConflict {
		t.Fatalf("accept after cancel should conflict, got %v", err)
	}

	callID := uuid.NewString()
	if _, err := CallServiceInstance.ProcessEvent("alice", callEvent("call.invite", callID, "alice-phone")); err != nil {
		t.Fatal(err)
	}
	if _, err := CallServiceInstance.ProcessEvent("bob", callEvent("call.accept", callID, "bob-phone")); err != nil {
		t.Fatal(err)
	}
	if _, err := CallServiceInstance.ProcessEvent("bob", callEvent("call.answer", callID, "bob-phone")); err == nil || err.Error() != ErrCallInvalidTransition {
		t.Fatalf("answer before offer should be rejected, got %v", err)
	}
	if _, err := CallServiceInstance.ProcessEvent("alice", callEvent("call.offer", callID, "alice-phone")); err != nil {
		t.Fatal(err)
	}
	if _, err := CallServiceInstance.ProcessEvent("bob", callEvent("call.answer", callID, "bob-phone")); err != nil {
		t.Fatal(err)
	}
	ended, err := CallServiceInstance.ProcessEvent("alice", callEvent("call.end", callID, "alice-phone"))
	if err != nil {
		t.Fatal(err)
	}
	if ended.Call.Status != "completed" || ended.Call.EndedAt == nil || ended.Call.AnsweredAt == nil {
		t.Fatalf("completed history is incomplete: %+v", ended.Call)
	}
}
