package supabase_test

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	supabase "github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	supabaseclient "github.com/nedpals/supabase-go"
)

func TestNotificationRepositoryRPCContractsKeepIdentityAndLease(t *testing.T) {
	var calls []string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.Method != "POST" || r.Header.Get("apikey") != "service-key" {
			t.Errorf("unexpected RPC authentication")
		}
		var args map[string]any
		if err := json.NewDecoder(r.Body).Decode(&args); err != nil {
			t.Error(err)
		}
		name := strings.TrimPrefix(r.URL.Path, "/rest/v1/rpc/")
		calls = append(calls, name)
		switch name {
		case "notification_list":
			if args["p_user_id"] != "user" || args["p_category"] != nil || args["p_limit"] != float64(40) {
				t.Errorf("list args=%#v", args)
			}
			_, _ = w.Write([]byte(`{"items":[],"unread_count":4,"server_time":"2026-10-19T00:00:00Z"}`))
		case "notification_mark_read":
			if args["p_user_id"] != "user" || args["p_id"] != "inbox" || args["p_conversation_id"] != nil || args["p_read_through"] != "2026-10-19T00:00:00Z" {
				t.Errorf("read args=%#v", args)
			}
			_, _ = w.Write([]byte(`1`))
		case "notification_claim_outbox":
			if args["p_limit"] != float64(20) || args["p_lease_seconds"] != float64(120) {
				t.Errorf("claim args=%#v", args)
			}
			_, _ = w.Write([]byte(`[{"id":"outbox","lease_token":"lease","device_id":"device","user_id":"user","token":"snapshot","notification_id":"inbox","payload":{"category":"chat","type":"chat_message","title":"Sender","body":"hello","conversation_id":"room"}}]`))
		case "notification_complete_delivery":
			if args["p_id"] != "outbox" || args["p_lease_token"] != "lease" || args["p_outcome"] != "invalid_token" || args["p_error"] != "unregistered" {
				t.Errorf("completion args=%#v", args)
			}
			_, _ = w.Write([]byte(`null`))
		default:
			t.Errorf("unexpected RPC: %s", name)
			w.WriteHeader(404)
		}
	}))
	defer server.Close()
	repo := supabase.NewSupabaseNotificationRepository(supabaseclient.CreateClient(server.URL, "service-key"))
	ctx := context.Background()
	page, err := repo.ListNotifications(ctx, "user", domain.NotificationFilter{Limit: 40})
	if err != nil || page.UnreadCount != 4 || page.Items == nil {
		t.Fatalf("page=%#v err=%v", page, err)
	}
	watermark := time.Date(2026, 10, 19, 0, 0, 0, 0, time.UTC)
	if err := repo.MarkNotificationsRead(ctx, "user", domain.NotificationReadTarget{ID: "inbox", ReadThrough: &watermark}); err != nil {
		t.Fatal(err)
	}
	deliveries, err := repo.ClaimNotificationDeliveries(ctx, 20, 120*time.Second)
	if err != nil || len(deliveries) != 1 || deliveries[0].Token != "snapshot" || deliveries[0].Payload.Body != "hello" {
		t.Fatalf("deliveries=%#v err=%v", deliveries, err)
	}
	if err := repo.CompleteNotificationDelivery(ctx, domain.NotificationDeliveryResult{ID: "outbox", LeaseToken: "lease", Outcome: "invalid_token", ErrorCode: "unregistered"}); err != nil {
		t.Fatal(err)
	}
	if len(calls) != 4 {
		t.Fatalf("calls=%v", calls)
	}
}

func TestNotificationRepositoryMapsOwnershipError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(403)
		_, _ = w.Write([]byte(`{"code":"42501","message":"notification_forbidden"}`))
	}))
	defer server.Close()
	repo := supabase.NewSupabaseNotificationRepository(supabaseclient.CreateClient(server.URL, "service-key"))
	if err := repo.MarkNotificationsRead(context.Background(), "user", domain.NotificationReadTarget{ID: "another-user"}); !errors.Is(err, domain.ErrNotificationForbidden) {
		t.Fatalf("err=%v", err)
	}
}
