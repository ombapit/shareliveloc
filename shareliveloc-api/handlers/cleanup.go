package handlers

import (
	"log"
	"shareliveloc-api/models"
	"time"
)

const (
	staleThreshold  = 5 * time.Minute
	cleanupInterval = 1 * time.Minute
)

// StartCleanupJob runs a background goroutine that periodically marks stale
// active shares (no location update within staleThreshold) as inactive.
// This handles cases where the mobile app was uninstalled, device died,
// or the background service was killed without calling /stop.
func StartCleanupJob() {
	go func() {
		ticker := time.NewTicker(cleanupInterval)
		defer ticker.Stop()
		for range ticker.C {
			cleanupStaleShares()
		}
	}()
}

func cleanupStaleShares() {
	threshold := time.Now().Add(-staleThreshold)

	var stale []models.Share
	models.DB.
		Where("is_active = ? AND updated_at < ?", true, threshold).
		Find(&stale)

	if len(stale) == 0 {
		return
	}

	log.Printf("[cleanup] found %d stale active shares, marking inactive", len(stale))

	for _, share := range stale {
		models.DB.Model(&share).Update("is_active", false)

		WsHub.Broadcast(share.GroupID, LocationBroadcast{
			ShareID:       share.ID,
			Name:          share.Name,
			Icon:          share.Icon,
			Latitude:      share.Latitude,
			Longitude:     share.Longitude,
			DurationHours: share.DurationHours,
			IsActive:      false,
			UpdatedAt:     time.Now().Format(time.RFC3339),
		})
	}
}
