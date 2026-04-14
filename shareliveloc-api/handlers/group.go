package handlers

import (
	"net/http"
	"shareliveloc-api/models"

	"github.com/gin-gonic/gin"
)

func CreateGroup(c *gin.Context) {
	var input struct {
		Name string `json:"name" binding:"required"`
	}
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "name is required"})
		return
	}

	group := models.Group{Name: input.Name}
	if err := models.DB.Create(&group).Error; err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "group name already exists"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"data": group})
}

func GetGroups(c *gin.Context) {
	search := c.Query("search")
	activeOnly := c.Query("active_only")

	baseQuery := models.DB.Model(&models.Group{})
	if activeOnly == "true" {
		baseQuery = baseQuery.Where("id IN (?)",
			models.DB.Model(&models.Share{}).Select("group_id").Where("is_active = ?", true),
		)
	}

	var totalCount int64
	baseQuery.Count(&totalCount)

	var groups []models.Group

	if totalCount <= 5 {
		baseQuery.Order("name asc").Find(&groups)
	} else {
		if len(search) < 3 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "search requires at least 3 characters"})
			return
		}
		baseQuery.Where("name ILIKE ?", "%"+search+"%").Order("name asc").Find(&groups)
	}

	c.JSON(http.StatusOK, gin.H{"data": groups, "total": totalCount})
}

func GetGroup(c *gin.Context) {
	var group models.Group
	if err := models.DB.First(&group, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "group not found"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": group})
}
