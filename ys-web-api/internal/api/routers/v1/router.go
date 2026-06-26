package router_v1

import (
	"github.com/gin-gonic/gin"
)

func Register(router *gin.Engine) {
	v1 := router.Group("/api/v1")

	RegisterCommonRouter(v1.Group(""))

	AuthRouter(v1.Group("/auth"))
	ChatRouter(v1.Group(""))
	ProfileRouter(v1.Group(""))

}
