package router_v1

import (
	"web-api/internal/api/controllers"
	"web-api/internal/api/middlewares"

	"github.com/gin-gonic/gin"
)

func ChatRouter(router *gin.RouterGroup) {
	chat := router.Group("/chat")
	chat.POST("/realtime/ticket", middlewares.AuthRequired(), controllers.Chat.RealtimeTicket)
	chat.GET("/realtime", middlewares.RealtimeAuthRequired(), controllers.Chat.Realtime)
	chat.Use(middlewares.AuthRequired())

	chat.GET("/users", controllers.Chat.SearchUsers)
	chat.GET("/search", controllers.Chat.Search)
	chat.GET("/contacts", controllers.Chat.ListContacts)
	chat.POST("/contacts", controllers.Chat.AddContact)
	chat.PUT("/contacts/:userid/nickname", controllers.Chat.UpdateContactNickname)
	chat.GET("/realtime/health", controllers.Chat.RealtimeHealth)
	chat.POST("/devices", controllers.Chat.RegisterDeviceToken)
	chat.DELETE("/devices", controllers.Chat.UnregisterDeviceToken)
	chat.POST("/calls/events", controllers.Chat.SendCallEvent)
	chat.GET("/calls/ice-config", controllers.Chat.ICEConfiguration)
	chat.GET("/calls/history", controllers.Chat.CallHistory)
	chat.GET("/calls/:id", controllers.Chat.GetCall)
	chat.GET("/conversations", controllers.Chat.ListConversations)
	chat.POST("/conversations/direct", controllers.Chat.CreateDirectConversation)
	chat.POST("/conversations/group", controllers.Chat.CreateGroupConversation)
	chat.PUT("/conversations/:id/settings", controllers.Chat.UpdateConversationSettings)
	chat.PATCH("/conversations/:id/user-settings", controllers.Chat.UpdateConversationUserSettings)
	chat.POST("/conversations/:id/members", controllers.Chat.AddMembers)
	chat.PUT("/conversations/:id/members/:userid/nickname", controllers.Chat.UpdateMemberNickname)
	chat.DELETE("/conversations/:id/members/:userid", controllers.Chat.RemoveMember)
	chat.GET("/conversations/:id/messages", controllers.Chat.ListMessages)
	chat.GET("/conversations/:id/messages/catch-up", controllers.Chat.CatchUpMessages)
	chat.GET("/conversations/:id/messages/search", controllers.Chat.SearchConversationMessages)
	chat.POST("/conversations/:id/messages", controllers.Chat.SendMessage)
	chat.POST("/conversations/:id/read", controllers.Chat.MarkRead)
	chat.POST("/conversations/:id/delivered", controllers.Chat.MarkDelivered)
	chat.POST("/conversations/:id/typing", controllers.Chat.SetTyping)
	chat.PUT("/conversations/:id/pinned-message", controllers.Chat.SetPinnedMessage)
	chat.GET("/conversations/:id/reminders", controllers.Chat.ListReminders)
	chat.POST("/conversations/:id/reminders", controllers.Chat.CreateReminder)
	chat.DELETE("/reminders/:id", controllers.Chat.CancelReminder)
	chat.GET("/messages/:id/edit-history", controllers.Chat.GetMessageEditHistory)
	chat.PATCH("/messages/:id", controllers.Chat.EditMessage)
	chat.POST("/messages/:id/recall", controllers.Chat.RecallMessage)
	chat.DELETE("/messages/:id", controllers.Chat.DeleteMessageForMe)
	chat.PUT("/messages/:id/reactions/:emoji", controllers.Chat.AddReaction)
	chat.DELETE("/messages/:id/reactions/:emoji", controllers.Chat.RemoveReaction)
	// Body-based aliases are kept for clients released during the transition.
	chat.POST("/messages/:id/reactions", controllers.Chat.AddReaction)
	chat.DELETE("/messages/:id/reactions", controllers.Chat.RemoveReaction)
	chat.POST("/conversations/:id/polls", controllers.Chat.CreatePoll)
	chat.POST("/messages/:id/poll/votes", controllers.Chat.VotePoll)
	chat.POST("/messages/:id/poll/close", controllers.Chat.ClosePoll)
	chat.POST("/uploads", controllers.Chat.UploadFiles)
}
