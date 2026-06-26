package router_v1

import (
	"web-api/internal/api/controllers"
	"web-api/internal/api/middlewares"

	"github.com/gin-gonic/gin"
)

func ProfileRouter(router *gin.RouterGroup) {
	profile := router.Group("/profile")
	profile.Use(middlewares.AuthRequired())

	profile.GET("", controllers.Profile.Me)
	profile.PUT("", controllers.Profile.UpdateProfile)
	profile.PUT("/password", controllers.Profile.ChangePassword)
	profile.POST("/avatar", controllers.Profile.UploadAvatar)
}
