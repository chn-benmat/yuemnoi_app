package supabase

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/gorilla/websocket"
)

const notificationRealtimeTopic = "realtime:notification-outbox"

// NotificationRealtimeListener รับสัญญาณจากฐานข้อมูลเพื่อปลุกตัวส่งแจ้งเตือน
type NotificationRealtimeListener struct {
	endpoint   url.URL
	serviceKey string
}

func NewNotificationRealtimeListener(supabaseURL, serviceKey string) (*NotificationRealtimeListener, error) {
	endpoint, err := url.Parse(strings.TrimSpace(supabaseURL))
	serviceKey = strings.TrimSpace(serviceKey)
	if err != nil || endpoint.Host == "" || endpoint.User != nil || serviceKey == "" {
		return nil, errors.New("invalid Supabase Realtime configuration")
	}
	switch endpoint.Scheme {
	case "https":
		endpoint.Scheme = "wss"
	case "http":
		endpoint.Scheme = "ws"
	default:
		return nil, errors.New("invalid Supabase Realtime URL scheme")
	}
	endpoint.Path = strings.TrimRight(endpoint.Path, "/") + "/realtime/v1/websocket"
	endpoint.RawPath, endpoint.RawQuery, endpoint.Fragment = "", "", ""
	return &NotificationRealtimeListener{endpoint: *endpoint, serviceKey: serviceKey}, nil
}

func (l *NotificationRealtimeListener) Run(ctx context.Context, wakeups chan<- struct{}) {
	backoff := time.Second
	for ctx.Err() == nil {
		started := time.Now()
		err := l.listen(ctx, wakeups)
		if ctx.Err() != nil {
			return
		}
		if time.Since(started) >= 30*time.Second {
			backoff = time.Second
		}
		slog.Warn("WebSocket แจ้งเตือนขาดการเชื่อมต่อ", slog.String("reason", err.Error()), slog.Duration("retry_in", backoff))
		select {
		case <-ctx.Done():
			return
		case <-time.After(backoff):
			backoff = min(backoff*2, 30*time.Second)
		}
	}
}

type notificationRealtimeFrame struct {
	Topic   string          `json:"topic"`
	Event   string          `json:"event"`
	Ref     string          `json:"ref"`
	JoinRef string          `json:"join_ref,omitempty"`
	Payload json.RawMessage `json:"payload"`
}

func (l *NotificationRealtimeListener) listen(ctx context.Context, wakeups chan<- struct{}) error {
	endpoint := l.endpoint
	endpoint.RawQuery = url.Values{"apikey": {l.serviceKey}, "vsn": {"1.0.0"}}.Encode()
	dialer := *websocket.DefaultDialer
	dialer.HandshakeTimeout = 8 * time.Second
	conn, response, err := dialer.DialContext(ctx, endpoint.String(), nil)
	if err != nil {
		if response != nil {
			_ = response.Body.Close()
		}
		// ข้อผิดพลาดจาก dial อาจรวม URL ที่มี service key
		return errors.New("handshake failed")
	}
	defer conn.Close()
	stopClose := context.AfterFunc(ctx, func() { _ = conn.Close() })
	defer stopClose()
	conn.SetReadLimit(64 << 10)
	if err := l.join(conn); err != nil {
		return err
	}
	slog.Info("เชื่อมต่อ WebSocket สำหรับแจ้งเตือนแล้ว")
	signalNotificationOutbox(wakeups)

	connectionCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	go keepNotificationRealtimeAlive(connectionCtx, conn)
	for {
		_ = conn.SetReadDeadline(time.Now().Add(45 * time.Second))
		var frame notificationRealtimeFrame
		if err := conn.ReadJSON(&frame); err != nil {
			return errors.New("socket read failed")
		}
		if frame.Topic != notificationRealtimeTopic {
			continue
		}
		switch frame.Event {
		case "phx_close", "phx_error":
			return errors.New("channel closed")
		case "broadcast":
			var payload struct {
				Event string `json:"event"`
			}
			if json.Unmarshal(frame.Payload, &payload) == nil && payload.Event == "outbox_ready" {
				signalNotificationOutbox(wakeups)
			}
		}
	}
}

func (l *NotificationRealtimeListener) join(conn *websocket.Conn) error {
	payload := map[string]any{
		"config": map[string]any{
			"private":   true,
			"broadcast": map[string]bool{"ack": false, "self": false},
			"presence":  map[string]bool{"enabled": false},
		},
	}
	if strings.Count(l.serviceKey, ".") == 2 {
		payload["access_token"] = l.serviceKey
	}
	encoded, _ := json.Marshal(payload)
	_ = conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
	if err := conn.WriteJSON(notificationRealtimeFrame{
		Topic: notificationRealtimeTopic, Event: "phx_join", Ref: "1", JoinRef: "1", Payload: encoded,
	}); err != nil {
		return errors.New("channel join write failed")
	}
	_ = conn.SetReadDeadline(time.Now().Add(8 * time.Second))
	for {
		var frame notificationRealtimeFrame
		if err := conn.ReadJSON(&frame); err != nil {
			return errors.New("channel join reply missing")
		}
		if frame.Topic != notificationRealtimeTopic {
			continue
		}
		if frame.Event == "phx_close" || frame.Event == "phx_error" {
			return errors.New("channel closed during join")
		}
		if frame.Event != "phx_reply" || frame.Ref != "1" {
			continue
		}
		var reply struct {
			Status string `json:"status"`
		}
		if json.Unmarshal(frame.Payload, &reply) != nil || reply.Status != "ok" {
			return errors.New("private channel join rejected")
		}
		return nil
	}
}

func keepNotificationRealtimeAlive(ctx context.Context, conn *websocket.Conn) {
	ticker := time.NewTicker(20 * time.Second)
	defer ticker.Stop()
	for ref := 2; ; ref++ {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			_ = conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
			if err := conn.WriteJSON(notificationRealtimeFrame{
				Topic: "phoenix", Event: "heartbeat", Ref: strconv.Itoa(ref), Payload: json.RawMessage(`{}`),
			}); err != nil {
				_ = conn.Close()
				return
			}
		}
	}
}

func signalNotificationOutbox(wakeups chan<- struct{}) {
	// ตัวส่งถือสัญญาณได้หนึ่งรายการเพื่อรวมเหตุการณ์ที่เข้าพร้อมกัน
	select {
	case wakeups <- struct{}{}:
	default:
	}
}
