package supabase_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	"github.com/gorilla/websocket"
)

func TestNotificationRealtimeWakesOnJoinBroadcastAndReconnect(t *testing.T) {
	const topic = "realtime:notification-outbox"
	const serviceKey = "header.payload.signature"
	var joins atomic.Int32
	release := make(chan struct{})
	writeBroadcast := make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/realtime/v1/websocket" || r.URL.Query().Get("apikey") != serviceKey || r.URL.Query().Get("vsn") != "1.0.0" {
			t.Error("unexpected Realtime URL")
			return
		}
		upgrader := websocket.Upgrader{}
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			t.Error(err)
			return
		}
		defer conn.Close()
		var join struct {
			Topic   string `json:"topic"`
			Event   string `json:"event"`
			Ref     string `json:"ref"`
			Payload struct {
				AccessToken string `json:"access_token"`
				Config      struct {
					Private bool `json:"private"`
				} `json:"config"`
			} `json:"payload"`
		}
		if err := conn.ReadJSON(&join); err != nil {
			t.Error(err)
			return
		}
		if join.Topic != topic || join.Event != "phx_join" || join.Payload.AccessToken != serviceKey || !join.Payload.Config.Private {
			t.Error("expected an authenticated private join")
			return
		}
		write := func(event, ref, payload string) {
			if err := conn.WriteJSON(map[string]any{"topic": topic, "event": event, "ref": ref, "payload": json.RawMessage(payload)}); err != nil {
				t.Error(err)
			}
		}
		connectionNumber := joins.Add(1)
		write("phx_reply", join.Ref, `{"status":"ok","response":{}}`)
		if connectionNumber == 1 {
			select {
			case <-writeBroadcast:
				write("broadcast", "", `{"event":"ignored"}`)
				write("broadcast", "", `{"event":"outbox_ready","payload":{}}`)
				// ให้ client ประมวลผลเฟรมทั้งสองก่อนทดสอบรอบ reconnect
				<-release
			case <-release:
			}
			return
		}
		_, _, _ = conn.ReadMessage()
	}))
	defer server.Close()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	listener, err := supabase.NewNotificationRealtimeListener(server.URL, serviceKey)
	if err != nil {
		t.Fatal(err)
	}
	wakeups := make(chan struct{}, 4)
	done := make(chan struct{})
	go func() {
		defer close(done)
		listener.Run(ctx, wakeups)
	}()
	waitForWake := func() {
		t.Helper()
		select {
		case <-wakeups:
		case <-time.After(3 * time.Second):
			t.Fatal("Realtime did not wake the worker")
		}
	}
	defer func() {
		select {
		case <-release:
		default:
			close(release)
		}
	}()
	waitForWake()
	close(writeBroadcast)
	waitForWake()
	select {
	case <-wakeups:
		t.Fatal("an unrelated broadcast woke the worker")
	case <-time.After(50 * time.Millisecond):
	}
	close(release)
	waitForWake()
	if joins.Load() != 2 {
		t.Fatalf("joined %d times, want 2", joins.Load())
	}
	cancel()
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("Realtime socket did not shut down on cancellation")
	}
}
