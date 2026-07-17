package middlewares

import (
	"net/http"
	"strings"
	"time"

	"github.com/dgrijalva/jwt-go"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"web-api/internal/pkg/config"
)

var authJWTSecret = []byte("TYTHAC@123")

func VerifyToken(tokenString string) (string, string, bool) {
	tokenString = strings.TrimSpace(strings.TrimPrefix(tokenString, "Bearer "))
	if tokenString == "" {
		return "", "", false
	}

	token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, jwt.ErrSignatureInvalid
		}
		return authJWTSecret, nil
	})
	if err != nil || !token.Valid {
		return "", "", false
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return "", "", false
	}

	userid, ok := claims["userid"].(string)
	if !ok || strings.TrimSpace(userid) == "" {
		return "", "", false
	}

	fullname, _ := claims["fullname"].(string)
	return userid, fullname, true
}

func IssueRealtimeTicket(userid, fullname string) (string, int, error) {
	const ttlSeconds = 30
	now := time.Now().UTC()
	claims := jwt.MapClaims{
		"userid":   strings.TrimSpace(userid),
		"fullname": strings.TrimSpace(fullname),
		"purpose":  "realtime",
		"jti":      uuid.NewString(),
		"iat":      now.Unix(),
		"exp":      now.Add(ttlSeconds * time.Second).Unix(),
	}
	ticket := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := ticket.SignedString(realtimeTicketSecret())
	return signed, ttlSeconds, err
}

func VerifyRealtimeTicket(ticketString string) (string, string, bool) {
	ticketString = strings.TrimSpace(ticketString)
	if ticketString == "" {
		return "", "", false
	}
	token, err := jwt.Parse(ticketString, func(token *jwt.Token) (interface{}, error) {
		if token.Method != jwt.SigningMethodHS256 {
			return nil, jwt.ErrSignatureInvalid
		}
		return realtimeTicketSecret(), nil
	})
	if err != nil || !token.Valid {
		return "", "", false
	}
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok || claims["purpose"] != "realtime" {
		return "", "", false
	}
	userid, _ := claims["userid"].(string)
	fullname, _ := claims["fullname"].(string)
	if strings.TrimSpace(userid) == "" {
		return "", "", false
	}
	return userid, fullname, true
}

func RealtimeAuthRequired() gin.HandlerFunc {
	return func(ctx *gin.Context) {
		userid, fullname, ok := VerifyRealtimeTicket(ctx.Query("ticket"))
		if !ok {
			ctx.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "INVALID_REALTIME_TICKET"})
			return
		}
		ctx.Set("userid", userid)
		if fullname != "" {
			ctx.Set("fullname", fullname)
		}
		ctx.Next()
	}
}

func realtimeTicketSecret() []byte {
	if current := config.GetConfig(); current != nil {
		if secret := strings.TrimSpace(current.Server.Secret); secret != "" {
			return []byte(secret)
		}
	}
	return authJWTSecret
}

func AuthRequired() gin.HandlerFunc {
	return func(ctx *gin.Context) {
		header := ctx.GetHeader("Authorization")
		tokenString := header
		if strings.TrimSpace(tokenString) == "" {
			tokenString = ctx.Query("token")
		}
		if strings.TrimSpace(tokenString) == "" {
			tokenString = ctx.Query("access_token")
		}

		userid, fullname, ok := VerifyToken(tokenString)
		if !ok {
			ctx.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "UNAUTHORIZED"})
			return
		}

		ctx.Set("userid", userid)
		if fullname != "" {
			ctx.Set("fullname", fullname)
		}
		ctx.Next()
	}
}
