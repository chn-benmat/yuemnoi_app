package tests

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	supabaseadapter "github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	supabaseclient "github.com/nedpals/supabase-go"
)

type rankedItemRepositoryStub struct {
	items []domain.RankedItem
}

func (*rankedItemRepositoryStub) Insert(context.Context, *domain.Item, []domain.ItemImage) (*domain.Item, error) {
	return nil, domain.ErrItemNotFound
}

func (r *rankedItemRepositoryStub) FindAll(context.Context) ([]domain.RankedItem, error) {
	return r.items, nil
}

func (*rankedItemRepositoryStub) FindByID(context.Context, int64) (*domain.Item, error) {
	return nil, domain.ErrItemNotFound
}

func (*rankedItemRepositoryStub) Update(context.Context, int64, string, map[string]interface{}) (*domain.Item, error) {
	return nil, domain.ErrItemNotFound
}

func (*rankedItemRepositoryStub) Delete(context.Context, int64, string) error {
	return domain.ErrItemNotFound
}

type rankedItemTokenVerifierStub struct{}

func (rankedItemTokenVerifierStub) UserIDFromToken(context.Context, string) (string, error) {
	return "test-user", nil
}

func TestItemRepositoryReadsRankedViewInRankPositionOrder(t *testing.T) {
	var feedRequested bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/rest/v1/home_feed_ranked_v":
			feedRequested = true
			if got := r.URL.Query().Get("order"); got != "rank_position.asc" {
				t.Errorf("expected rank_position order, got %q", got)
			}
			selected := r.URL.Query().Get("select")
			if strings.Contains(selected, "rank_score") || !strings.Contains(selected, "paid_booking_count") {
				t.Errorf("unexpected selected columns: %q", selected)
			}
			_, _ = w.Write([]byte(`[
				{"id":29,"user_id":"owner-a","item_name":"popular","item_image_url":[],"description":"","category":"camera","price":900,"status":"available","type":"รายวัน","rating":4.8,"review_count":12,"paid_booking_count":7},
				{"id":8,"user_id":"owner-b","item_name":"fresh","item_image_url":[],"description":"","category":"audio","price":500,"status":"available","type":"รายวัน","rating":0,"review_count":0,"paid_booking_count":0}
			]`))
		case "/rest/v1/profile_tb":
			_ = json.NewEncoder(w).Encode([]map[string]string{
				{"user_id": "owner-a", "email": "alice@example.test", "user_image_url": "avatar-a"},
				{"user_id": "owner-b", "email": "bob@example.test", "user_image_url": "avatar-b"},
			})
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	client := supabaseclient.CreateClient(server.URL, "test-service-key")
	repository := supabaseadapter.NewSupabaseItemRepository(client, "test-service-key")
	items, err := repository.FindAll(context.Background())
	if err != nil {
		t.Fatal(err)
	}

	if !feedRequested {
		t.Fatal("expected ranked feed view to be requested")
	}
	if len(items) != 2 || items[0].ID != 29 || items[1].ID != 8 {
		t.Fatalf("expected ranked view order, got %#v", items)
	}
	if items[0].Rating != 4.8 || items[0].ReviewCount != 12 || items[0].PaidBookingCount != 7 {
		t.Fatalf("expected ranking metrics, got %#v", items[0])
	}
	if items[0].OwnerName != "alice" || items[1].OwnerName != "bob" {
		t.Fatalf("expected owner profiles, got %#v", items)
	}
}

func TestGetAllItemsPreservesRankedOrderAndHidesInternalScore(t *testing.T) {

	repository := &rankedItemRepositoryStub{items: []domain.RankedItem{
		{
			Item:             domain.Item{ID: 29, ItemName: "กล้องยอดนิยม"},
			Rating:           4.8,
			ReviewCount:      12,
			PaidBookingCount: 7,
		},
		{
			Item: domain.Item{ID: 8, ItemName: "กล้องใหม่"},
		},
	}}
	handler := ports.NewItemHandler(repository, rankedItemTokenVerifierStub{})
	router := ports.NewHTTPApp()
	router.Get("/api/items", handler.GetAllItems)

	request := httptest.NewRequest(http.MethodGet, "/api/items", nil)
	response := httptest.NewRecorder()
	performFiberRequest(t, router, response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d: %s", response.Code, response.Body.String())
	}
	var payload []map[string]any
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if len(payload) != 2 || payload[0]["id"] != float64(29) || payload[1]["id"] != float64(8) {
		t.Fatalf("expected ranked repository order, got %#v", payload)
	}
	if payload[0]["rating"] != 4.8 || payload[0]["review_count"] != float64(12) || payload[0]["paid_booking_count"] != float64(7) {
		t.Fatalf("expected real ranking metrics, got %#v", payload[0])
	}
	if _, exposed := payload[0]["rank_score"]; exposed {
		t.Fatalf("rank_score must not be exposed: %#v", payload[0])
	}
}
