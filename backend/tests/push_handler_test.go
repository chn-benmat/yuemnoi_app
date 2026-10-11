package tests

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
)

type mockPushSender struct {
	mu           sync.Mutex
	lastReceived domain.ChatPushNotification
	callCount    int
	err          error
}

func (m *mockPushSender) SendChatPush(_ context.Context, n domain.ChatPushNotification) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.lastReceived = n
	m.callCount++
	return m.err
}

func (m *mockPushSender) getNotification() domain.ChatPushNotification {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.lastReceived
}

func (m *mockPushSender) getCount() int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.callCount
}

// mockPushAuthGateway จำลอง AuthGateway สำหรับทดสอบการตรวจสอบสิทธิ์และดึงโปรไฟล์ผู้ส่ง
type mockPushAuthGateway struct {
	domain.AuthGateway
	userID  string
	profile *domain.UserProfile
	err     error
}

func (m *mockPushAuthGateway) UserIDFromToken(_ context.Context, _ string) (string, error) {
	if m.err != nil {
		return "", m.err
	}
	return m.userID, nil
}

func (m *mockPushAuthGateway) GetProfile(_ context.Context, _ string) (*domain.UserProfile, error) {
	return m.profile, nil
}

func TestPushHandlerSendChatPush(t *testing.T) {

	mockSender := &mockPushSender{}
	mockAuth := &mockPushAuthGateway{
		userID: "sender-user-id",
		profile: &domain.UserProfile{
			UserID:       "sender-user-id",
			DisplayName:  "Alice",
			UserImageURL: "https://example.test/avatar.png",
		},
	}
	handler := ports.NewPushHandler(mockSender, mockAuth)

	router := ports.NewHTTPApp()
	router.Post("/api/push/chat", handler.SendChatPush)

	t.Run("returns 200 queued and dispatches to sender", func(t *testing.T) {
		payload := map[string]string{
			"receiver_id":     "user-123",
			"conversation_id": "conv-456",
			"message_id":      "msg-789",
			"sender_name":     "Alice",
			"sender_avatar":   "https://example.test/avatar.png",
			"message":         "สวัสดีครับ ขอยืมอุปกรณ์หน่อยครับ",
		}
		body, _ := json.Marshal(payload)

		req := httptest.NewRequest(http.MethodPost, "/api/push/chat", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer valid-token")
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()

		performFiberRequest(t, router, w, req)

		if w.Code != http.StatusOK {
			t.Fatalf("expected status 200, got %d: %s", w.Code, w.Body.String())
		}

		var res map[string]string
		if err := json.Unmarshal(w.Body.Bytes(), &res); err != nil {
			t.Fatal(err)
		}
		if res["status"] != "queued" {
			t.Fatalf("expected status 'queued', got %q", res["status"])
		}

		// รอ Background Goroutine เล็กน้อย
		time.Sleep(50 * time.Millisecond)

		if mockSender.getCount() == 0 {
			t.Fatal("expected push sender to be called in background")
		}
		notification := mockSender.getNotification()
		if notification.ReceiverID != "user-123" || notification.ConversationID != "conv-456" {
			t.Fatalf("unexpected notification data: %#v", notification)
		}
		if notification.SenderName != "Alice" || notification.Message != "สวัสดีครับ ขอยืมอุปกรณ์หน่อยครับ" {
			t.Fatalf("unexpected notification payload: %#v", notification)
		}
	})

	t.Run("returns 400 when missing required receiver_id", func(t *testing.T) {
		payload := map[string]string{
			"conversation_id": "conv-456",
			"message":         "สวัสดี",
		}
		body, _ := json.Marshal(payload)

		req := httptest.NewRequest(http.MethodPost, "/api/push/chat", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer valid-token")
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()

		performFiberRequest(t, router, w, req)

		if w.Code != http.StatusBadRequest {
			t.Fatalf("expected status 400, got %d: %s", w.Code, w.Body.String())
		}
	})

	t.Run("returns 401 when authorization header is missing", func(t *testing.T) {
		payload := map[string]string{
			"receiver_id":     "user-123",
			"conversation_id": "conv-456",
			"message":         "สวัสดี",
		}
		body, _ := json.Marshal(payload)

		req := httptest.NewRequest(http.MethodPost, "/api/push/chat", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()

		performFiberRequest(t, router, w, req)

		if w.Code != http.StatusUnauthorized {
			t.Fatalf("expected status 401, got %d: %s", w.Code, w.Body.String())
		}
	})

	t.Run("returns 400 when sender attempts to push to self", func(t *testing.T) {
		payload := map[string]string{
			"receiver_id":     "sender-user-id",
			"conversation_id": "conv-456",
			"message":         "สวัสดี",
		}
		body, _ := json.Marshal(payload)

		req := httptest.NewRequest(http.MethodPost, "/api/push/chat", bytes.NewReader(body))
		req.Header.Set("Authorization", "Bearer valid-token")
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()

		performFiberRequest(t, router, w, req)

		if w.Code != http.StatusBadRequest {
			t.Fatalf("expected status 400, got %d: %s", w.Code, w.Body.String())
		}
	})
}
