package supabase_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	supabaseadapter "github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	supabaseclient "github.com/nedpals/supabase-go"
)

func TestItemFeedReturnsPickupLocation(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/rest/v1/rpc/get_home_catalog":
			_ = json.NewEncoder(w).Encode([]map[string]any{{"id": 11, "item_name": "Camera", "pickup_location": "Library"}})
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
		case "/rest/v1/rpc/get_home_catalog":
			_ = json.NewEncoder(w).Encode([]map[string]any{{"id": 11, "item_name": "Tripod", "hourly_rate": 50, "daily_rate": 300}})
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

func TestItemFeedUsesTheSharedRankingAndOwnerFields(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path != "/rest/v1/rpc/get_home_catalog" {
			t.Errorf("catalog must come from the shared ranking RPC, got %s", r.URL.Path)
			w.WriteHeader(http.StatusNotFound)
			return
		}
		_, _ = w.Write([]byte(`[{"id":2,"item_name":"Tent","owner_name":"Alice","owner_avatar_url":"https://example.com/a.png","is_verified":true,"rating":4.5,"review_count":2,"paid_booking_count":3,"is_rental_occupied":true},{"id":1,"item_name":"Camera","owner_name":"Bob"}]`))
	}))
	defer server.Close()

	repo := supabaseadapter.NewSupabaseItemRepository(supabaseclient.CreateClient(server.URL, "test-key"), "test-key")
	items, err := repo.FindAll(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 2 || items[0].ID != 2 || items[1].ID != 1 {
		t.Fatalf("catalog order must be kept, got %+v", items)
	}
	first := items[0]
	if first.OwnerName != "Alice" || !first.IsVerified || first.OwnerAvatarURL == "" || first.Rating != 4.5 ||
		first.ReviewCount != 2 || first.PaidBookingCount != 3 || !first.IsRentalOccupied {
		t.Fatalf("catalog fields lost: %+v", first)
	}
}
