package ports_test

import (
	"context"
	"encoding/json"
	"errors"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	ports "github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	"github.com/gofiber/fiber/v3"
)

const notificationTestID = "10000000-0000-4000-8000-000000000001"

type notificationTestVerifier struct{}

func (notificationTestVerifier) UserIDFromToken(_ context.Context, token string) (string, error) {
	if token != "valid" {
		return "", errors.New("invalid")
	}
	return "authenticated-user", nil
}

type notificationTestStore struct {
	domain.NotificationRepository
	calls        int
	user         string
	filter       domain.NotificationFilter
	target       domain.NotificationReadTarget
	device       domain.NotificationDevice
	installation string
	err          error
}

func (s *notificationTestStore) ListNotifications(_ context.Context, user string, filter domain.NotificationFilter) (*domain.NotificationPage, error) {
	s.calls++
	s.user = user
	s.filter = filter
	return &domain.NotificationPage{Items: []domain.Notification{}, UnreadCount: 3, ServerTime: time.Date(2026, 10, 19, 0, 0, 0, 0, time.UTC)}, s.err
}
func (s *notificationTestStore) MarkNotificationsRead(_ context.Context, user string, target domain.NotificationReadTarget) error {
	s.calls++
	s.user = user
	s.target = target
	return s.err
}
func (s *notificationTestStore) RegisterNotificationDevice(_ context.Context, user string, device domain.NotificationDevice) error {
	s.calls++
	s.user = user
	s.device = device
	return s.err
}
func (s *notificationTestStore) UnregisterNotificationDevice(_ context.Context, user, id string) error {
	s.calls++
	s.user = user
	s.installation = id
	return s.err
}

func notificationTestApp(store *notificationTestStore) *fiber.App {
	app := ports.NewHTTPApp()
	h := ports.NewNotificationHandler(store, notificationTestVerifier{})
	app.Get("/notifications", h.ListNotifications)
	app.Post("/notifications/read-all", h.MarkAllNotificationsRead)
	app.Post("/notifications/read-conversation", h.MarkConversationRead)
	app.Post("/notifications/:id/read", h.MarkNotificationRead)
	app.Put("/notifications/devices", h.RegisterDevice)
	app.Delete("/notifications/devices/:installation_id", h.UnregisterDevice)
	return app
}

func TestNotificationEndpointsRequireIdentityAndValidateInputs(t *testing.T) {
	for _, tc := range []struct {
		name, method, path, body, token string
		status, calls                   int
	}{
		{"private list", "GET", "/notifications", "", "", 401, 0},
		{"private read", "POST", "/notifications/" + notificationTestID + "/read", "{}", "", 401, 0},
		{"private register", "PUT", "/notifications/devices", `{"installation_id":"installation-aaaa","token":"device-token-value","platform":"android"}`, "", 401, 0},
		{"private unregister", "DELETE", "/notifications/devices/installation-aaaa", "", "", 401, 0},
		{"bad pagination", "GET", "/notifications?limit=101", "", "valid", 400, 0},
		{"bad offset", "GET", "/notifications?offset=-1", "", "valid", 400, 0},
		{"bad category", "GET", "/notifications?category=other", "", "valid", 400, 0},
		{"bad id", "POST", "/notifications/not-uuid/read", "{}", "valid", 400, 0},
		{"missing conversation", "POST", "/notifications/read-conversation", "{}", "valid", 400, 0},
		{"bad timestamp", "POST", "/notifications/read-all", `{"read_through":"later"}`, "valid", 400, 0},
		{"invalid device platform", "PUT", "/notifications/devices", `{"installation_id":"installation-a","token":"device","platform":"other"}`, "valid", 400, 0},
		{"invalid device token", "PUT", "/notifications/devices", `{"installation_id":"installation-a","token":"device token","platform":"android"}`, "valid", 400, 0},
		{"valid device", "PUT", "/notifications/devices", `{"installation_id":"installation-aaaa","token":"device-token-value","platform":"android","user_id":"victim"}`, "valid", 200, 1},
		{"valid unregister", "DELETE", "/notifications/devices/installation-aaaa", "", "valid", 200, 1},
	} {
		t.Run(tc.name, func(t *testing.T) {
			store := &notificationTestStore{}
			app := notificationTestApp(store)
			defer app.Shutdown()
			req := httptest.NewRequest(tc.method, tc.path, strings.NewReader(tc.body))
			req.Header.Set("Content-Type", "application/json")
			if tc.token != "" {
				req.Header.Set("Authorization", "Bearer "+tc.token)
			}
			res, err := app.Test(req)
			if err != nil {
				t.Fatal(err)
			}
			defer res.Body.Close()
			if res.StatusCode != tc.status || store.calls != tc.calls {
				t.Fatalf("status=%d calls=%d", res.StatusCode, store.calls)
			}
			if store.calls > 0 && store.user != "authenticated-user" {
				t.Fatalf("caller-selected user=%q", store.user)
			}
		})
	}
}

func TestNotificationReadForwardsWatermarkAndConversationUnderVerifiedIdentity(t *testing.T) {
	store := &notificationTestStore{}
	app := notificationTestApp(store)
	defer app.Shutdown()
	req := httptest.NewRequest("POST", "/notifications/read-conversation", strings.NewReader(`{"conversation_id":"`+notificationTestID+`","read_through":"2026-10-19T10:15:00Z","user_id":"victim"}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer valid")
	res, err := app.Test(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != 200 || store.user != "authenticated-user" || store.target.ConversationID != notificationTestID || store.target.ReadThrough == nil || store.target.ReadThrough.Format(time.RFC3339) != "2026-10-19T10:15:00Z" {
		t.Fatalf("status=%d user=%q target=%#v", res.StatusCode, store.user, store.target)
	}
}

func TestNotificationListExposesServerWatermarkAndTotalUnread(t *testing.T) {
	store := &notificationTestStore{}
	app := notificationTestApp(store)
	defer app.Shutdown()
	req := httptest.NewRequest("GET", "/notifications?category=rental&limit=20&offset=40", nil)
	req.Header.Set("Authorization", "Bearer valid")
	res, err := app.Test(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.Header.Get("Cache-Control") != "private, no-store" {
		t.Fatalf("private inbox cache policy=%q", res.Header.Get("Cache-Control"))
	}
	var page domain.NotificationPage
	if err := json.NewDecoder(res.Body).Decode(&page); err != nil {
		t.Fatal(err)
	}
	if page.Items == nil || page.UnreadCount != 3 || page.ServerTime.IsZero() || store.filter.Category != "rental" || store.filter.Limit != 20 || store.filter.Offset != 40 {
		t.Fatalf("page=%#v filter=%#v", page, store.filter)
	}
}
