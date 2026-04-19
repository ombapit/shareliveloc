package handlers

import (
	"net/http"
	"shareliveloc-api/models"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
)

func CreateMessage(c *gin.Context) {
	groupIDStr := c.Param("id")
	groupID, err := strconv.ParseUint(groupIDStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group id"})
		return
	}

	var group models.Group
	if err := models.DB.First(&group, groupID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "group not found"})
		return
	}

	var input struct {
		SenderName string `json:"sender_name" binding:"required"`
		Content    string `json:"content" binding:"required"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	msg := models.Message{
		GroupID:    uint(groupID),
		SenderName: input.SenderName,
		Content:    input.Content,
	}
	models.DB.Create(&msg)

	WsHub.Broadcast(uint(groupID), MessageBroadcast{
		Type:       "message",
		MessageID:  msg.ID,
		GroupID:    msg.GroupID,
		SenderName: msg.SenderName,
		Content:    msg.Content,
		CreatedAt:  msg.CreatedAt.Format(time.RFC3339),
	})

	c.JSON(http.StatusCreated, gin.H{"data": msg})
}

func GetMessages(c *gin.Context) {
	groupIDStr := c.Param("id")
	groupID, err := strconv.ParseUint(groupIDStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group id"})
		return
	}

	limit := 50
	if l := c.Query("limit"); l != "" {
		if parsed, err := strconv.Atoi(l); err == nil && parsed > 0 && parsed <= 200 {
			limit = parsed
		}
	}

	query := models.DB.Where("group_id = ?", groupID)

	// Optional: only return messages after a given ID (client has cleared local)
	if since := c.Query("since"); since != "" {
		if sinceID, err := strconv.Atoi(since); err == nil {
			query = query.Where("id > ?", sinceID)
		}
	}

	var messages []models.Message
	query.Order("created_at desc").Limit(limit).Find(&messages)

	// Reverse to chronological (oldest first)
	for i, j := 0, len(messages)-1; i < j; i, j = i+1, j-1 {
		messages[i], messages[j] = messages[j], messages[i]
	}

	c.JSON(http.StatusOK, gin.H{"data": messages})
}
