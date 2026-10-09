package tests

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/aiservice"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/fcm"
	supabaseadapter "github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	supabaseclient "github.com/nedpals/supabase-go"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type contractUpstreamRequest struct {
	method, path string
	query        url.Values
	body         map[string]any
}

type completedPushSender struct {
	sender domain.PushNotificationSender
	done   chan error
}

func (s completedPushSender) SendChatPush(ctx context.Context, push domain.ChatPushNotification) error {
	err := s.sender.SendChatPush(ctx, push)
	s.done <- err
	return err
}

// ใช้ adapter จริงทุกตัวกับ HTTP server บน loopback โดยไม่แตะฐานข้อมูลหรือส่งแจ้งเตือนจริง
func newAPIContractUpstream(t *testing.T, tc apiContractCase, requests chan contractUpstreamRequest) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		if (strings.Contains(r.Header.Get("Content-Type"), "application/json") || r.Header.Get("Content-Type") == "") && r.Body != nil {
			data, err := io.ReadAll(r.Body)
			assert.NoError(t, err)
			if len(data) > 0 {
				assert.NoError(t, json.Unmarshal(data, &body))
			}
		}
		requests <- contractUpstreamRequest{r.Method, r.URL.Path, r.URL.Query(), body}
		w.Header().Set("Content-Type", "application/json")
		var response any
		profile := map[string]any{"user_id": "verified-user", "email": "fixture@example.test", "display_name": "Verified name", "phone": "+66812345678", "user_image_url": "https://example.test/avatar.png", "fcm_token": "test-device"}
		item := map[string]any{"id": 7, "user_id": "verified-user", "item_name": "Camera", "description": "Digital camera", "category": "Camera", "price": 100, "type": "daily", "status": "available", "rating": 4.5, "review_count": 2, "paid_booking_count": 3}
		rental := map[string]any{"id": 9, "user_id": "verified-user", "item_id": 7, "status": "pending", "total_price": 200}
		if tc.path == "/api/rentals/9/return" {
			rental["status"] = "active"
		}
		switch r.URL.Path {
		case "/auth/v1/user":
			assert.Equal(t, "Bearer "+contractBearer, r.Header.Get("Authorization"))
			response = map[string]any{"id": "verified-user", "email": "fixture@example.test", "user_metadata": map[string]any{"avatar_url": "https://example.test/google.png"}}
		case "/auth/v1/token", "/auth/v1/verify":
			response = map[string]any{"access_token": "test-access", "refresh_token": "test-refresh"}
		case "/auth/v1/otp":
			response = map[string]any{}
		case "/auth/v1/admin/users":
			assert.Equal(t, "POST", r.Method)
			assert.Equal(t, "+66812345678", body["phone"])
			response = map[string]any{"id": "registered-user"}
		case "/auth/v1/admin/users/verified-user", "/auth/v1/admin/users/owner":
			assert.Equal(t, "Bearer test-service-key", r.Header.Get("Authorization"))
			response = map[string]any{"id": "verified-user", "email": "fixture@example.test", "phone": "+66812345678", "user_metadata": map[string]any{"phone": "+66812345678", "display_name": "Verified name"}}
		case "/rest/v1/rpc/check_email_exists":
			response = tc.op != "register"
		case "/rest/v1/rpc/create_rental_request":
			response = rental
		case "/rest/v1/profile_tb":
			response = []any{profile}
		case "/rest/v1/home_feed_ranked_v":
			response = []any{item}
		case "/rest/v1/item_tb":
			if r.Method == http.MethodPost || r.Method == http.MethodPatch {
				for key, value := range body {
					item[key] = value
				}
			}
			response = []any{item}
		case "/rest/v1/booking_tb":
			if r.Method == http.MethodPatch {
				rental["status"] = body["status"]
			}
			response = []any{rental}
		case "/rest/v1/conversation_tb":
			response = []any{map[string]any{"renter_id": "verified-user", "owner_id": "owner"}}
		case "/oauth2/token":
			response = map[string]any{"access_token": "test-google-access", "expires_in": 3600}
		case "/v1/projects/test/messages:send":
			assert.Equal(t, "Bearer test-google-access", r.Header.Get("Authorization"))
			response = map[string]any{"name": "projects/test/messages/1"}
		case "/api/chat":
			assert.Equal(t, "test-internal-key", r.Header.Get("X-Internal-Service-Key"))
			response = map[string]any{"response": "hello", "items": []any{}, "questions": []any{}, "suggested_replies": []any{}}
		case "/api/chat/stream":
			assert.Equal(t, "test-internal-key", r.Header.Get("X-Internal-Service-Key"))
			w.Header().Set("Content-Type", "text/event-stream")
			_, _ = io.WriteString(w, contractSSE)
			return
		default:
			if strings.HasPrefix(r.URL.Path, "/storage/v1/object/") {
				assert.Equal(t, "test-service-key", r.Header.Get("apikey"))
				assert.Equal(t, "Bearer test-service-key", r.Header.Get("Authorization"))
				assert.Equal(t, "image/png", r.Header.Get("Content-Type"))
				data, err := io.ReadAll(r.Body)
				assert.NoError(t, err)
				assert.True(t, strings.HasPrefix(string(data), "\x89PNG\r\n\x1a\n"))
				response = map[string]any{"Key": strings.TrimPrefix(r.URL.Path, "/storage/v1/object/")}
			} else {
				t.Errorf("unexpected upstream request: %s %s", r.Method, r.URL.Path)
				http.NotFound(w, r)
				return
			}
		}
		assert.NoError(t, json.NewEncoder(w).Encode(response))
	}))
}

func TestMultipartAPIsWithRealStorageAdapter(t *testing.T) {
	for _, c := range []struct {
		method, path, field string
		fields              map[string]string
	}{
		{"POST", "/api/auth/register", "image", map[string]string{"display_name": "Fixture", "email": "fixture@example.test", "phone": "0812345678", "password": "abcdef"}},
		{"PUT", "/api/user/profile", "image", map[string]string{"bio": ""}},
		{"POST", "/api/items", "images", map[string]string{"item_name": "Camera", "description": "Camera", "category": "Camera", "price": "100", "type": "daily"}},
	} {
		t.Run(c.path, func(t *testing.T) {
			tc := contractCaseFor(t, c.method, c.path)
			requests := make(chan contractUpstreamRequest, 32)
			upstream := newAPIContractUpstream(t, tc, requests)
			defer upstream.Close()
			client := supabaseclient.CreateClient(upstream.URL, "test-service-key")
			auth := supabaseadapter.NewSupabaseUserRepository(client, "test-service-key")
			app := ports.SetupRouter(supabaseadapter.NewSupabaseItemRepository(client, "test-service-key"), auth, nil, nil, nil, nil, contractAppKey)
			request := multipartRequest(t, c.method, c.path, c.fields, c.field, 1, 16)
			request.Header.Set("Authorization", "Bearer "+contractBearer)
			request.Header.Set("X-App-Secret", contractAppKey)
			recorder := httptest.NewRecorder()
			performFiberRequest(t, app, recorder, request)
			require.Equal(t, tc.status, recorder.Code, recorder.Body.String())
			uploads := 0
			for len(requests) > 0 {
				r := <-requests
				if strings.HasPrefix(r.path, "/storage/v1/object/") {
					uploads++
					require.Equal(t, "POST", r.method)
				}
			}
			require.Equal(t, 1, uploads)
			if tc.op == "register" {
				var response map[string]any
				require.NoError(t, json.Unmarshal(recorder.Body.Bytes(), &response))
				require.Contains(t, response["user_image_url"], upstream.URL+"/storage/v1/object/public/profile_bk/")
			}
		})
	}
}

func TestAllAPIEndpointsWithRealAdapters(t *testing.T) {
	privateKey := generateTestRSAPrivateKeyPEM(t)
	for _, tc := range apiContractCases() {
		t.Run(tc.method+" "+tc.pattern, func(t *testing.T) {
			requests := make(chan contractUpstreamRequest, 32)
			upstream := newAPIContractUpstream(t, tc, requests)
			defer upstream.Close()
			client := supabaseclient.CreateClient(upstream.URL, "test-service-key")
			auth := supabaseadapter.NewSupabaseUserRepository(client, "test-service-key")
			sender, err := fcm.NewFCMSender(auth, "", firebaseTestCredentials(t, "test", upstream.URL+"/oauth2/token", privateKey), firebaseTestHTTPClient(upstream))
			require.NoError(t, err)
			pushSender := completedPushSender{sender: sender, done: make(chan error, 1)}
			app := ports.SetupRouter(supabaseadapter.NewSupabaseItemRepository(client, "test-service-key"), auth,
				supabaseadapter.NewSupabaseConversationContactRepository(client), supabaseadapter.NewSupabaseRentalRepository(client),
				pushSender, aiservice.NewClient(upstream.URL, "test-internal-key", 2*time.Second), contractAppKey)
			recorder := contractRequest(t, app, tc, "Bearer "+contractBearer, contractAppKey)
			require.Equal(t, tc.status, recorder.Code, recorder.Body.String())
			if tc.path == "/api/push/chat" {
				select {
				case err := <-pushSender.done:
					require.NoError(t, err)
				case <-time.After(3 * time.Second):
					t.Fatal("FCM adapter did not complete")
				}
			}
			if tc.op == "stream" {
				require.Equal(t, contractSSE, recorder.Body.String())
			} else if tc.op == "register" {
				assertContractFields(t, recorder, map[string]any{"user_id": "registered-user"})
			} else if tc.status != 204 {
				assertContractFields(t, recorder, tc.fields)
			}
			var seen []contractUpstreamRequest
			for len(requests) > 0 {
				seen = append(seen, <-requests)
			}
			if tc.path == "/health" {
				require.Empty(t, seen)
				return
			}
			require.NotEmpty(t, seen, "request did not reach real adapter")
			for _, request := range seen {
				switch request.path {
				case "/rest/v1/rpc/create_rental_request":
					require.Equal(t, "verified-user", request.body["p_user_id"])
					require.Equal(t, float64(7), request.body["p_item_id"])
					require.NotContains(t, request.body, "total_price")
				case "/rest/v1/item_tb":
					if request.method == "PATCH" || request.method == "DELETE" {
						require.Equal(t, "eq.7", request.query.Get("id"))
						require.Equal(t, "eq.verified-user", request.query.Get("user_id"))
					}
					if request.method == "POST" {
						require.Equal(t, "verified-user", request.body["user_id"])
					}
				case "/rest/v1/profile_tb":
					if request.method == "PATCH" {
						require.Equal(t, "eq.verified-user", request.query.Get("user_id"))
					}
				case "/v1/projects/test/messages:send":
					message := request.body["message"].(map[string]any)
					require.Equal(t, "test-device", message["token"])
					require.Equal(t, "Verified name", message["notification"].(map[string]any)["title"])
				case "/api/chat", "/api/chat/stream":
					require.Equal(t, "Hello", request.body["message"])
				}
			}
		})
	}
}

func TestPasswordAPIMapsRealSupabaseAuthenticationFailures(t *testing.T) {
	for _, status := range []int{401, 403, 500} {
		t.Run(fmt.Sprint(status), func(t *testing.T) {
			upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				assert.Equal(t, "PUT", r.Method)
				assert.Equal(t, "/auth/v1/user", r.URL.Path)
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(status)
				_, _ = io.WriteString(w, `{"error_code":"bad_jwt","msg":"`+contractPrivateDetail+`"}`)
			}))
			defer upstream.Close()
			client := supabaseclient.CreateClient(upstream.URL, "test-service-key")
			app := ports.SetupRouter(nil, supabaseadapter.NewSupabaseUserRepository(client, "test-service-key"), nil, nil, nil, nil, contractAppKey)
			recorder := contractRequest(t, app, contractCaseFor(t, "POST", "/api/auth/change-password"), "Bearer "+contractBearer, contractAppKey)
			expected := 401
			if status == 500 {
				expected = 500
			}
			require.Equal(t, expected, recorder.Code)
			require.NotContains(t, recorder.Body.String(), contractPrivateDetail)
		})
	}
}
