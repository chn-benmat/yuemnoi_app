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
	"net/url"
	"sync"
	"testing"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/fcm"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

// เปลี่ยนเฉพาะปลายทาง FCM เป็น loopback โดยยังผ่าน SDK และ OAuth จริงทั้งหมด
type firebaseTestTransport struct {
	base   http.RoundTripper
	target *url.URL
}

func (t firebaseTestTransport) RoundTrip(request *http.Request) (*http.Response, error) {
	if request.URL.Host == "fcm.googleapis.com" {
		request = request.Clone(request.Context())
		request.URL.Scheme = t.target.Scheme
		request.URL.Host = t.target.Host
	}
	return t.base.RoundTrip(request)
}

func firebaseTestHTTPClient(server *httptest.Server) *http.Client {
	client := *server.Client()
	base := client.Transport
	if base == nil {
		base = http.DefaultTransport
	}
	target, _ := url.Parse(server.URL)
	client.Transport = firebaseTestTransport{base: base, target: target}
	return &client
}

func firebaseTestCredentials(t *testing.T, project, tokenURL, privateKey string) string {
	t.Helper()
	data, err := json.Marshal(map[string]string{
		"type": "service_account", "project_id": project,
		"client_email": "fixture@" + project + ".iam.gserviceaccount.com",
		"private_key":  privateKey, "token_uri": tokenURL,
	})
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

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

	// จำลอง Google OAuth และ FCM โดยไม่ส่งแจ้งเตือนจริง
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/oauth2/token":
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(map[string]any{
				"access_token": "mock-google-token",
				"expires_in":   3600,
			})
		case "/v1/projects/test-proj/messages:send":
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

	sender, err := fcm.NewFCMSender(tokenMgr, "", firebaseTestCredentials(t, "test-proj", server.URL+"/oauth2/token", pemKey), firebaseTestHTTPClient(server))
	if err != nil {
		t.Fatalf("NewFCMSender error: %v", err)
	}

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
		fcmResponseBody = `{"error":{"code":404,"status":"NOT_FOUND","message":"UNREGISTERED","details":[{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError","errorCode":"UNREGISTERED"}]}}`

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
