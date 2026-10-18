package ports

import (
	"bytes"
	"context"
	"math"
	"mime/multipart"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

func TestPickupRequiresExplicitFiniteCoordinates(t *testing.T) {
	zero, valid, invalid, nan := 0.0, 13.7, 181.0, math.NaN()
	for _, test := range []struct {
		name     string
		lat, lng *float64
		want     bool
	}{
		{"equator", &zero, &zero, true}, {"missing", nil, &valid, false},
		{"out of range", &valid, &invalid, false}, {"nan", &nan, &valid, false},
	} {
		t.Run(test.name, func(t *testing.T) {
			if got := validPickupLocation("point", test.lat, test.lng); got != test.want {
				t.Fatalf("valid=%v, want=%v", got, test.want)
			}
		})
	}
	if validPickupLocation("  ", &valid, &valid) {
		t.Fatal("blank location accepted")
	}
}

type pickupItemRepository struct {
	itemManagementRepository
	inserted *domain.Item
}

func (r *pickupItemRepository) Insert(_ context.Context, item *domain.Item, _ []domain.ItemImage) (*domain.Item, error) {
	r.inserted = item
	item.ID = 100
	return item, nil
}

func TestMultipartItemRetainsConfirmedPickup(t *testing.T) {
	repo := &pickupItemRepository{}
	app := NewHTTPApp()
	defer app.Shutdown()
	handler := NewItemHandler(repo, itemManagementVerifier{})
	app.Post("/api/items", handler.CreateItem)
	var body bytes.Buffer
	form := multipart.NewWriter(&body)
	for key, value := range map[string]string{"item_name": "camera", "description": "description", "category": "camera", "price": "100", "type": "daily",
		"pickup_location": "Library", "pickup_address": "Bangkok", "pickup_note": "Gate 1", "pickup_latitude": "0", "pickup_longitude": "100.5"} {
		if err := form.WriteField(key, value); err != nil {
			t.Fatal(err)
		}
	}
	if err := form.Close(); err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest("POST", "/api/items", &body)
	req.Header.Set("Authorization", "Bearer owner")
	req.Header.Set("Content-Type", form.FormDataContentType())
	res, err := app.Test(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != 201 {
		t.Fatalf("status %d", res.StatusCode)
	}
	item := repo.inserted
	if item == nil || item.PickupLatitude == nil || *item.PickupLatitude != 0 || item.PickupLongitude == nil || *item.PickupLongitude != 100.5 || item.PickupNote != "Gate 1" || item.UserID != "owner" {
		t.Fatalf("unexpected item: %+v", item)
	}
}

func TestItemEditRequiresPickupWithoutBreakingVisibility(t *testing.T) {
	repo := &itemManagementRepository{}
	app := NewHTTPApp()
	defer app.Shutdown()
	app.Put("/api/items/:id", NewItemHandler(repo, itemManagementVerifier{}).UpdateItem)
	for _, test := range []struct {
		body   string
		status int
	}{
		{`{"item_name":"camera"}`, 400},
		{`{"item_name":"camera","pickup_location":"Library","pickup_latitude":13.7,"pickup_longitude":100.5}`, 200},
		{`{"owner_hidden":true}`, 200},
	} {
		req := httptest.NewRequest("PUT", "/api/items/1", strings.NewReader(test.body))
		req.Header.Set("Authorization", "Bearer owner")
		req.Header.Set("Content-Type", "application/json")
		res, err := app.Test(req)
		if err != nil {
			t.Fatal(err)
		}
		res.Body.Close()
		if res.StatusCode != test.status {
			t.Fatalf("%s status %d", test.body, res.StatusCode)
		}
	}
}
