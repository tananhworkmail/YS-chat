package services

import (
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base64"
	"strings"
	"testing"

	"web-api/internal/pkg/config"
)

func TestBuildICEConfigurationUsesShortLivedTURNCredential(t *testing.T) {
	previous := config.Config
	config.Config = &config.Configuration{WebRTC: config.WebRTCConfiguration{
		STUNURLs: []string{"stun:stun.example.test:3478"},
		TURNURLs: []string{"turn:turn.example.test:3478"},
		TURNCredentialTTLSeconds: 600,
	}}
	t.Cleanup(func() { config.Config = previous })
	t.Setenv("TURN_SHARED_SECRET", "unit-test-shared-secret")
	t.Setenv("TURN_USERNAME", "")
	t.Setenv("TURN_CREDENTIAL", "")

	result := BuildICEConfiguration("alice")
	if len(result.ICEServers) != 2 {
		t.Fatalf("expected STUN and TURN entries, got %+v", result.ICEServers)
	}
	turn := result.ICEServers[1]
	if !strings.HasSuffix(turn.Username, ":alice") {
		t.Fatalf("unexpected short-lived username: %q", turn.Username)
	}
	mac := hmac.New(sha1.New, []byte("unit-test-shared-secret"))
	_, _ = mac.Write([]byte(turn.Username))
	expected := base64.StdEncoding.EncodeToString(mac.Sum(nil))
	if turn.Credential != expected {
		t.Fatal("TURN REST credential does not match its short-lived username")
	}
	if strings.Contains(turn.Credential, "unit-test-shared-secret") {
		t.Fatal("shared secret leaked into ICE response")
	}
}
