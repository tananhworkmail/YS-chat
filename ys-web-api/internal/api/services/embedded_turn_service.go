package services

import (
	"crypto/subtle"
	"errors"
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"

	"web-api/internal/pkg/config"

	"github.com/pion/logging"
	"github.com/pion/turn/v4"
)

const (
	defaultTURNListenAddress = "0.0.0.0:3478"
	defaultTURNRealm         = "ys-chat"
	defaultTURNMinPort       = 49160
	defaultTURNMaxPort       = 49200
)

// EmbeddedTURNServer owns the UDP/TCP listeners used by the in-process TURN
// relay. Pion closes the listeners when Server.Close is called.
type EmbeddedTURNServer struct {
	server *turn.Server
}

func (s *EmbeddedTURNServer) Close() error {
	if s == nil || s.server == nil {
		return nil
	}
	return s.server.Close()
}

// StartEmbeddedTURN starts an authenticated relay when enabled and adds its
// URLs to the ICE response when no explicit TURN URLs were configured.
func StartEmbeddedTURN(configuration *config.WebRTCConfiguration) (*EmbeddedTURNServer, error) {
	if configuration == nil || !configuration.EmbeddedTURNEnabled {
		return nil, nil
	}

	relayIP := net.ParseIP(strings.TrimSpace(configuration.EmbeddedTURNRelayIP))
	if relayIP == nil || relayIP.To4() == nil {
		return nil, errors.New("webrtc.embeddedTURNRelayIP must be a reachable IPv4 address")
	}

	listenAddress := strings.TrimSpace(configuration.EmbeddedTURNListenAddress)
	if listenAddress == "" {
		listenAddress = defaultTURNListenAddress
	}
	host, port, err := net.SplitHostPort(listenAddress)
	if err != nil {
		return nil, fmt.Errorf("invalid webrtc.embeddedTURNListenAddress: %w", err)
	}
	if host == "" {
		host = "0.0.0.0"
	}
	portNumber, err := strconv.Atoi(port)
	if err != nil || portNumber <= 0 || portNumber > 65535 {
		return nil, errors.New("webrtc.embeddedTURNListenAddress must use a port between 1 and 65535")
	}

	minPort, maxPort, err := embeddedTURNPortRange(configuration)
	if err != nil {
		return nil, err
	}
	realm := strings.TrimSpace(configuration.EmbeddedTURNRealm)
	if realm == "" {
		realm = defaultTURNRealm
	}
	authHandler, err := embeddedTURNAuthHandler(configuration, realm)
	if err != nil {
		return nil, err
	}

	udpListener, err := net.ListenPacket("udp4", listenAddress)
	if err != nil {
		return nil, fmt.Errorf("listen for TURN/UDP on %s: %w", listenAddress, err)
	}
	tcpListener, err := net.Listen("tcp4", listenAddress)
	if err != nil {
		_ = udpListener.Close()
		return nil, fmt.Errorf("listen for TURN/TCP on %s: %w", listenAddress, err)
	}

	newRelayGenerator := func() turn.RelayAddressGenerator {
		return &turn.RelayAddressGeneratorPortRange{
			RelayAddress: relayIP.To4(),
			Address:      host,
			MinPort:      minPort,
			MaxPort:      maxPort,
		}
	}
	server, err := turn.NewServer(turn.ServerConfig{
		Realm:       realm,
		AuthHandler: authHandler,
		PacketConnConfigs: []turn.PacketConnConfig{{
			PacketConn:            udpListener,
			RelayAddressGenerator: newRelayGenerator(),
		}},
		ListenerConfigs: []turn.ListenerConfig{{
			Listener:              tcpListener,
			RelayAddressGenerator: newRelayGenerator(),
		}},
	})
	if err != nil {
		_ = tcpListener.Close()
		_ = udpListener.Close()
		return nil, fmt.Errorf("start TURN relay: %w", err)
	}

	if len(validICEURLs(configuration.TURNURLs, "turn:", "turns:")) == 0 {
		hostPort := net.JoinHostPort(relayIP.String(), strconv.Itoa(portNumber))
		configuration.TURNURLs = []string{
			"turn:" + hostPort + "?transport=udp",
			"turn:" + hostPort + "?transport=tcp",
		}
	}
	return &EmbeddedTURNServer{server: server}, nil
}

func embeddedTURNPortRange(configuration *config.WebRTCConfiguration) (uint16, uint16, error) {
	minPort := configuration.EmbeddedTURNMinPort
	maxPort := configuration.EmbeddedTURNMaxPort
	if minPort == 0 {
		minPort = defaultTURNMinPort
	}
	if maxPort == 0 {
		maxPort = defaultTURNMaxPort
	}
	if minPort <= 0 || maxPort > 65535 || minPort > maxPort {
		return 0, 0, errors.New("invalid embedded TURN relay port range")
	}
	return uint16(minPort), uint16(maxPort), nil
}

func embeddedTURNAuthHandler(configuration *config.WebRTCConfiguration, realm string) (turn.AuthHandler, error) {
	sharedSecret := strings.TrimSpace(os.Getenv("TURN_SHARED_SECRET"))
	if sharedSecret != "" {
		logger := logging.NewDefaultLoggerFactory().NewLogger("turn-auth")
		return turn.LongTermTURNRESTAuthHandler(sharedSecret, logger), nil
	}

	username := firstNonEmpty(os.Getenv("TURN_USERNAME"), configuration.TURNUsername)
	credential := firstNonEmpty(os.Getenv("TURN_CREDENTIAL"), configuration.TURNCredential)
	if username == "" || credential == "" {
		return nil, errors.New("embedded TURN requires TURN_SHARED_SECRET or TURN username and credential")
	}
	authKey := turn.GenerateAuthKey(username, realm, credential)
	return func(candidateUsername, _ string, _ net.Addr) ([]byte, bool) {
		if subtle.ConstantTimeCompare([]byte(candidateUsername), []byte(username)) != 1 {
			return nil, false
		}
		return authKey, true
	}, nil
}
