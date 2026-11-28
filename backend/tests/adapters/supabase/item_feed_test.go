package supabase_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"testing"

	supabaseadapter "github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	supabaseclient "github.com/nedpals/supabase-go"
)

func TestItemFeedReturnsPickupLocation(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/rest/v1/home_feed_ranked_v":
			item := map[string]any{"id": 11, "item_name": "Camera"}
			if slices.Contains(strings.Split(r.URL.Query().Get("select"), ","), "pickup_location") {
				item["pickup_location"] = "Library"
			}
			_ = json.NewEncoder(w).Encode([]map[string]any{item})
		case "/rest/v1/public_profile_v":
			_, _ = w.Write([]byte(`[]`))
		default:
			t.Errorf("unexpected request: %s", r.URL.Path)
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer server.Close()

	repo := supabaseadapter.NewSupabaseItemRepository(supabaseclient.CreateClient(server.URL, "test-key"), "test-key")
	items, err := repo.FindAll(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 1 || items[0].PickupLocation != "Library" {
		t.Fatalf("expected an item with pickup location Library, got %+v", items)
	}
}

func TestItemFeedReturnsDatabaseRates(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/rest/v1/home_feed_ranked_v":
			columns := strings.Split(r.URL.Query().Get("select"), ",")
			item := map[string]any{"id": 11, "item_name": "Tripod"}
			if slices.Contains(columns, "hourly_rate") && slices.Contains(columns, "daily_rate") {
				item["hourly_rate"] = 50
				item["daily_rate"] = 300
			}
			_ = json.NewEncoder(w).Encode([]map[string]any{item})
		case "/rest/v1/public_profile_v":
			_, _ = w.Write([]byte(`[]`))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer server.Close()

	repo := supabaseadapter.NewSupabaseItemRepository(supabaseclient.CreateClient(server.URL, "test-key"), "test-key")
	items, err := repo.FindAll(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 1 || items[0].HourlyRate == nil || *items[0].HourlyRate != 50 ||
		items[0].DailyRate == nil || *items[0].DailyRate != 300 {
		t.Fatalf("expected the feed to carry database rates, got %+v", items)
	}
}
