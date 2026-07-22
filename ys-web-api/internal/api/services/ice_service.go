package services

import (
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base64"
	"os"
	"strconv"
	"strings"
	"time"

	"web-api/internal/pkg/config"
)

const defaultSTUNURL = "stun:stun.l.google.com:19302"

type ICEConfiguration struct {
	ICEServers []ICEServer `json:"iceServers"`
	ExpiresAt  time.Time   `json:"expiresAt"`
}

type ICEServer struct {
	URLs       []string `json:"urls"`
	Username   string   `json:"username,omitempty"`
	Credential string   `json:"credential,omitempty"`
}

func BuildICEConfiguration(userid string) ICEConfiguration {
	configuration := config.WebRTCConfiguration{}
	if current := config.GetConfig(); current != nil {
		configuration = current.WebRTC
	}
	ttl := time.Duration(configuration.TURNCredentialTTLSeconds) * time.Second
	if ttl <= 0 || ttl > 24*time.Hour {
		ttl = time.Hour
	}
	expiresAt := time.Now().UTC().Add(ttl)
	result := ICEConfiguration{ICEServers: []ICEServer{}, ExpiresAt: expiresAt}
	stunURLs := validICEURLs(configuration.STUNURLs, "stun:", "stuns:")
	if len(stunURLs) == 0 {
		stunURLs = []string{defaultSTUNURL}
	}
	result.ICEServers = append(result.ICEServers, ICEServer{URLs: stunURLs})
	turnURLs := validICEURLs(configuration.TURNURLs, "turn:", "turns:")
	if len(turnURLs) == 0 {
		return result
	}

	sharedSecret := strings.TrimSpace(os.Getenv("TURN_SHARED_SECRET"))
	username := ""
	credential := ""
	if sharedSecret != "" {
		// coturn's REST API accepts an expiry Unix timestamp as the username
		// prefix. Keep the calculation separate so the shared secret is never
		// returned or logged.
		username = strings.Join([]string{
			formatUnix(expiresAt.Unix()),
			strings.TrimSpace(userid),
		}, ":")
		mac := hmac.New(sha1.New, []byte(sharedSecret))
		_, _ = mac.Write([]byte(username))
		credential = base64.StdEncoding.EncodeToString(mac.Sum(nil))
	} else {
		username = firstNonEmpty(os.Getenv("TURN_USERNAME"), configuration.TURNUsername)
		credential = firstNonEmpty(os.Getenv("TURN_CREDENTIAL"), configuration.TURNCredential)
	}
	if username != "" && credential != "" {
		result.ICEServers = append(result.ICEServers, ICEServer{
			URLs: turnURLs, Username: username, Credential: credential,
		})
	}
	return result
}

func validICEURLs(values []string, prefixes ...string) []string {
	result := make([]string, 0, len(values))
	seen := make(map[string]struct{})
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value == "" || len(value) > 1024 {
			continue
		}
		valid := false
		for _, prefix := range prefixes {
			if strings.HasPrefix(strings.ToLower(value), prefix) {
				valid = true
				break
			}
		}
		if !valid {
			continue
		}
		if _, exists := seen[value]; exists {
			continue
		}
		seen[value] = struct{}{}
		result = append(result, value)
	}
	return result
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value = strings.TrimSpace(value); value != "" {
			return value
		}
	}
	return ""
}

func formatUnix(value int64) string {
	return strconv.FormatInt(value, 10)
}
