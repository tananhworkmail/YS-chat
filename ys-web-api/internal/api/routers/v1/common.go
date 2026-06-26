package router_v1

import (
	"web-api/internal/api/controllers"

	"github.com/gin-gonic/gin"
)

func RegisterCommonRouter(router *gin.RouterGroup) {
	router.GET("/ping", controllers.Common.Ping)
}
