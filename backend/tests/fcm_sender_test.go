package tests

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/fcm"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

type mockTokenManager struct {
	mu           sync.Mutex
	tokens       map[string]string
	deletedUsers []string
}

func newMockTokenManager() *mockTokenManager {
	return &mockTokenManager{
		tokens: make(map[string]string),
	}
}

func (m *mockTokenManager) GetFCMToken(_ context.Context, userID string) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.tokens[userID], nil
}

func (m *mockTokenManager) DeleteFCMToken(_ context.Context, userID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.tokens, userID)
	m.deletedUsers = append(m.deletedUsers, userID)
	return nil
}

func generateTestRSAPrivateKeyPEM(t *testing.T) string {
	privKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate rsa key: %v", err)
	}
	pkcs8Bytes, err := x509.MarshalPKCS8PrivateKey(privKey)
	if err != nil {
		t.Fatalf("marshal pkcs8: %v", err)
	}
	pemBytes := pem.EncodeToMemory(&pem.Block{
		Type:  "PRIVATE KEY",
		Bytes: pkcs8Bytes,
	})
	return string(pemBytes)
}

func TestExtractCleanChatMessage(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "plain message",
			input:    "สวัสดีครับ",
			expected: "สวัสดีครับ",
		},
		{
			name:     "message with reply prefix and newline",
			input:    "↩ ตอบกลับ: ข้อความเดิม\nข้อความใหม่จริง",
			expected: "ข้อความใหม่จริง",
		},
		{
			name:     "message with pipe separator",
			input:    "💬 ตอบกลับ | ข้อความจริง",
			expected: "ข้อความจริง",
		},
		{
			name:     "whitespace trim",
			input:    "   ยืมของหน่อย   ",
			expected: "ยืมของหน่อย",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := fcm.ExtractCleanChatMessage(tt.input)
			if got != tt.expected {
				t.Errorf("got %q, want %q", got, tt.expected)
			}
		})
	}
}

func TestFCMSenderSendChatPushSuccessAndInvalidation(t *testing.T) {
	pemKey := generateTestRSAPrivateKeyPEM(t)

	var fcmRequests []map[string]any
	var fcmStatusCode = http.StatusOK
	var fcmResponseBody = `{"name":"projects/test-proj/messages/msg-123"}`

	// Mock Google OAuth and FCM Server
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/oauth2/token":
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]any{
				"access_token": "mock-google-token",
				"expires_in":   3600,
			})
		case "/fcm/send":
			var payload map[string]any
			_ = json.NewDecoder(r.Body).Decode(&payload)
			fcmRequests = append(fcmRequests, payload)

			w.WriteHeader(fcmStatusCode)
			_, _ = w.Write([]byte(fcmResponseBody))
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	tokenMgr := newMockTokenManager()
	tokenMgr.tokens["user-target"] = "target-fcm-device-token"

	sender, err := fcm.NewFCMSender(tokenMgr, "", "", server.Client())
	if err != nil {
		t.Fatalf("NewFCMSender error: %v", err)
	}

	sender.SetServiceAccountForTesting(&fcm.ServiceAccountKey{
		ProjectID:   "test-proj",
		ClientEmail: "test-bot@test-proj.iam.gserviceaccount.com",
		PrivateKey:  pemKey,
	})
	sender.SetEndpointsForTesting(server.URL+"/oauth2/token", server.URL+"/fcm/send")

	t.Run("sends chat push successfully", func(t *testing.T) {
		err := sender.SendChatPush(context.Background(), domain.ChatPushNotification{
			ReceiverID:     "user-target",
			ConversationID: "conv-1",
			MessageID:      "m-1",
			SenderName:     "Bob",
			Message:        "สวัสดีครับ",
		})
		if err != nil {
			t.Fatalf("expected nil error, got: %v", err)
		}
		if len(fcmRequests) != 1 {
			t.Fatalf("expected 1 FCM request, got %d", len(fcmRequests))
		}
	})

	t.Run("invalidates token when FCM returns UNREGISTERED", func(t *testing.T) {
		fcmStatusCode = http.StatusNotFound
		fcmResponseBody = `{"error":{"message":"UNREGISTERED"}}`

		err := sender.SendChatPush(context.Background(), domain.ChatPushNotification{
			ReceiverID:     "user-target",
			ConversationID: "conv-1",
			MessageID:      "m-2",
			SenderName:     "Bob",
			Message:        "สวัสดีอีกรอบ",
		})
		if err == nil {
			t.Fatal("expected error on 404 UNREGISTERED, got nil")
		}

		// ตรวจสอบว่า DeleteFCMToken ถูกเรียกใน mockTokenManager
		tokenMgr.mu.Lock()
		deleted := tokenMgr.deletedUsers
		tokenMgr.mu.Unlock()

		if len(deleted) == 0 || deleted[0] != "user-target" {
			t.Fatalf("expected user-target to be deleted, got %v", deleted)
		}
	})
}
