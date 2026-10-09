package tests

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"mime/multipart"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/stretchr/testify/require"
)

func contractCaseFor(t *testing.T, method, path string) apiContractCase {
	t.Helper()
	for _, tc := range apiContractCases() {
		if tc.method == method && tc.path == path {
			return tc
		}
	}
	t.Fatalf("missing contract case: %s %s", method, path)
	return apiContractCase{}
}

func replaceContractField(t *testing.T, body, field string, value any) string {
	t.Helper()
	var object map[string]any
	require.NoError(t, json.Unmarshal([]byte(body), &object))
	object[field] = value
	encoded, err := json.Marshal(object)
	require.NoError(t, err)
	return string(encoded)
}

func TestAPIRejectsInvalidFieldValues(t *testing.T) {
	cases := []struct {
		method, path, field string
		values              []any
	}{
		{"POST", "/api/auth/register", "display_name", []any{"", " \t ", strings.Repeat("ก", 151)}},
		{"POST", "/api/auth/register", "email", []any{"", "invalid", "a@"}},
		{"POST", "/api/auth/register", "phone", []any{"", "123", "+14155551234", "08123456789", "08abcdefgh"}},
		{"POST", "/api/auth/register", "password", []any{"", "12345"}},
		{"POST", "/api/auth/register", "confirm_password", []any{"different", "123"}},
		{"POST", "/api/auth/login", "email", []any{"", "invalid"}},
		{"POST", "/api/auth/login", "password", []any{"", "12345"}},
		{"POST", "/api/auth/send-otp", "email", []any{"", "invalid"}},
		{"POST", "/api/auth/verify-otp", "otp_code", []any{"", "12345", "1234567", "abcdef"}},
		{"POST", "/api/auth/change-password", "new_password", []any{"", "12345"}},
		{"PUT", "/api/user/profile", "display_name", []any{strings.Repeat("ก", 151)}},
		{"PUT", "/api/user/profile", "username", []any{strings.Repeat("u", 101)}},
		{"PUT", "/api/user/profile", "bio", []any{strings.Repeat("ก", 501)}},
		{"PUT", "/api/user/contact", "phone", []any{"", " ", "123", "abc", "+14155551234"}},
		{"POST", "/api/user/fcm-token", "fcm_token", []any{"", " \t\n "}},
		{"POST", "/api/items", "item_name", []any{"", " \t ", strings.Repeat("ก", 151)}},
		{"POST", "/api/items", "description", []any{"", " \t ", strings.Repeat("ก", 2001)}},
		{"POST", "/api/items", "category", []any{"", " \t ", strings.Repeat("ก", 101)}},
		{"POST", "/api/items", "price", []any{0, -1, 1.5, "100"}},
		{"POST", "/api/items", "type", []any{"", "weekly"}},
		{"POST", "/api/items", "item_image_url", []any{[]string{strings.Repeat("a", 2049)}}},
		{"PUT", "/api/items/7", "item_name", []any{"", " \t ", strings.Repeat("a", 151)}},
		{"PUT", "/api/items/7", "description", []any{"", " \t ", strings.Repeat("a", 2001)}},
		{"PUT", "/api/items/7", "price", []any{0, -1}},
		{"PUT", "/api/items/7", "category", []any{strings.Repeat("a", 101)}},
		{"PUT", "/api/items/7", "status", []any{strings.Repeat("a", 51)}},
		{"PUT", "/api/items/7", "type", []any{strings.Repeat("a", 101)}},
		{"PUT", "/api/items/7", "item_image_url", []any{[]string{strings.Repeat("a", 2049)}}},
		{"POST", "/api/rentals", "item_id", []any{0, -1, 1.5}},
		{"POST", "/api/rentals", "start_at", []any{"", "invalid-date", "2026-10-12T01:00:00Z", "2026-10-13T01:00:00Z"}},
		{"POST", "/api/rentals", "end_at", []any{"", "2026-10-10T01:00:00Z", "2026-10-09T01:00:00Z"}},
		{"POST", "/api/rentals", "rental_type", []any{"", "weekly"}},
		{"POST", "/api/rentals", "pickup_location", []any{"", " \t ", strings.Repeat("ก", 501)}},
		{"POST", "/api/push/chat", "receiver_id", []any{"", " \t ", "verified-user"}},
		{"POST", "/api/push/chat", "conversation_id", []any{"", " \t "}},
		{"POST", "/api/chat/contact", "conversation_id", []any{"", " \t "}},
		{"POST", "/api/chat-ai", "query", []any{"", " \t ", nil}},
		{"POST", "/api/chat-ai/stream", "query", []any{"", " \t ", nil}},
	}
	for _, c := range cases {
		for index, value := range c.values {
			t.Run(fmt.Sprintf("%s %s/%s/%d", c.method, c.path, c.field, index), func(t *testing.T) {
				f := newAPIContractFixture(t)
				tc := contractCaseFor(t, c.method, c.path)
				tc.body = replaceContractField(t, tc.body, c.field, value)
				recorder := contractRequest(t, f.app(), tc, "Bearer "+contractBearer, contractAppKey)
				require.Equal(t, 400, recorder.Code, recorder.Body.String())
				require.Zero(t, f.calls[tc.op], "invalid payload reached adapter")
			})
		}
	}
}

func TestAPIRejectsInvalidPathIDs(t *testing.T) {
	for _, tc := range apiContractCases() {
		if !strings.Contains(tc.pattern, ":id") {
			continue
		}
		for _, id := range []string{"0", "-1", "abc", "1.5", "9223372036854775808"} {
			t.Run(tc.method+" "+tc.pattern+"/"+id, func(t *testing.T) {
				f := newAPIContractFixture(t)
				tc.path = strings.Replace(tc.pattern, ":id", id, 1)
				recorder := contractRequest(t, f.app(), tc, "Bearer "+contractBearer, contractAppKey)
				require.Equal(t, 400, recorder.Code, recorder.Body.String())
				require.Zero(t, f.calls[tc.op])
			})
		}
	}
}

func TestAPIUsesVerifiedIdentityAndAllowedFields(t *testing.T) {
	for _, tc := range apiContractCases() {
		if !tc.protected || tc.op == "google" || tc.op == "password" || tc.path == "/api/push/chat" {
			continue
		}
		t.Run(tc.method+" "+tc.pattern, func(t *testing.T) {
			f := newAPIContractFixture(t)
			if tc.body != "" {
				tc.body = replaceContractField(t, tc.body, "user_id", "spoofed-user")
			}
			if tc.op == "rental" {
				tc.body = replaceContractField(t, tc.body, "total_price", 1)
				tc.body = replaceContractField(t, tc.body, "status", "completed")
			}
			recorder := contractRequest(t, f.app(), tc, "bEaReR "+contractBearer, contractAppKey)
			require.Equal(t, tc.status, recorder.Code, recorder.Body.String())
			args := f.args[tc.op]
			switch tc.op {
			case "insertItem":
				require.Equal(t, "verified-user", args[0].(domain.Item).UserID)
				require.Equal(t, "available", args[0].(domain.Item).Status)
			case "updateItem":
				require.Equal(t, "verified-user", args[1])
				fields := args[2].(map[string]interface{})
				require.NotContains(t, fields, "user_id")
				require.Equal(t, 150, fields["price"])
				require.WithinDuration(t, time.Now(), fields["updated_at"].(time.Time), 5*time.Second)
			case "deleteItem":
				require.Equal(t, "verified-user", args[1])
			case "rental":
				require.Equal(t, "verified-user", args[0])
				assertContractFields(t, recorder, map[string]any{"total_price": float64(200), "status": "pending"})
			default:
				require.Equal(t, "verified-user", args[0])
			}
		})
	}
}

func TestAPIAdditionalUserAndPushBranches(t *testing.T) {
	t.Run("email lookup failure", func(t *testing.T) {
		f := newAPIContractFixture(t)
		f.errors["emailExists"] = errors.New(contractPrivateDetail)
		recorder := contractRequest(t, f.app(), contractCaseFor(t, "POST", "/api/auth/send-otp"), "", contractAppKey)
		require.Equal(t, 500, recorder.Code)
		require.NotContains(t, recorder.Body.String(), contractPrivateDetail)
		require.Zero(t, f.calls["sendOTP"])
	})
	t.Run("unknown email does not send OTP", func(t *testing.T) {
		f := newAPIContractFixture(t)
		f.emailExists = false
		recorder := contractRequest(t, f.app(), contractCaseFor(t, "POST", "/api/auth/send-otp"), "", contractAppKey)
		require.Equal(t, 404, recorder.Code)
		require.Zero(t, f.calls["sendOTP"])
	})
	for _, phone := range []string{"0812345678", "+66812345678", "66812345678", " 0812345678 "} {
		t.Run("phone normalization/"+phone, func(t *testing.T) {
			f := newAPIContractFixture(t)
			tc := contractCaseFor(t, "PUT", "/api/user/contact")
			tc.body = replaceContractField(t, tc.body, "phone", phone)
			recorder := contractRequest(t, f.app(), tc, "Bearer "+contractBearer, contractAppKey)
			require.Equal(t, 200, recorder.Code)
			require.Equal(t, "+66812345678", f.args["contact"][1])
		})
	}
	t.Run("empty item update", func(t *testing.T) {
		f := newAPIContractFixture(t)
		tc := contractCaseFor(t, "PUT", "/api/items/7")
		tc.body = `{}`
		recorder := contractRequest(t, f.app(), tc, "Bearer "+contractBearer, contractAppKey)
		require.Equal(t, 400, recorder.Code)
		require.Zero(t, f.calls["updateItem"])
	})
	for _, c := range []struct {
		name, expected          string
		profile                 *domain.UserProfile
		profileError, pushError error
	}{
		{"profile failure uses default sender", "ผู้ใช้งาน Yuemnoi", nil, errors.New(contractPrivateDetail), nil},
		{"missing profile uses default sender", "ผู้ใช้งาน Yuemnoi", nil, nil, nil},
		{"email prefix is fallback sender", "fixture", &domain.UserProfile{Email: "fixture@example.test"}, nil, nil},
		{"background delivery failure stays queued", "Verified name", &domain.UserProfile{DisplayName: "Verified name"}, nil, errors.New(contractPrivateDetail)},
	} {
		t.Run(c.name, func(t *testing.T) {
			f := newAPIContractFixture(t)
			f.profile, f.errors["profile"], f.pushError = c.profile, c.profileError, c.pushError
			recorder := contractRequest(t, f.app(), contractCaseFor(t, "POST", "/api/push/chat"), "Bearer "+contractBearer, contractAppKey)
			require.Equal(t, 200, recorder.Code)
			require.JSONEq(t, `{"status":"queued"}`, recorder.Body.String())
			require.Equal(t, c.expected, awaitContractPush(t, f).SenderName)
		})
	}
}

func TestAPIItemUpdateAndSearchContracts(t *testing.T) {
	t.Run("all editable fields", func(t *testing.T) {
		f := newAPIContractFixture(t)
		tc := contractCaseFor(t, "PUT", "/api/items/7")
		tc.body = `{"item_name":"Updated","description":"Updated description","category":"Updated category","price":200,"status":"available","type":"hourly","item_image_url":["https://example.test/image.png"],"user_id":"spoofed"}`
		recorder := contractRequest(t, f.app(), tc, "Bearer "+contractBearer, contractAppKey)
		require.Equal(t, 200, recorder.Code)
		fields := f.args["updateItem"][2].(map[string]interface{})
		require.Len(t, fields, 8)
		require.Equal(t, "Updated", fields["item_name"])
		require.Equal(t, "Updated description", fields["description"])
		require.Equal(t, "Updated category", fields["category"])
		require.Equal(t, "hourly", fields["type"])
		require.Equal(t, []string{"https://example.test/image.png"}, fields["item_image_url"])
		require.NotContains(t, fields, "user_id")
	})
	for _, c := range []struct {
		query string
		count int
	}{
		{"?search=CAMERA", 1}, {"?search=missing", 0}, {"?category=Camera&search=digital", 1},
		{"?category=Other", 0}, {"?category=all", 1}, {"?category=other&search=camera", 0},
	} {
		t.Run(c.query, func(t *testing.T) {
			f := newAPIContractFixture(t)
			tc := contractCaseFor(t, "GET", "/api/items")
			tc.path += c.query
			recorder := contractRequest(t, f.app(), tc, "", contractAppKey)
			require.Equal(t, 200, recorder.Code)
			var items []domain.RankedItem
			require.NoError(t, json.Unmarshal(recorder.Body.Bytes(), &items))
			require.Len(t, items, c.count)
			if c.count == 0 {
				require.JSONEq(t, `[]`, recorder.Body.String())
			}
		})
	}
}

func TestAPIRejectsMalformedMultipart(t *testing.T) {
	for _, c := range []struct{ method, path string }{{"POST", "/api/auth/register"}, {"PUT", "/api/user/profile"}, {"POST", "/api/items"}} {
		t.Run(c.path, func(t *testing.T) {
			f := newAPIContractFixture(t)
			request := httptest.NewRequest(c.method, c.path, strings.NewReader("invalid multipart body"))
			request.Header.Set("Content-Type", "multipart/form-data; boundary=missing-boundary")
			request.Header.Set("Authorization", "Bearer "+contractBearer)
			request.Header.Set("X-App-Secret", contractAppKey)
			recorder := httptest.NewRecorder()
			performFiberRequest(t, f.app(), recorder, request)
			require.Equal(t, 400, recorder.Code, recorder.Body.String())
			require.Zero(t, f.calls[contractCaseFor(t, c.method, c.path).op])
		})
	}
}

func TestAPIUploadRejectsEmptyAndUnsupportedImages(t *testing.T) {
	for _, route := range []struct {
		method, path, field string
		fields              map[string]string
	}{
		{"POST", "/api/auth/register", "image", map[string]string{"display_name": "Fixture", "email": "fixture@example.test", "phone": "0812345678", "password": "abcdef"}},
		{"PUT", "/api/user/profile", "image", map[string]string{"bio": "updated"}},
		{"POST", "/api/items", "images", map[string]string{"item_name": "Camera", "description": "Camera", "category": "Camera", "price": "100", "type": "daily"}},
	} {
		for _, c := range []struct{ name, data string }{{"empty", ""}, {"text disguised as PNG", "not-an-image"}, {"GIF is unsupported", "GIF89a0123456789"}} {
			t.Run(route.path+"/"+c.name, func(t *testing.T) {
				f := newAPIContractFixture(t)
				var body bytes.Buffer
				writer := multipart.NewWriter(&body)
				for key, value := range route.fields {
					require.NoError(t, writer.WriteField(key, value))
				}
				file, err := writer.CreateFormFile(route.field, "fake.png")
				require.NoError(t, err)
				_, err = file.Write([]byte(c.data))
				require.NoError(t, err)
				require.NoError(t, writer.Close())
				request := httptest.NewRequest(route.method, route.path, &body)
				request.Header.Set("Content-Type", writer.FormDataContentType())
				request.Header.Set("Authorization", "Bearer "+contractBearer)
				request.Header.Set("X-App-Secret", contractAppKey)
				recorder := httptest.NewRecorder()
				performFiberRequest(t, f.app(), recorder, request)
				require.Equal(t, 400, recorder.Code, recorder.Body.String())
				require.Zero(t, f.calls[contractCaseFor(t, route.method, route.path).op])
			})
		}
	}
}

func TestProfileAPIRejectsOversizedImages(t *testing.T) {
	for _, c := range []struct {
		method, path string
		fields       map[string]string
	}{
		{"POST", "/api/auth/register", map[string]string{"display_name": "Fixture", "email": "fixture@example.test", "phone": "0812345678", "password": "abcdef"}},
		{"PUT", "/api/user/profile", map[string]string{"bio": "updated"}},
	} {
		t.Run(c.path, func(t *testing.T) {
			f := newAPIContractFixture(t)
			request := multipartRequest(t, c.method, c.path, c.fields, "image", 1, (5<<20)+1)
			request.Header.Set("Authorization", "Bearer "+contractBearer)
			request.Header.Set("X-App-Secret", contractAppKey)
			recorder := httptest.NewRecorder()
			performFiberRequest(t, f.app(), recorder, request)
			require.Equal(t, 400, recorder.Code)
			require.Zero(t, f.calls[contractCaseFor(t, c.method, c.path).op])
		})
	}
}
