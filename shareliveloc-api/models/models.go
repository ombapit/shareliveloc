package models

import (
	"fmt"
	"os"
	"time"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

type Group struct {
	ID        uint      `json:"id" gorm:"primaryKey"`
	Name      string    `json:"name" gorm:"uniqueIndex;not null"`
	CreatedAt time.Time `json:"created_at"`
}

type Share struct {
	ID            uint       `json:"id" gorm:"primaryKey"`
	Name          string     `json:"name" gorm:"not null"`
	Icon          string     `json:"icon" gorm:"not null"`
	GroupID       uint       `json:"group_id" gorm:"not null;index"`
	Group         Group      `json:"group,omitempty" gorm:"foreignKey:GroupID"`
	Latitude      float64    `json:"latitude"`
	Longitude     float64    `json:"longitude"`
	DurationHours int        `json:"duration_hours" gorm:"not null;default:0"`
	ExpiresAt     time.Time  `json:"expires_at"`
	IsActive      bool       `json:"is_active" gorm:"default:true"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
}

type AppConfig struct {
	ID    uint   `json:"id" gorm:"primaryKey"`
	Key   string `json:"key" gorm:"uniqueIndex;not null"`
	Value string `json:"value" gorm:"not null"`
}

var DB *gorm.DB

func getEnv(key, fallback string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return fallback
}

func InitDB() {
	dsn := fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		getEnv("DB_HOST", "localhost"),
		getEnv("DB_PORT", "5432"),
		getEnv("DB_USER", "shareliveloc"),
		getEnv("DB_PASSWORD", "shareliveloc"),
		getEnv("DB_NAME", "shareliveloc"),
	)

	var err error
	DB, err = gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		panic("failed to connect database: " + err.Error())
	}

	DB.AutoMigrate(&Group{}, &Share{}, &AppConfig{})

	dropRemovedColumns(&Group{}, &Share{}, &AppConfig{})

	// Seed default configs (only adds missing keys, won't overwrite existing values)
	defaults := map[string]string{
		"ads_enabled":   "false",
		"ads_banner_id": "ca-app-pub-3940256099942544/6300978111",
	}
	for key, val := range defaults {
		var cfg AppConfig
		if err := DB.Where("key = ?", key).First(&cfg).Error; err != nil {
			DB.Create(&AppConfig{Key: key, Value: val})
		}
	}
}

func dropRemovedColumns(models ...interface{}) {
	for _, model := range models {
		stmt := &gorm.Statement{DB: DB}
		stmt.Parse(model)
		tableName := stmt.Schema.Table

		var structColumns []string
		for _, field := range stmt.Schema.Fields {
			if field.DBName != "" {
				structColumns = append(structColumns, field.DBName)
			}
		}

		var dbColumns []string
		rows, err := DB.Raw(
			"SELECT column_name FROM information_schema.columns WHERE table_name = ? AND table_schema = 'public'",
			tableName,
		).Rows()
		if err != nil {
			continue
		}
		for rows.Next() {
			var col string
			rows.Scan(&col)
			dbColumns = append(dbColumns, col)
		}
		rows.Close()

		structMap := make(map[string]bool)
		for _, c := range structColumns {
			structMap[c] = true
		}

		for _, col := range dbColumns {
			if !structMap[col] {
				DB.Exec(fmt.Sprintf("ALTER TABLE %s DROP COLUMN %s", tableName, col))
			}
		}
	}
}
