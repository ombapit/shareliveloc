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
	now := time.Now()
	threshold := now.Add(-staleThreshold)

	var candidates []models.Share
	// Stale (no update in threshold) OR expired (expires_at passed for timed shares)
	models.DB.
		Where("is_active = ? AND (updated_at < ? OR (duration_hours > 0 AND expires_at < ?))",
			true, threshold, now).
		Find(&candidates)

	if len(candidates) == 0 {
		return
	}

	log.Printf("[cleanup] found %d stale/expired active shares, marking inactive", len(candidates))

	for _, share := range candidates {
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
	}
}
