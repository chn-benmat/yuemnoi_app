package tests

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type apiContractCase struct {
	method, pattern, path, body, op string
	status                          int
	protected                       bool
	fields                          map[string]any
}

type apiFailureCase struct {
	err    error
	status int
}

func apiContractCases() []apiContractCase {
	return []apiContractCase{
		{http.MethodGet, "/health", "/health", "", "", 200, false, map[string]any{"status": "ok"}},
		{http.MethodPost, "/api/auth/register", "/api/auth/register", `{"display_name":"Fixture","email":"fixture@example.test","phone":"0812345678","password":"abcdef","confirm_password":"abcdef"}`, "register", 201, false, map[string]any{"status": float64(201), "user_id": "registered-user", "user_image_url": "https://example.test/profile.png"}},
		{http.MethodPost, "/api/auth/login", "/api/auth/login", `{"email":"fixture@example.test","password":"abcdef"}`, "login", 200, false, map[string]any{"status": float64(200), "access_token": "test-access", "refresh_token": "test-refresh"}},
		{http.MethodPost, "/api/auth/google-profile", "/api/auth/google-profile", "", "google", 200, true, map[string]any{"user_image_url": "https://example.test/google.png"}},
		{http.MethodPost, "/api/auth/change-password", "/api/auth/change-password", `{"new_password":"abcdef"}`, "password", 200, true, map[string]any{"status": float64(200)}},
		{http.MethodPost, "/api/auth/send-otp", "/api/auth/send-otp", `{"email":"fixture@example.test"}`, "sendOTP", 200, false, map[string]any{"status": float64(200)}},
		{http.MethodPost, "/api/auth/verify-otp", "/api/auth/verify-otp", `{"email":"fixture@example.test","otp_code":"123456"}`, "verifyOTP", 200, false, map[string]any{"access_token": "test-access", "refresh_token": "test-refresh"}},
		{http.MethodGet, "/api/user/profile", "/api/user/profile", "", "profile", 200, true, map[string]any{"user_id": "verified-user", "display_name": "Verified name"}},
		{http.MethodPut, "/api/user/profile", "/api/user/profile", `{"display_name":"Updated","bio":""}`, "updateProfile", 200, true, map[string]any{"profile.user_id": "verified-user", "status": float64(200)}},
		{http.MethodPut, "/api/user/contact", "/api/user/contact", `{"phone":"0812345678"}`, "contact", 200, true, map[string]any{"phone": "+66812345678"}},
		{http.MethodPost, "/api/user/fcm-token", "/api/user/fcm-token", `{"fcm_token":"test-device"}`, "fcm", 200, true, map[string]any{"status": float64(200)}},
		{http.MethodGet, "/api/items", "/api/items", "", "items", 200, false, map[string]any{"0.id": float64(7), "0.rating": 4.5, "0.review_count": float64(2)}},
		{http.MethodPost, "/api/items", "/api/items", `{"item_name":"Camera","description":"Digital camera","category":"Camera","price":100,"type":"daily"}`, "insertItem", 201, true, map[string]any{"id": float64(7), "user_id": "verified-user", "status": "available"}},
		{http.MethodGet, "/api/items/:id", "/api/items/7", "", "item", 200, false, map[string]any{"id": float64(7), "item_name": "Camera"}},
		{http.MethodPut, "/api/items/:id", "/api/items/7", `{"price":150}`, "updateItem", 200, true, map[string]any{"id": float64(7)}},
		{http.MethodDelete, "/api/items/:id", "/api/items/7", "", "deleteItem", 204, true, nil},
		{http.MethodPost, "/api/rentals", "/api/rentals", `{"item_id":7,"start_at":"2026-10-10T01:00:00Z","end_at":"2026-10-12T01:00:00Z","rental_type":"daily","pickup_location":"Office"}`, "rental", 201, true, map[string]any{"id": float64(9), "user_id": "verified-user", "total_price": float64(200), "status": "pending"}},
		{http.MethodPost, "/api/rentals/:id/handover", "/api/rentals/9/handover", "", "rentalStatus", 200, true, map[string]any{"rental.id": float64(9), "rental.status": "active"}},
		{http.MethodPost, "/api/rentals/:id/return", "/api/rentals/9/return", "", "rentalStatus", 200, true, map[string]any{"rental.id": float64(9), "rental.status": "completed"}},
		{http.MethodPost, "/api/push/chat", "/api/push/chat", `{"receiver_id":"recipient","conversation_id":"conversation","message":"hello","sender_name":"Spoofed","sender_avatar":"spoofed"}`, "profile", 200, true, map[string]any{"status": "queued"}},
		{http.MethodPost, "/api/chat/contact", "/api/chat/contact", `{"conversation_id":"conversation"}`, "chatContact", 200, true, map[string]any{"phone": "+66812345678"}},
		{http.MethodPost, "/api/chat-ai", "/api/chat-ai", `{"query":"Hello","history":[]}`, "ai", 200, false, map[string]any{"status": "success", "answer": "hello"}},
		{http.MethodPost, "/api/chat-ai/stream", "/api/chat-ai/stream", `{"query":"Hello","history":[]}`, "stream", 200, false, nil},
	}
}

func contractRequest(t *testing.T, app *fiber.App, tc apiContractCase, authorization, appKey string) *httptest.ResponseRecorder {
	t.Helper()
	request := httptest.NewRequest(tc.method, tc.path, strings.NewReader(tc.body))
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Authorization", authorization)
	request.Header.Set("X-App-Secret", appKey)
	recorder := httptest.NewRecorder()
	performFiberRequest(t, app, recorder, request)
	return recorder
}

func assertContractFields(t *testing.T, recorder *httptest.ResponseRecorder, fields map[string]any) {
	t.Helper()
	require.Contains(t, recorder.Header().Get("Content-Type"), "application/json")
	var body any
	require.NoError(t, json.Unmarshal(recorder.Body.Bytes(), &body))
	for path, expected := range fields {
		value := body
		for _, part := range strings.Split(path, ".") {
			switch node := value.(type) {
			case map[string]any:
				var ok bool
				value, ok = node[part]
				require.True(t, ok, "missing JSON field %s", path)
			case []any:
				index, err := strconv.Atoi(part)
				require.NoError(t, err)
				require.Less(t, index, len(node))
				value = node[index]
			default:
				t.Fatalf("unexpected JSON structure at %s", path)
			}
		}
		assert.Equal(t, expected, value, path)
	}
}

func awaitContractPush(t *testing.T, f *apiContractFixture) domain.ChatPushNotification {
	t.Helper()
	select {
	case push := <-f.pushes:
		return push
	case <-time.After(2 * time.Second):
		t.Fatal("background push was not dispatched")
		return domain.ChatPushNotification{}
	}
}

// ตารางนี้ต้องตรงกับ routes จริงทั้งหมด เพื่อให้ endpoint ใหม่ที่ยังไม่มี test ทำให้ suite ล้มเหลว
func TestAllAPIEndpointsSuccess(t *testing.T) {
	fixture := newAPIContractFixture(t)
	var registered, covered []string
	for _, route := range fixture.app().GetRoutes(true) {
		registered = append(registered, route.Method+" "+route.Path)
	}
	for _, tc := range append(apiContractCases(), operationsContractCases()...) {
		covered = append(covered, tc.method+" "+tc.pattern)
		t.Run(tc.method+" "+tc.pattern, func(t *testing.T) {
			f := newAPIContractFixture(t)
			authorization := ""
			if tc.protected {
				authorization = "Bearer " + contractBearer
			}
			recorder := contractRequest(t, f.app(), tc, authorization, contractAppKey)
			require.Equal(t, tc.status, recorder.Code, recorder.Body.String())
			if tc.status == http.StatusNoContent {
				require.Empty(t, recorder.Body.String())
			} else if tc.op == "stream" {
				require.Contains(t, recorder.Header().Get("Content-Type"), "text/event-stream")
				require.Equal(t, "no-cache", recorder.Header().Get("Cache-Control"))
				require.Equal(t, "no", recorder.Header().Get("X-Accel-Buffering"))
				require.Equal(t, contractSSE, recorder.Body.String())
			} else {
				assertContractFields(t, recorder, tc.fields)
			}
			if tc.op != "" {
				require.Equal(t, 1, f.calls[tc.op])
			}
			if tc.path == "/api/push/chat" {
				push := awaitContractPush(t, f)
				require.Equal(t, "Verified name", push.SenderName)
				require.Equal(t, f.profile.UserImageURL, push.SenderAvatar)
				require.Equal(t, "recipient", push.ReceiverID)
			}
		})
	}
	require.ElementsMatch(t, registered, covered)
	require.Len(t, covered, 30)
}

func TestAllAPIEndpointsAppKey(t *testing.T) {
	for _, tc := range apiContractCases() {
		for _, key := range []string{"", "wrong-app-key"} {
			t.Run(tc.method+" "+tc.pattern+"/"+key, func(t *testing.T) {
				f := newAPIContractFixture(t)
				recorder := contractRequest(t, f.app(), tc, "Bearer "+contractBearer, key)
				if tc.path == "/health" {
					require.Equal(t, 200, recorder.Code)
				} else {
					require.Equal(t, 401, recorder.Code, recorder.Body.String())
					require.JSONEq(t, `{"error":"unauthorized"}`, recorder.Body.String())
				}
				require.Empty(t, f.calls)
			})
		}
	}
}

func TestAllProtectedAPIEndpointsAuthentication(t *testing.T) {
	for _, tc := range apiContractCases() {
		if !tc.protected {
			continue
		}
		for _, auth := range []string{"", "Basic invalid", "Bearer", "Bearer ", "Bearer invalid", "Bearer a b"} {
			t.Run(tc.method+" "+tc.pattern+"/"+auth, func(t *testing.T) {
				f := newAPIContractFixture(t)
				recorder := contractRequest(t, f.app(), tc, auth, contractAppKey)
				require.Equal(t, 401, recorder.Code, recorder.Body.String())
				if tc.op != "google" && tc.op != "password" {
					require.Zero(t, f.calls[tc.op], "unauthenticated request reached data operation")
				}
			})
		}
	}
}

func TestProtectedAPIRejectsEmptyVerifiedIdentity(t *testing.T) {
	for _, tc := range apiContractCases() {
		if !tc.protected || tc.op == "google" || tc.op == "password" {
			continue
		}
		t.Run(tc.method+" "+tc.pattern, func(t *testing.T) {
			f := newAPIContractFixture(t)
			f.userID = ""
			recorder := contractRequest(t, f.app(), tc, "Bearer "+contractBearer, contractAppKey)
			require.Equal(t, 401, recorder.Code, recorder.Body.String())
			require.Zero(t, f.calls[tc.op])
		})
	}
}

func TestAllJSONAPIEndpointsMalformedPayload(t *testing.T) {
	for _, tc := range apiContractCases() {
		if tc.body == "" {
			continue
		}
		for _, body := range []string{"", "{broken", "[]", `{"display_name":123,"new_password":123,"query":123,"conversation_id":123,"phone":123,"fcm_token":123,"price":"wrong type","email":123}`} {
			t.Run(tc.method+" "+tc.pattern+"/"+body, func(t *testing.T) {
				f := newAPIContractFixture(t)
				tc.body = body
				recorder := contractRequest(t, f.app(), tc, "Bearer "+contractBearer, contractAppKey)
				require.Equal(t, 400, recorder.Code, recorder.Body.String())
				require.Zero(t, f.calls[tc.op])
			})
		}
	}
}

func TestAPIRepositoryFailureContracts(t *testing.T) {
	for _, tc := range apiContractCases() {
		if tc.op == "" || tc.path == "/api/push/chat" {
			continue
		}
		t.Run(tc.method+" "+tc.pattern, func(t *testing.T) {
			f := newAPIContractFixture(t)
			f.errors[tc.op] = errors.New(contractPrivateDetail)
			recorder := contractRequest(t, f.app(), tc, "Bearer "+contractBearer, contractAppKey)
			status := 500
			switch tc.op {
			case "login":
				status = 401
			case "verifyOTP":
				status = 400
			case "ai", "stream":
				status = 502
			}
			require.Equal(t, status, recorder.Code, recorder.Body.String())
			require.NotContains(t, recorder.Body.String(), contractPrivateDetail, "response leaked internal adapter details")
			require.Contains(t, recorder.Header().Get("Content-Type"), "application/json")
			var payload map[string]any
			require.NoError(t, json.Unmarshal(recorder.Body.Bytes(), &payload))
			require.NotEmpty(t, payload["error"])
		})
	}
}

func TestAPIDomainErrorMappings(t *testing.T) {
	for _, tc := range apiContractCases() {
		var failures []apiFailureCase
		switch tc.op {
		case "register":
			failures = append(failures, apiFailureCase{errors.New("email already registered"), 409})
		case "google":
			failures = append(failures, apiFailureCase{errors.New("invalid access token: " + contractPrivateDetail), 401}, apiFailureCase{errors.New("profile image URL was not found"), 422}, apiFailureCase{errors.New("profile was not found"), 422})
		case "items", "insertItem", "item", "updateItem", "deleteItem":
			failures = append(failures, apiFailureCase{domain.ErrItemNotFound, 404}, apiFailureCase{domain.ErrItemInUse, 409})
		case "rental":
			failures = append(failures, apiFailureCase{domain.ErrItemNotFound, 404}, apiFailureCase{domain.ErrRentalNotFound, 404}, apiFailureCase{domain.ErrRentalUnavailable, 409}, apiFailureCase{domain.ErrInvalidRental, 400})
		case "rentalStatus":
			failures = append(failures, apiFailureCase{domain.ErrRentalNotFound, 404}, apiFailureCase{domain.ErrRentalForbidden, 403}, apiFailureCase{domain.ErrRentalStatusTransition, 409})
		case "chatContact":
			failures = append(failures, apiFailureCase{domain.ErrConversationNotFound, 404}, apiFailureCase{domain.ErrContactForbidden, 403}, apiFailureCase{domain.ErrContactPhoneNotFound, 404})
		case "ai", "stream":
			retry := 12
			failures = append(failures, apiFailureCase{&domain.AIServiceError{StatusCode: 429, Code: "quota_exhausted", RetryAfterSeconds: &retry}, 503}, apiFailureCase{&domain.AIServiceError{StatusCode: 503, Code: "service_unavailable"}, 503})
		}
		for _, failure := range failures {
			t.Run(tc.method+" "+tc.pattern+fmt.Sprint(failure.status)+failure.err.Error(), func(t *testing.T) {
				f := newAPIContractFixture(t)
				f.errors[tc.op] = fmt.Errorf("adapter: %w", failure.err)
				recorder := contractRequest(t, f.app(), tc, "Bearer "+contractBearer, contractAppKey)
				require.Equal(t, failure.status, recorder.Code, recorder.Body.String())
				require.NotContains(t, recorder.Body.String(), contractPrivateDetail)
				var serviceError *domain.AIServiceError
				if errors.As(failure.err, &serviceError) {
					assertContractFields(t, recorder, map[string]any{"error_code": serviceError.Code, "status": "error"})
					if serviceError.RetryAfterSeconds != nil {
						require.Equal(t, "12", recorder.Header().Get("Retry-After"))
					}
				}
			})
		}
	}
}

func operationsContractCases() []apiContractCase {
	return []apiContractCase{
		{http.MethodGet, "/api/identity/status", "/api/identity/status", "", "", 503, true, map[string]any{"error": "ระบบเจ้าหน้าที่และยืนยันตัวตนยังไม่เปิดใช้งาน"}},
		{http.MethodPost, "/api/identity/sessions", "/api/identity/sessions", "", "", 503, true, map[string]any{"error": "ระบบเจ้าหน้าที่และยืนยันตัวตนยังไม่เปิดใช้งาน"}},
		{http.MethodPost, "/api/identity/sessions/:id/submit", "/api/identity/sessions/test/submit", "", "", 503, true, map[string]any{"error": "ระบบเจ้าหน้าที่และยืนยันตัวตนยังไม่เปิดใช้งาน"}},
		{http.MethodPost, "/api/complaints", "/api/complaints", "", "", 503, true, map[string]any{"error": "ระบบเจ้าหน้าที่และยืนยันตัวตนยังไม่เปิดใช้งาน"}},
		{http.MethodGet, "/api/admin/evidence/:id", "/api/admin/evidence/test", "", "", 503, true, map[string]any{"error": "ระบบเจ้าหน้าที่และยืนยันตัวตนยังไม่เปิดใช้งาน"}},
		{http.MethodGet, "/api/admin/:module", "/api/admin/overview", "", "", 503, true, map[string]any{"error": "ระบบเจ้าหน้าที่และยืนยันตัวตนยังไม่เปิดใช้งาน"}},
		{http.MethodPost, "/api/admin/actions/:action/:target", "/api/admin/actions/hide-item/7", "", "", 503, true, map[string]any{"error": "ระบบเจ้าหน้าที่และยืนยันตัวตนยังไม่เปิดใช้งาน"}},
	}
}
