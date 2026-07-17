package services

import (
	"context"
	"testing"
)

func TestInMemoryRealtimeEventBusPublishesEnvelope(t *testing.T) {
	bus := NewInMemoryRealtimeEventBus()
	received := make(chan RealtimeEnvelope, 1)
	if err := bus.Subscribe(func(envelope RealtimeEnvelope) { received <- envelope }); err != nil {
		t.Fatal(err)
	}
	expected := RealtimeEnvelope{Userids: []string{"alice"}, Event: RealtimeEvent{Type: "chat.test"}}
	if err := bus.Publish(context.Background(), expected); err != nil {
		t.Fatal(err)
	}
	actual := <-received
	if len(actual.Userids) != 1 || actual.Userids[0] != "alice" || actual.Event.Type != "chat.test" {
		t.Fatalf("unexpected envelope: %+v", actual)
	}
	if err := bus.Close(); err != nil {
		t.Fatal(err)
	}
	if err := bus.Publish(context.Background(), expected); err == nil {
		t.Fatal("publish after close should fail")
	}
}
