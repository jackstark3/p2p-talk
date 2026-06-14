package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin:     func(r *http.Request) bool { return true }, // allow all origins
}

func main() {
	addr := os.Getenv("ADDR")
	if addr == "" {
		addr = ":8080"
	}

	hub := NewHub()
	go hub.Run()

	http.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			log.Printf("upgrade error: %v", err)
			return
		}
		client := &Client{
			hub:  hub,
			conn: conn,
			send: make(chan []byte, 64),
		}
		go client.writePump()
		go client.readPump() // readPump will call hub.register when peerID is set
	})

	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})

	go func() {
		log.Printf("Signaling server listening on %s", addr)
		if err := http.ListenAndServe(addr, nil); err != nil {
			log.Fatalf("listen error: %v", err)
		}
	}()

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down...")
	close(hub.shutdown)
	time.Sleep(100 * time.Millisecond)
}

// ---- Message types ----

type SignalMessage struct {
	Type      string          `json:"type"`
	From      string          `json:"from,omitempty"`
	To        string          `json:"to,omitempty"`
	PeerID    string          `json:"peer_id,omitempty"`
	SDP       json.RawMessage `json:"sdp,omitempty"`
	Candidate json.RawMessage `json:"candidate,omitempty"`
	Status    string          `json:"status,omitempty"`
}

// ---- Client ----

type Client struct {
	hub    *Hub
	conn   *websocket.Conn
	send   chan []byte
	peerID string
}

func (c *Client) readPump() {
	defer func() {
		c.hub.unregister <- c
		c.conn.Close()
	}()

	c.conn.SetReadLimit(65536)
	c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})

	for {
		_, msgBytes, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseNormalClosure) {
				log.Printf("ws read error: %v", err)
			}
			break
		}

		var msg SignalMessage
		if err := json.Unmarshal(msgBytes, &msg); err != nil {
			log.Printf("invalid message: %v", err)
			continue
		}

		switch msg.Type {
		case "register":
			c.peerID = msg.PeerID
			// Only now add to clients map — not before!
			c.hub.register <- c
			log.Printf("peer registered: %s", c.peerID)
			// Confirm registration
			resp, _ := json.Marshal(SignalMessage{Type: "registered", PeerID: c.peerID})
			c.send <- resp
			// Broadcast online presence to all other peers
			c.hub.broadcastPresence(c.peerID, "online")
			// Tell new peer about everyone already online
			for id := range c.hub.clients {
				if id != "" && id != c.peerID {
					presence, _ := json.Marshal(SignalMessage{
						Type:   "presence",
						PeerID: id,
						Status: "online",
					})
					c.send <- presence
				}
			}
		case "call", "accept", "reject", "ice_candidate", "data":
			// Forward to target peer
			msg.From = c.peerID
			c.hub.forward(msg)
		case "ping":
			// Respond with pong
			pong, _ := json.Marshal(SignalMessage{Type: "pong"})
			c.send <- pong
		}
	}
}

func (c *Client) writePump() {
	ticker := time.NewTicker(30 * time.Second)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case data, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := c.conn.WriteMessage(websocket.TextMessage, data); err != nil {
				return
			}
		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// ---- Hub ----

type Hub struct {
	clients    map[string]*Client // peerID → *Client
	register   chan *Client
	unregister chan *Client
	forwardCh  chan SignalMessage
	shutdown   chan struct{}
}

func NewHub() *Hub {
	return &Hub{
		clients:    make(map[string]*Client),
		register:   make(chan *Client),
		unregister: make(chan *Client),
		forwardCh:  make(chan SignalMessage, 128),
		shutdown:   make(chan struct{}),
	}
}

func (h *Hub) Run() {
	for {
		select {
		case client := <-h.register:
			h.clients[client.peerID] = client
		case client := <-h.unregister:
			if client.peerID != "" {
				if _, ok := h.clients[client.peerID]; ok {
					delete(h.clients, client.peerID)
					log.Printf("peer unregistered: %s", client.peerID)
					// Broadcast offline
					h.broadcastPresence(client.peerID, "offline")
				}
			}
			close(client.send)
		case msg := <-h.forwardCh:
			target, ok := h.clients[msg.To]
			if !ok {
				log.Printf("forward: target %s not found", msg.To)
				continue
			}
			msgBytes, err := json.Marshal(msg)
			if err != nil {
				log.Printf("marshal error: %v", err)
				continue
			}
			select {
			case target.send <- msgBytes:
			default:
				log.Printf("send buffer full for %s, dropping", msg.To)
			}
		case <-h.shutdown:
			return
		}
	}
}

func (h *Hub) forward(msg SignalMessage) {
	h.forwardCh <- msg
}

func (h *Hub) broadcastPresence(peerID string, status string) {
	msg, _ := json.Marshal(SignalMessage{
		Type:   "presence",
		PeerID: peerID,
		Status: status,
	})
	for id, client := range h.clients {
		if id != "" && id != peerID {
			select {
			case client.send <- msg:
			default:
			}
		}
	}
}
