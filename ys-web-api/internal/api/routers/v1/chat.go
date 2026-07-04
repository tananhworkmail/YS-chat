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
	chat.GET("/search", controllers.Chat.Search)
	chat.GET("/contacts", controllers.Chat.ListContacts)
	chat.POST("/contacts", controllers.Chat.AddContact)
	chat.GET("/realtime/health", controllers.Chat.RealtimeHealth)
	chat.GET("/realtime", controllers.Chat.Realtime)
	chat.POST("/devices", controllers.Chat.RegisterDeviceToken)
	chat.GET("/conversations", controllers.Chat.ListConversations)
	chat.POST("/conversations/direct", controllers.Chat.CreateDirectConversation)
	chat.POST("/conversations/group", controllers.Chat.CreateGroupConversation)
	chat.PUT("/conversations/:id/settings", controllers.Chat.UpdateConversationSettings)
	chat.POST("/conversations/:id/members", controllers.Chat.AddMembers)
	chat.PUT("/conversations/:id/members/:userid/nickname", controllers.Chat.UpdateMemberNickname)
	chat.DELETE("/conversations/:id/members/:userid", controllers.Chat.RemoveMember)
	chat.GET("/conversations/:id/messages", controllers.Chat.ListMessages)
	chat.POST("/conversations/:id/messages", controllers.Chat.SendMessage)
	chat.POST("/conversations/:id/polls", controllers.Chat.CreatePoll)
	chat.POST("/messages/:id/poll/votes", controllers.Chat.VotePoll)
	chat.POST("/messages/:id/poll/close", controllers.Chat.ClosePoll)
	chat.POST("/uploads", controllers.Chat.UploadFiles)
}
