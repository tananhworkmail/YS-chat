package services

import (
	"fmt"
	"net"
	"testing"

	"web-api/internal/pkg/config"

	"github.com/pion/logging"
	"github.com/pion/turn/v4"
)

func TestEmbeddedTURNAllocatesAuthenticatedRelay(t *testing.T) {
	t.Setenv("TURN_SHARED_SECRET", "")
	t.Setenv("TURN_USERNAME", "")
	t.Setenv("TURN_CREDENTIAL", "")

	listener, err := net.ListenPacket("udp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := listener.LocalAddr().(*net.UDPAddr).Port
	_ = listener.Close()

	configuration := config.WebRTCConfiguration{
		EmbeddedTURNEnabled:       true,
		EmbeddedTURNListenAddress: fmt.Sprintf("127.0.0.1:%d", port),
		EmbeddedTURNRelayIP:       "127.0.0.1",
		EmbeddedTURNRealm:         "ys-chat-test",
		EmbeddedTURNMinPort:       55000,
		EmbeddedTURNMaxPort:       55100,
		TURNUsername:              "test-user",
		TURNCredential:            "test-password",
	}
	server, err := StartEmbeddedTURN(&configuration)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = server.Close() })
	if len(configuration.TURNURLs) != 2 {
		t.Fatalf("expected UDP and TCP TURN URLs, got %+v", configuration.TURNURLs)
	}

	clientConn, err := net.ListenPacket("udp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = clientConn.Close() })
	client, err := turn.NewClient(&turn.ClientConfig{
		STUNServerAddr: fmt.Sprintf("127.0.0.1:%d", port),
		TURNServerAddr: fmt.Sprintf("127.0.0.1:%d", port),
		Conn:           clientConn,
		Username:       configuration.TURNUsername,
		Password:       configuration.TURNCredential,
		Realm:          configuration.EmbeddedTURNRealm,
		LoggerFactory:  logging.NewDefaultLoggerFactory(),
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(client.Close)
	if err := client.Listen(); err != nil {
		t.Fatal(err)
	}
	relay, err := client.Allocate()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = relay.Close() })
	address, ok := relay.LocalAddr().(*net.UDPAddr)
	if !ok || !address.IP.Equal(net.ParseIP("127.0.0.1")) {
		t.Fatalf("unexpected relay address: %v", relay.LocalAddr())
	}
}
