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

type Hub struct {
	mu    sync.RWMutex
	rooms map[uint]map[*websocket.Conn]bool
}

var WsHub = &Hub{
	rooms: make(map[uint]map[*websocket.Conn]bool),
}

func (h *Hub) Register(groupID uint, conn *websocket.Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.rooms[groupID] == nil {
		h.rooms[groupID] = make(map[*websocket.Conn]bool)
	}
	h.rooms[groupID][conn] = true
}

func (h *Hub) Unregister(groupID uint, conn *websocket.Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if clients, ok := h.rooms[groupID]; ok {
		delete(clients, conn)
		if len(clients) == 0 {
			delete(h.rooms, groupID)
		}
	}
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

	go func() {
		defer func() {
			WsHub.Unregister(gid, conn)
			conn.Close()
		}()
		for {
			if _, _, err := conn.ReadMessage(); err != nil {
				break
			}
		}
	}()
}
