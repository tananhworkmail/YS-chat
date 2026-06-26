package middlewares

import (
	"net/http"
	"strings"

	"github.com/dgrijalva/jwt-go"
	"github.com/gin-gonic/gin"
)

var authJWTSecret = []byte("TYTHAC@123")

func VerifyToken(tokenString string) (string, string, bool) {
	tokenString = strings.TrimSpace(strings.TrimPrefix(tokenString, "Bearer "))
	if tokenString == "" {
		return "", "", false
	}

	token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
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
