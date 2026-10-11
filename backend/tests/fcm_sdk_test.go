package tests

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/fcm"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestFirebaseSDKPreservesNotificationAndCachesOAuth(t *testing.T) {
	var oauthCalls atomic.Int32
	requests := make(chan []byte, 2)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path == "/oauth2/token" {
			oauthCalls.Add(1)
			assert.NoError(t, r.ParseForm())
			assert.Equal(t, "urn:ietf:params:oauth:grant-type:jwt-bearer", r.Form.Get("grant_type"))
			assert.NotEmpty(t, r.Form.Get("assertion"))
			_, _ = io.WriteString(w, `{"access_token":"fixture-access","token_type":"Bearer","expires_in":3600}`)
			return
		}
		assert.Equal(t, "/v1/projects/test/messages:send", r.URL.Path)
		assert.Equal(t, "Bearer fixture-access", r.Header.Get("Authorization"))
		assert.Contains(t, r.Header.Get("X-Firebase-Client"), "fire-admin-go/")
		body, err := io.ReadAll(r.Body)
		assert.NoError(t, err)
		requests <- body
		_, _ = io.WriteString(w, `{"name":"projects/test/messages/1"}`)
	}))
	defer server.Close()
	tokens := newMockTokenManager()
	tokens.tokens["receiver"] = "fixture-device"
	credentials := firebaseTestCredentials(t, "test", server.URL+"/oauth2/token", generateTestRSAPrivateKeyPEM(t))
	// ตรวจการโหลดจากไฟล์ด้วย JSON ที่สร้างเฉพาะในการทดสอบ
	path := filepath.Join(t.TempDir(), "service-account.json")
	require.NoError(t, os.WriteFile(path, []byte(credentials), 0600))
	sender, err := fcm.NewFCMSender(tokens, path, "", firebaseTestHTTPClient(server))
	require.NoError(t, err)
	for _, tc := range []struct{ name, message, title, body string }{
		{" Alice ", "↩ ตอบกลับ: เก่า\nใหม่", "Alice", "ใหม่"},
		{" ", " ", "ข้อความใหม่", "ส่งข้อความถึงคุณ"},
	} {
		err := sender.SendChatPush(context.Background(), domain.ChatPushNotification{
			ReceiverID: "receiver", ConversationID: "conversation", MessageID: "message",
			SenderName: tc.name, SenderAvatar: "avatar", Message: tc.message,
		})
		require.NoError(t, err)
		var payload map[string]any
		require.NoError(t, json.Unmarshal(<-requests, &payload))
		message := payload["message"].(map[string]any)
		require.Equal(t, "fixture-device", message["token"])
		require.Equal(t, map[string]any{"title": tc.title, "body": tc.body}, message["notification"])
		require.Equal(t, map[string]any{
			"type": "chat_message", "conversation_id": "conversation", "message_id": "message",
			"sender_name": tc.title, "sender_avatar": "avatar", "message": tc.body, "title": tc.title, "body": tc.body,
		}, message["data"])
		require.Equal(t, map[string]any{
			"priority": "high", "notification": map[string]any{
				"channel_id": "yuemnoi_chat_messages_v3", "title": tc.title, "body": tc.body,
				"sound": "message_tone", "click_action": "FLUTTER_NOTIFICATION_CLICK",
			},
		}, message["android"])
		require.Equal(t, map[string]any{
			"headers": map[string]any{"apns-priority": "10"},
			"payload": map[string]any{"aps": map[string]any{
				"alert": map[string]any{"title": tc.title, "body": tc.body}, "badge": float64(1),
				"sound": "message_tone.wav", "content-available": float64(1),
			}},
		}, message["apns"])
	}
	require.EqualValues(t, 1, oauthCalls.Load())
}

func TestFirebaseSDKDeletesOnlyUnregisteredTokens(t *testing.T) {
	key := generateTestRSAPrivateKeyPEM(t)
	for _, tc := range []struct {
		name    string
		status  int
		body    string
		deleted bool
	}{
		{"unregistered", 404, `{"error":{"code":404,"status":"NOT_FOUND","message":"gone","details":[{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError","errorCode":"UNREGISTERED"}]}}`, true},
		{"ordinary not found", 404, `{"error":{"code":404,"status":"NOT_FOUND","message":"project missing"}}`, false},
		{"unregistered text alone", 404, `{"error":{"code":404,"status":"NOT_FOUND","message":"UNREGISTERED"}}`, false},
		{"invalid payload", 400, `{"error":{"code":400,"status":"INVALID_ARGUMENT","message":"invalid notification"}}`, false},
		{"permission denied", 403, `{"error":{"code":403,"status":"PERMISSION_DENIED","message":"wrong project"}}`, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				if r.URL.Path == "/oauth2/token" {
					_, _ = io.WriteString(w, `{"access_token":"fixture-access","expires_in":3600}`)
					return
				}
				w.WriteHeader(tc.status)
				_, _ = io.WriteString(w, tc.body)
			}))
			defer server.Close()
			tokens := newMockTokenManager()
			tokens.tokens["receiver"] = "fixture-device"
			sender, err := fcm.NewFCMSender(tokens, "", firebaseTestCredentials(t, "test", server.URL+"/oauth2/token", key), firebaseTestHTTPClient(server))
			require.NoError(t, err)
			require.Error(t, sender.SendChatPush(context.Background(), domain.ChatPushNotification{ReceiverID: "receiver", Message: "hello"}))
			tokens.mu.Lock()
			defer tokens.mu.Unlock()
			require.Equal(t, tc.deleted, len(tokens.deletedUsers) == 1)
			if !tc.deleted {
				require.Equal(t, "fixture-device", tokens.tokens["receiver"])
			}
		})
	}
}

func TestFirebaseSDKCancellationDuringOAuthAndDelivery(t *testing.T) {
	key := generateTestRSAPrivateKeyPEM(t)
	for _, stage := range []string{"oauth", "delivery"} {
		t.Run(stage, func(t *testing.T) {
			started, release := make(chan struct{}), make(chan struct{})
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				_, _ = io.Copy(io.Discard, r.Body)
				if r.URL.Path == "/oauth2/token" && stage != "oauth" {
					w.Header().Set("Content-Type", "application/json")
					_, _ = io.WriteString(w, `{"access_token":"fixture-access","expires_in":3600}`)
					return
				}
				close(started)
				select {
				case <-r.Context().Done():
				case <-release:
				}
			}))
			defer server.Close()
			defer close(release)
			tokens := newMockTokenManager()
			tokens.tokens["receiver"] = "fixture-device"
			sender, err := fcm.NewFCMSender(tokens, "", firebaseTestCredentials(t, "test", server.URL+"/oauth2/token", key), firebaseTestHTTPClient(server))
			require.NoError(t, err)
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			done := make(chan error, 1)
			go func() {
				done <- sender.SendChatPush(ctx, domain.ChatPushNotification{ReceiverID: "receiver", Message: "hello"})
			}()
			select {
			case <-started:
			case <-time.After(2 * time.Second):
				t.Fatal("SDK request did not reach upstream")
			}
			cancel()
			select {
			case err := <-done:
				require.Error(t, err)
			case <-time.After(time.Second):
				t.Fatal("SDK ignored caller cancellation")
			}
			require.Empty(t, tokens.deletedUsers)
		})
	}
}

func TestFirebaseSDKInvalidConfigurationRemainsCallable(t *testing.T) {
	for _, value := range []string{"invalid JSON", `{}`, `{"type":"authorized_user","project_id":"test"}`, `{"type":"service_account","project_id":"test","private_key":"invalid"}`} {
		sender, err := fcm.NewFCMSender(nil, "", value, nil)
		require.Error(t, err)
		require.NotNil(t, sender)
		require.ErrorContains(t, sender.SendChatPush(context.Background(), domain.ChatPushNotification{}), "not configured")
	}
}
