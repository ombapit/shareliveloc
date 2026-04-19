package handlers

import (
	"net/http"
	"shareliveloc-api/models"
	"time"

	"github.com/gin-gonic/gin"
)

func formatExpiresAt(t time.Time) string {
	if t.IsZero() {
		return ""
	}
	return t.Format(time.RFC3339)
}

func CreateShare(c *gin.Context) {
	var input struct {
		Name          string `json:"name" binding:"required"`
		Icon          string `json:"icon" binding:"required"`
		GroupName     string `json:"group_name" binding:"required"`
		DurationHours int    `json:"duration_hours" binding:"min=0,max=8"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var group models.Group
	result := models.DB.Where("name = ?", input.GroupName).First(&group)
	if result.Error != nil {
		group = models.Group{Name: input.GroupName}
		if err := models.DB.Create(&group).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create group"})
			return
		}
	}

	share := models.Share{
		Name:     input.Name,
		Icon:     input.Icon,
		GroupID:  group.ID,
		IsActive: true,
	}
	if input.DurationHours > 0 {
		share.DurationHours = input.DurationHours
		share.ExpiresAt = time.Now().Add(time.Duration(input.DurationHours) * time.Hour)
	}
	models.DB.Create(&share)

	WsHub.Broadcast(share.GroupID, LocationBroadcast{
		Type:          "location",
		ShareID:       share.ID,
		Name:          share.Name,
		Icon:          share.Icon,
		Latitude:      share.Latitude,
		Longitude:     share.Longitude,
		DurationHours: share.DurationHours,
		ExpiresAt:     formatExpiresAt(share.ExpiresAt),
		IsActive:      true,
		UpdatedAt:     time.Now().Format(time.RFC3339),
	})

	c.JSON(http.StatusCreated, gin.H{"data": share})
}

func UpdateLocation(c *gin.Context) {
	var share models.Share
	if err := models.DB.First(&share, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "share not found"})
		return
	}

	if !share.IsActive {
		c.JSON(http.StatusBadRequest, gin.H{"error": "share is not active"})
		return
	}

	if share.DurationHours > 0 && time.Now().After(share.ExpiresAt) {
		models.DB.Model(&share).Update("is_active", false)
		WsHub.Broadcast(share.GroupID, LocationBroadcast{
			Type:          "location",
			ShareID:       share.ID,
			Name:          share.Name,
			Icon:          share.Icon,
			Latitude:      share.Latitude,
			Longitude:     share.Longitude,
			DurationHours: share.DurationHours,
			IsActive:      false,
			UpdatedAt:     time.Now().Format(time.RFC3339),
		})
		c.JSON(http.StatusBadRequest, gin.H{"error": "share has expired"})
		return
	}

	var input struct {
		Latitude  float64 `json:"latitude" binding:"required"`
		Longitude float64 `json:"longitude" binding:"required"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	models.DB.Model(&share).Updates(map[string]interface{}{
		"latitude":  input.Latitude,
		"longitude": input.Longitude,
	})

	WsHub.Broadcast(share.GroupID, LocationBroadcast{
		Type:          "location",
		ShareID:       share.ID,
		Name:          share.Name,
		Icon:          share.Icon,
		Latitude:      input.Latitude,
		Longitude:     input.Longitude,
		DurationHours: share.DurationHours,
		ExpiresAt:     formatExpiresAt(share.ExpiresAt),
		IsActive:      true,
		UpdatedAt:     time.Now().Format(time.RFC3339),
	})

	c.JSON(http.StatusOK, gin.H{"data": share})
}

func StopShare(c *gin.Context) {
	var share models.Share
	if err := models.DB.First(&share, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "share not found"})
		return
	}

	models.DB.Model(&share).Update("is_active", false)

	WsHub.Broadcast(share.GroupID, LocationBroadcast{
		Type:          "location",
		ShareID:       share.ID,
		Name:          share.Name,
		Icon:          share.Icon,
		Latitude:      share.Latitude,
		Longitude:     share.Longitude,
		DurationHours: share.DurationHours,
		ExpiresAt:     formatExpiresAt(share.ExpiresAt),
		IsActive:      false,
		UpdatedAt:     time.Now().Format(time.RFC3339),
	})

	c.JSON(http.StatusOK, gin.H{"data": "sharing stopped"})
}

func GetShare(c *gin.Context) {
	var share models.Share
	if err := models.DB.First(&share, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "share not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": share})
}

func GetShares(c *gin.Context) {
	groupID := c.Query("group_id")
	if groupID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "group_id is required"})
		return
	}

	var shares []models.Share
	models.DB.Where("group_id = ? AND is_active = ?", groupID, true).Find(&shares)
	c.JSON(http.StatusOK, gin.H{"data": shares})
}
