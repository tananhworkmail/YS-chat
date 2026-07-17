package middlewares

import (
	"testing"

	"web-api/internal/pkg/config"
)

func TestRealtimeTicketIsScopedAndVerifiable(t *testing.T) {
	previous := config.Config
	config.Config = &config.Configuration{Server: config.ServerConfiguration{Secret: "realtime-ticket-test"}}
	t.Cleanup(func() { config.Config = previous })

	ticket, expiresIn, err := IssueRealtimeTicket("alice", "Alice")
	if err != nil {
		t.Fatal(err)
	}
	if expiresIn != 30 {
		t.Fatalf("unexpected ticket TTL: %d", expiresIn)
	}
	userid, fullname, ok := VerifyRealtimeTicket(ticket)
	if !ok || userid != "alice" || fullname != "Alice" {
		t.Fatalf("ticket claims were not preserved: %q %q %v", userid, fullname, ok)
	}
	if _, _, ok := VerifyRealtimeTicket(ticket + "tampered"); ok {
		t.Fatal("tampered ticket should be rejected")
	}
}
