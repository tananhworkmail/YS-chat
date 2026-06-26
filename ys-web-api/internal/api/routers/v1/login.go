package router_v1

import (
	"web-api/internal/api/controllers"

	"github.com/gin-gonic/gin"
)

func AuthRouter(router *gin.RouterGroup) {
	// API Đăng nhập
	router.POST("/login", controllers.Auth.Login)

	// API Đăng ký
	router.POST("/register", controllers.Auth.Register)

	// API Quên mật khẩu
	router.POST("/forgot-password", controllers.Auth.ForgotPassword)
}