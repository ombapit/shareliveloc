package main

import (
	"shareliveloc-api/handlers"
	"shareliveloc-api/models"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
)

func main() {
	models.InitDB()

	handlers.StartCleanupJob()

	r := gin.Default()

	r.Use(cors.New(cors.Config{
		AllowAllOrigins:  true,
		AllowMethods:     []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Authorization"},
		AllowCredentials: true,
	}))

	api := r.Group("/api")
	{
		api.POST("/groups", handlers.CreateGroup)
		api.GET("/groups", handlers.GetGroups)
		api.GET("/groups/:id", handlers.GetGroup)

		api.POST("/shares", handlers.CreateShare)
		api.PUT("/shares/:id/location", handlers.UpdateLocation)
		api.PUT("/shares/:id/stop", handlers.StopShare)
		api.GET("/shares", handlers.GetShares)
		api.GET("/shares/:id", handlers.GetShare)

		api.GET("/config", handlers.GetConfigs)
		api.GET("/config/:key", handlers.GetConfig)
	}

	r.GET("/ws/location/:group_id", handlers.HandleWebSocket)

	r.Run(":8080")
}
