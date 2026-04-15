package handlers

import (
	"net/http"
	"shareliveloc-api/models"

	"github.com/gin-gonic/gin"
)

func GetConfig(c *gin.Context) {
	key := c.Param("key")

	var config models.AppConfig
	if err := models.DB.Where("key = ?", key).First(&config).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "config not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": config})
}

func GetConfigs(c *gin.Context) {
	var configs []models.AppConfig
	models.DB.Find(&configs)

	result := make(map[string]string)
	for _, cfg := range configs {
		result[cfg.Key] = cfg.Value
	}

	c.JSON(http.StatusOK, gin.H{"data": result})
}
