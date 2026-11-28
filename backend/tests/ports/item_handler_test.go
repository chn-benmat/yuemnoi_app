package ports_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"mime/multipart"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	ports "github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
)

type itemManagementVerifier struct{}

func (itemManagementVerifier) UserIDFromToken(_ context.Context, token string) (string, error) {
	if token == "invalid" {
		return "", errors.New("invalid token")
	}
	return token, nil
}

type itemManagementRepository struct {
	domain.ItemRepository
	fields         map[string]interface{}
	actor          string
	deleted        bool
	err            error
	hidden         bool
	deletionHidden bool
}

func (r *itemManagementRepository) Insert(_ context.Context, item *domain.Item, _ []domain.ItemImage) (*domain.Item, error) {
	return item, nil
}

func createItemForm(t *testing.T, pricing map[string]string) (*bytes.Buffer, string) {
	t.Helper()
	var body bytes.Buffer
	form := multipart.NewWriter(&body)
	fields := map[string]string{
		"item_name": "Camera", "description": "Includes lens", "category": "Camera",
		"pickup_location": "Station", "pickup_latitude": "13.75", "pickup_longitude": "100.5",
	}
	for name, value := range pricing {
		fields[name] = value
	}
	for name, value := range fields {
		if err := form.WriteField(name, value); err != nil {
			t.Fatal(err)
		}
	}
	if err := form.Close(); err != nil {
		t.Fatal(err)
	}
	return &body, form.FormDataContentType()
}

func TestCreateItemStoresPerUnitRates(t *testing.T) {
	for _, tc := range []struct {
		name          string
		pricing       map[string]string
		status        int
		hourly, daily *int
	}{
		{"both rates", map[string]string{"hourly_rate": "75", "daily_rate": "410"}, 201, intPtr(75), intPtr(410)},
		{"daily only", map[string]string{"daily_rate": "410"}, 201, nil, intPtr(410)},
		{"legacy hourly app", map[string]string{"price": "75", "daily_price": "410", "type": "รายชั่วโมง"}, 201, intPtr(75), intPtr(410)},
		{"legacy daily app", map[string]string{"price": "410", "type": "daily"}, 201, nil, intPtr(410)},
		{"no rate", map[string]string{}, 400, nil, nil},
		{"zero rate", map[string]string{"hourly_rate": "0"}, 400, nil, nil},
	} {
		t.Run(tc.name, func(t *testing.T) {
			app := ports.NewHTTPApp()
			defer app.Shutdown()
			app.Post("/api/items", ports.NewItemHandler(&itemManagementRepository{}, itemManagementVerifier{}).CreateItem)
			body, contentType := createItemForm(t, tc.pricing)
			req := httptest.NewRequest("POST", "/api/items", body)
			req.Header.Set("Content-Type", contentType)
			req.Header.Set("Authorization", "Bearer owner")
			res, err := app.Test(req)
			if err != nil {
				t.Fatal(err)
			}
			defer res.Body.Close()
			if res.StatusCode != tc.status {
				t.Fatalf("status=%d want %d", res.StatusCode, tc.status)
			}
			if tc.status != 201 {
				return
			}
			var item map[string]any
			if err := json.NewDecoder(res.Body).Decode(&item); err != nil {
				t.Fatal(err)
			}
			for key := range map[string]bool{"price": true, "type": true, "daily_price": true} {
				if _, ok := item[key]; ok {
					t.Fatalf("response still carries legacy %s: %v", key, item)
				}
			}
			if !sameRate(item["hourly_rate"], tc.hourly) || !sameRate(item["daily_rate"], tc.daily) {
				t.Fatalf("rates = %v / %v", item["hourly_rate"], item["daily_rate"])
			}
		})
	}
}

func intPtr(value int) *int { return &value }

func sameRate(got any, want *int) bool {
	if want == nil {
		return got == nil
	}
	return got == float64(*want)
}

func TestUpdateItemRates(t *testing.T) {
	for _, tc := range []struct {
		name, pricing string
		status        int
		want          map[string]interface{}
	}{
		{"sets both rates", `"hourly_rate":75,"daily_rate":410`, 200, map[string]interface{}{"hourly_rate": 75, "daily_rate": 410}},
		{"removes the daily rate", `"hourly_rate":75,"daily_rate":0`, 200, map[string]interface{}{"hourly_rate": 75, "daily_rate": nil}},
		{"changes only the daily rate", `"daily_rate":420`, 200, map[string]interface{}{"daily_rate": 420}},
		{"legacy hourly edit", `"type":"รายชั่วโมง","price":75,"daily_price":410`, 200, map[string]interface{}{"hourly_rate": 75, "daily_rate": 410}},
		{"legacy removes daily rate", `"type":"รายชั่วโมง","price":75,"daily_price":0`, 200, map[string]interface{}{"hourly_rate": 75, "daily_rate": nil}},
		{"legacy daily-only edit", `"type":"รายวัน","price":410`, 200, map[string]interface{}{"hourly_rate": nil, "daily_rate": 410}},
		{"rejects removing every rate", `"hourly_rate":0,"daily_rate":0`, 400, nil},
		{"rejects a negative rate", `"hourly_rate":-1`, 400, nil},
		{"rejects a legacy daily rate without the hourly rate", `"type":"รายชั่วโมง","daily_price":410`, 400, nil},
	} {
		t.Run(tc.name, func(t *testing.T) {
			repo := &itemManagementRepository{}
			app := ports.NewHTTPApp()
			defer app.Shutdown()
			app.Put("/api/items/:id", ports.NewItemHandler(repo, itemManagementVerifier{}).UpdateItem)
			req := httptest.NewRequest("PUT", "/api/items/7", strings.NewReader(`{`+tc.pricing+`,"pickup_location":"Station","pickup_latitude":13.75,"pickup_longitude":100.5}`))
			req.Header.Set("Content-Type", "application/json")
			req.Header.Set("Authorization", "Bearer owner")
			res, err := app.Test(req)
			if err != nil {
				t.Fatal(err)
			}
			defer res.Body.Close()
			if res.StatusCode != tc.status {
				t.Fatalf("status=%d want %d", res.StatusCode, tc.status)
			}
			if tc.status != 200 {
				return
			}
			for _, legacy := range []string{"price", "type", "daily_price"} {
				if _, ok := repo.fields[legacy]; ok {
					t.Fatalf("update still writes %s: %v", legacy, repo.fields)
				}
			}
			for key, want := range tc.want {
				got, ok := repo.fields[key]
				if !ok {
					t.Fatalf("fields=%v, missing %s", repo.fields, key)
				}
				if want == nil {
					if got != nil {
						t.Fatalf("%s=%v want nil", key, got)
					}
				} else if got != want {
					t.Fatalf("%s=%v want %v", key, got, want)
				}
			}
			if _, ok := repo.fields["hourly_rate"]; ok != (tc.want["hourly_rate"] != nil || hasKey(tc.want, "hourly_rate")) {
				t.Fatalf("unexpected hourly_rate write: %v", repo.fields)
			}
		})
	}
}

func hasKey(values map[string]interface{}, key string) bool {
	_, ok := values[key]
	return ok
}

func (r *itemManagementRepository) FindByID(_ context.Context, id int64) (*domain.Item, error) {
	return &domain.Item{ID: id, UserID: "owner", OwnerHidden: r.hidden, AccountDeletionHidden: r.deletionHidden}, nil
}
func (r *itemManagementRepository) HasRentalAccess(_ context.Context, _ int64, actor string) (bool, error) {
	return actor == "renter", nil
}
func (r *itemManagementRepository) Update(_ context.Context, id int64, actor string, fields map[string]interface{}) (*domain.Item, error) {
	r.actor = actor
	r.fields = fields
	if actor != "owner" {
		return nil, domain.ErrItemNotFound
	}
	return &domain.Item{ID: id, OwnerHidden: fields["owner_hidden"] == true}, r.err
}
func (r *itemManagementRepository) Delete(_ context.Context, _ int64, actor string) error {
	r.actor = actor
	if actor != "owner" {
		return domain.ErrItemNotFound
	}
	if r.err != nil {
		return r.err
	}
	r.deleted = true
	return nil
}

func TestOwnerItemManagement(t *testing.T) {
	for _, tc := range []struct {
		name, method, body, token string
		err                       error
		status                    int
	}{
		{"hide", "PUT", `{"owner_hidden":true}`, "owner", nil, 200},
		{"unhide false survives partial update", "PUT", `{"owner_hidden":false}`, "owner", nil, 200},
		{"hide requires auth", "PUT", `{"owner_hidden":true}`, "", nil, 401},
		{"cannot change someone else's listing", "PUT", `{"owner_hidden":true}`, "stranger", nil, 404},
		{"delete", "DELETE", "", "owner", nil, 204},
		{"delete requires auth", "DELETE", "", "", nil, 401},
		{"cannot delete another listing", "DELETE", "", "stranger", nil, 404},
		{"referenced listing cannot be deleted", "DELETE", "", "owner", domain.ErrItemInUse, 409},
	} {
		t.Run(tc.name, func(t *testing.T) {
			repo := &itemManagementRepository{err: tc.err}
			app := ports.NewHTTPApp()
			defer app.Shutdown()
			handler := ports.NewItemHandler(repo, itemManagementVerifier{})
			app.Put("/api/items/:id", handler.UpdateItem)
			app.Delete("/api/items/:id", handler.DeleteItem)
			req := httptest.NewRequest(tc.method, "/api/items/7", strings.NewReader(tc.body))
			req.Header.Set("Content-Type", "application/json")
			if tc.token != "" {
				req.Header.Set("Authorization", "Bearer "+tc.token)
			}
			res, err := app.Test(req)
			if err != nil {
				t.Fatal(err)
			}
			defer res.Body.Close()
			if res.StatusCode != tc.status {
				t.Fatalf("status=%d want %d", res.StatusCode, tc.status)
			}
			if tc.status == 200 {
				value, exists := repo.fields["owner_hidden"]
				if !exists || value != (tc.body == `{"owner_hidden":true}`) || repo.actor != "owner" {
					t.Fatalf("unexpected fields/actor: %v %s", repo.fields, repo.actor)
				}
				if _, exists := repo.fields["status"]; exists {
					t.Fatal("visibility changed rental status")
				}
			}
			if repo.deleted != (tc.method == "DELETE" && tc.status == 204) {
				t.Fatal("unexpected deletion")
			}
		})
	}
}

func TestHiddenItemReadAccess(t *testing.T) {
	for _, tc := range []struct {
		token          string
		hidden         bool
		deletionHidden bool
		status         int
	}{
		{"", false, false, 200}, {"", true, false, 404}, {"invalid", true, false, 404},
		{"stranger", true, false, 404}, {"owner", true, false, 200}, {"renter", true, false, 200},
		{"", false, true, 404}, {"renter", false, true, 404},
	} {
		t.Run(tc.token, func(t *testing.T) {
			app := ports.NewHTTPApp()
			defer app.Shutdown()
			repo := &itemManagementRepository{hidden: tc.hidden, deletionHidden: tc.deletionHidden}
			app.Get("/api/items/:id", ports.NewItemHandler(repo, itemManagementVerifier{}).GetItemByID)
			req := httptest.NewRequest("GET", "/api/items/7", nil)
			if tc.token != "" {
				req.Header.Set("Authorization", "Bearer "+tc.token)
			}
			res, err := app.Test(req)
			if err != nil {
				t.Fatal(err)
			}
			defer res.Body.Close()
			if res.StatusCode != tc.status {
				t.Fatalf("status=%d want %d", res.StatusCode, tc.status)
			}
		})
	}
}
