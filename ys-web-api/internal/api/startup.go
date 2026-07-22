package api

import (
	"context"
	"fmt"
	"net/http"
	"os/signal"
	"syscall"
	"time"

	router "web-api/internal/api/routers"
	"web-api/internal/api/services"
	"web-api/internal/pkg/config"
	"web-api/internal/pkg/database"
	"web-api/pkg/logger"

	"github.com/gin-gonic/gin"
)

func Run(configPath string) {
	if configPath == "" {
		configPath = "data/config.yml"
	}
	if err := config.Setup(configPath); err != nil {
		logger.Fatalf("failed to setup config, %s", err)
	}
	if err := database.Setup(); err != nil {
		logger.Fatalf("failed to setup database, %s", err)
	}
	if err := services.ConfigureRealtimeHub(config.GetConfig().Realtime); err != nil {
		logger.Fatalf("failed to setup realtime event bus, %s", err)
	}
	turnServer, err := services.StartEmbeddedTURN(&config.GetConfig().WebRTC)
	if err != nil {
		logger.Fatalf("failed to setup embedded TURN relay, %s", err)
	}

	gin.SetMode(config.GetConfig().Server.Mode)

	config := config.GetConfig()

	web := router.Setup()

	fmt.Println("Web API Running on port " + config.Server.Port)
	fmt.Println("================================>")
	server := &http.Server{
		Addr:              ":" + config.Server.Port,
		Handler:           web,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       75 * time.Second,
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	services.CallServiceInstance.StartReaper(ctx, config.WebRTC)
	services.ReminderServiceInstance.StartScheduler(ctx)
	shutdownDone := make(chan struct{})
	go func() {
		defer close(shutdownDone)
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdownCtx)
		_ = services.RealtimeHubInstance.Shutdown(shutdownCtx)
		if turnServer != nil {
			_ = turnServer.Close()
		}
	}()
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		logger.Fatalf("%v", err)
	}
	if ctx.Err() != nil {
		<-shutdownDone
	}
}
