package router_v1

import (
	"web-api/internal/api/controllers"
	"web-api/internal/api/middlewares"

	"github.com/gin-gonic/gin"
)

func ChatRouter(router *gin.RouterGroup) {
	chat := router.Group("/chat")
	chat.Use(middlewares.AuthRequired())

	chat.GET("/users", controllers.Chat.SearchUsers)
	chat.GET("/contacts", controllers.Chat.ListContacts)
	chat.POST("/contacts", controllers.Chat.AddContact)
	chat.GET("/realtime", controllers.Chat.Realtime)
	chat.POST("/devices", controllers.Chat.RegisterDeviceToken)
	chat.GET("/conversations", controllers.Chat.ListConversations)
	chat.POST("/conversations/direct", controllers.Chat.CreateDirectConversation)
	chat.POST("/conversations/group", controllers.Chat.CreateGroupConversation)
	chat.POST("/conversations/:id/members", controllers.Chat.AddMembers)
	chat.DELETE("/conversations/:id/members/:userid", controllers.Chat.RemoveMember)
	chat.GET("/conversations/:id/messages", controllers.Chat.ListMessages)
	chat.POST("/conversations/:id/messages", controllers.Chat.SendMessage)
	chat.POST("/uploads", controllers.Chat.UploadFiles)
}
