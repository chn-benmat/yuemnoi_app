package ports_test

import (
	"bytes"
	"context"
	"fmt"
	"mime/multipart"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	ports "github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
)

func TestPickupRequiresExplicitFiniteCoordinates(t *testing.T) {
	for _, test := range []struct {
		name, location, lat, lng string
		status                   int
	}{
		{"equator", "point", "0", "0", 201},
		{"missing", "point", "null", "13.7", 400},
		{"out of range", "point", "13.7", "181", 400},
		{"nan", "point", "NaN", "13.7", 400},
		{"blank location", "  ", "13.7", "13.7", 400},
	} {
		t.Run(test.name, func(t *testing.T) {
			repo := &pickupItemRepository{}
			app := ports.NewHTTPApp()
			defer app.Shutdown()
			app.Post("/items", ports.NewItemHandler(repo, itemManagementVerifier{}).CreateItem)
			body := fmt.Sprintf(`{"item_name":"camera","description":"description","category":"camera","price":100,"type":"daily","pickup_location":%q,"pickup_latitude":%s,"pickup_longitude":%s}`, test.location, test.lat, test.lng)
			req := httptest.NewRequest("POST", "/items", strings.NewReader(body))
			req.Header.Set("Content-Type", "application/json")
			req.Header.Set("Authorization", "Bearer owner")
			response, err := app.Test(req)
			if err != nil {
				t.Fatal(err)
			}
			defer response.Body.Close()
			if response.StatusCode != test.status || (repo.inserted != nil) != (test.status == 201) {
				t.Fatalf("status=%d inserted=%v want=%d", response.StatusCode, repo.inserted, test.status)
			}
		})
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
	app := ports.NewHTTPApp()
	defer app.Shutdown()
	handler := ports.NewItemHandler(repo, itemManagementVerifier{})
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
	app := ports.NewHTTPApp()
	defer app.Shutdown()
	app.Put("/api/items/:id", ports.NewItemHandler(repo, itemManagementVerifier{}).UpdateItem)
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
