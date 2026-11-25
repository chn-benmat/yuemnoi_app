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
	fields  map[string]interface{}
	actor   string
	deleted bool
	err     error
	hidden  bool
}

func (r *itemManagementRepository) Insert(_ context.Context, item *domain.Item, _ []domain.ItemImage) (*domain.Item, error) {
	return item, nil
}

func TestCreateItemWithHourlyAndDailyPrice(t *testing.T) {
	app := ports.NewHTTPApp()
	defer app.Shutdown()
	app.Post("/api/items", ports.NewItemHandler(&itemManagementRepository{}, itemManagementVerifier{}).CreateItem)
	var body bytes.Buffer
	form := multipart.NewWriter(&body)
	for name, value := range map[string]string{
		"item_name": "Camera", "description": "Includes lens", "category": "Camera",
		"price": "75", "daily_price": "410", "type": "รายชั่วโมง",
		"pickup_location": "Station", "pickup_latitude": "13.75", "pickup_longitude": "100.5",
	} {
		if err := form.WriteField(name, value); err != nil {
			t.Fatal(err)
		}
	}
	if err := form.Close(); err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest("POST", "/api/items", &body)
	req.Header.Set("Content-Type", form.FormDataContentType())
	req.Header.Set("Authorization", "Bearer owner")
	res, err := app.Test(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	var item struct {
		Price      int `json:"price"`
		DailyPrice int `json:"daily_price"`
	}
	if err := json.NewDecoder(res.Body).Decode(&item); err != nil {
		t.Fatal(err)
	}
	if res.StatusCode != 201 || item.Price != 75 || item.DailyPrice != 410 {
		t.Fatalf("status=%d, price=%d, daily_price=%d", res.StatusCode, item.Price, item.DailyPrice)
	}
}

func TestUpdateItemDailyPrice(t *testing.T) {
	for _, tc := range []struct {
		name, pricing string
		want          interface{}
		status        int
	}{
		{"sets daily rate", `"type":"รายชั่วโมง","price":75,"daily_price":410`, 410, 200},
		{"removes daily rate", `"type":"รายชั่วโมง","price":75,"daily_price":0`, nil, 200},
		{"clears additional rate on legacy daily-only edits", `"type":"รายวัน","price":410`, nil, 200},
		{"rejects negative daily rate", `"type":"รายชั่วโมง","price":75,"daily_price":-1`, nil, 400},
		{"requires an hourly rate when adding the daily rate", `"type":"รายชั่วโมง","daily_price":410`, nil, 400},
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
			if tc.status == 200 {
				if price, ok := repo.fields["daily_price"]; !ok || price != tc.want {
					t.Fatalf("fields=%v, want daily_price=%v", repo.fields, tc.want)
				}
			}
		})
	}
}

func (r *itemManagementRepository) FindByID(_ context.Context, id int64) (*domain.Item, error) {
	return &domain.Item{ID: id, UserID: "owner", OwnerHidden: r.hidden}, nil
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
		token  string
		hidden bool
		status int
	}{
		{"", false, 200}, {"", true, 404}, {"invalid", true, 404},
		{"stranger", true, 404}, {"owner", true, 200}, {"renter", true, 200},
	} {
		t.Run(tc.token, func(t *testing.T) {
			app := ports.NewHTTPApp()
			defer app.Shutdown()
			app.Get("/api/items/:id", ports.NewItemHandler(&itemManagementRepository{hidden: tc.hidden}, itemManagementVerifier{}).GetItemByID)
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
