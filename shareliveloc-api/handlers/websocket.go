package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

type LocationBroadcast struct {
	Type          string  `json:"type"`
	ShareID       uint    `json:"share_id"`
	Name          string  `json:"name"`
	Icon          string  `json:"icon"`
	Latitude      float64 `json:"latitude"`
	Longitude     float64 `json:"longitude"`
	DurationHours int     `json:"duration_hours"`
	ExpiresAt     string  `json:"expires_at"`
	TrakteerID    string  `json:"trakteer_id"`
	IsActive      bool    `json:"is_active"`
	UpdatedAt     string  `json:"updated_at"`
}

type MessageBroadcast struct {
	Type       string `json:"type"`
	MessageID  uint   `json:"message_id"`
	GroupID    uint   `json:"group_id"`
	SenderName string `json:"sender_name"`
	Content    string `json:"content"`
	CreatedAt  string `json:"created_at"`
}

type PresenceBroadcast struct {
	Type  string `json:"type"`
	Count int    `json:"count"`
}

type FollowerCountBroadcast struct {
	Type    string `json:"type"`
	ShareID uint   `json:"share_id"`
	Count   int    `json:"count"`
}

type Hub struct {
	mu       sync.RWMutex
	rooms    map[uint]map[*websocket.Conn]bool // group_id -> conns
	follows  map[uint]map[*websocket.Conn]bool // share_id -> followers
	connGrp  map[*websocket.Conn]uint          // conn -> group_id
}

var WsHub = &Hub{
	rooms:   make(map[uint]map[*websocket.Conn]bool),
	follows: make(map[uint]map[*websocket.Conn]bool),
	connGrp: make(map[*websocket.Conn]uint),
}

func (h *Hub) Register(groupID uint, conn *websocket.Conn) {
	h.mu.Lock()
	if h.rooms[groupID] == nil {
		h.rooms[groupID] = make(map[*websocket.Conn]bool)
	}
	h.rooms[groupID][conn] = true
	h.connGrp[conn] = groupID
	count := len(h.rooms[groupID])
	h.mu.Unlock()
	h.broadcastPresence(groupID, count)
}

func (h *Hub) Unregister(groupID uint, conn *websocket.Conn) {
	// Clean up any follows this conn had
	unfollowed := h.unfollowAllInternal(conn)

	h.mu.Lock()
	var count int
	if clients, ok := h.rooms[groupID]; ok {
		delete(clients, conn)
		count = len(clients)
		if count == 0 {
			delete(h.rooms, groupID)
		}
	}
	delete(h.connGrp, conn)
	h.mu.Unlock()

	for shareID, cnt := range unfollowed {
		h.Broadcast(groupID, FollowerCountBroadcast{
			Type:    "follower_count",
			ShareID: shareID,
			Count:   cnt,
		})
	}
	h.broadcastPresence(groupID, count)
}

func (h *Hub) Follow(shareID uint, conn *websocket.Conn) {
	h.mu.Lock()
	if h.follows[shareID] == nil {
		h.follows[shareID] = make(map[*websocket.Conn]bool)
	}
	h.follows[shareID][conn] = true
	count := len(h.follows[shareID])
	groupID := h.connGrp[conn]
	h.mu.Unlock()
	if groupID > 0 {
		h.Broadcast(groupID, FollowerCountBroadcast{
			Type:    "follower_count",
			ShareID: shareID,
			Count:   count,
		})
	}
}

func (h *Hub) Unfollow(shareID uint, conn *websocket.Conn) {
	h.mu.Lock()
	var count int
	if clients, ok := h.follows[shareID]; ok {
		delete(clients, conn)
		count = len(clients)
		if count == 0 {
			delete(h.follows, shareID)
		}
	}
	groupID := h.connGrp[conn]
	h.mu.Unlock()
	if groupID > 0 {
		h.Broadcast(groupID, FollowerCountBroadcast{
			Type:    "follower_count",
			ShareID: shareID,
			Count:   count,
		})
	}
}

func (h *Hub) unfollowAllInternal(conn *websocket.Conn) map[uint]int {
	h.mu.Lock()
	defer h.mu.Unlock()
	result := make(map[uint]int)
	for shareID, clients := range h.follows {
		if clients[conn] {
			delete(clients, conn)
			count := len(clients)
			if count == 0 {
				delete(h.follows, shareID)
			}
			result[shareID] = count
		}
	}
	return result
}

func (h *Hub) FollowerCountsFor(shareIDs []uint) map[uint]int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	result := make(map[uint]int)
	for _, id := range shareIDs {
		result[id] = len(h.follows[id])
	}
	return result
}

func (h *Hub) Count(groupID uint) int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.rooms[groupID])
}

func (h *Hub) broadcastPresence(groupID uint, count int) {
	h.Broadcast(groupID, PresenceBroadcast{
		Type:  "presence",
		Count: count,
	})
}

func (h *Hub) Broadcast(groupID uint, msg interface{}) {
	data, err := json.Marshal(msg)
	if err != nil {
		return
	}
	h.mu.RLock()
	clients := h.rooms[groupID]
	h.mu.RUnlock()

	for conn := range clients {
		conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
		if err := conn.WriteMessage(websocket.TextMessage, data); err != nil {
			conn.Close()
			h.Unregister(groupID, conn)
		}
	}
}

func HandleWebSocket(c *gin.Context) {
	groupIDStr := c.Param("group_id")
	groupID, err := strconv.ParseUint(groupIDStr, 10, 32)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}

	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return
	}

	gid := uint(groupID)
	WsHub.Register(gid, conn)

	// Send initial presence snapshot to the newly connected client
	snapshot := PresenceBroadcast{Type: "presence", Count: WsHub.Count(gid)}
	if data, err := json.Marshal(snapshot); err == nil {
		conn.WriteMessage(websocket.TextMessage, data)
	}

	go func() {
		defer func() {
			WsHub.Unregister(gid, conn)
			conn.Close()
		}()
		for {
			_, data, err := conn.ReadMessage()
			if err != nil {
				break
			}
			var msg map[string]interface{}
			if err := json.Unmarshal(data, &msg); err != nil {
				continue
			}
			msgType, _ := msg["type"].(string)
			shareIDf, _ := msg["share_id"].(float64)
			shareID := uint(shareIDf)
			if shareID == 0 {
				continue
			}
			switch msgType {
			case "follow":
				WsHub.Follow(shareID, conn)
			case "unfollow":
				WsHub.Unfollow(shareID, conn)
			}
		}
	}()
}
