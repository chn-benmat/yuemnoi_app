package tests

import (
	"bytes"
	"context"
	"encoding/json"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	"github.com/gin-gonic/gin"
)

type itemHandlerRepository struct {
	item        *domain.Item
	images      []domain.ItemImage
	rankedItems []domain.RankedItem
}

func (r *itemHandlerRepository) Insert(_ context.Context, item *domain.Item, images []domain.ItemImage) (*domain.Item, error) {
	item.ID = 42
	item.ItemImageURL = []string{"https://example.test/item_bk/42/image.png"}
	r.item = item
	r.images = images
	return item, nil
}
func (r *itemHandlerRepository) FindAll(context.Context) ([]domain.RankedItem, error) {
	return r.rankedItems, nil
}
func (*itemHandlerRepository) FindByID(context.Context, int64) (*domain.Item, error) {
	return nil, domain.ErrItemNotFound
}
func (*itemHandlerRepository) Update(context.Context, int64, string, map[string]interface{}) (*domain.Item, error) {
	return nil, domain.ErrItemNotFound
}
func (*itemHandlerRepository) Delete(context.Context, int64, string) error { return nil }

type itemTokenVerifier struct{}

func (itemTokenVerifier) UserIDFromToken(context.Context, string) (string, error) {
	return "6df692ac-40b7-4f6d-9ca1-081cf31888c9", nil
}

func TestCreateItemAcceptsMultipartImages(t *testing.T) {
	gin.SetMode(gin.TestMode)
	repository := &itemHandlerRepository{}
	handler := ports.NewItemHandler(repository, itemTokenVerifier{})
	router := gin.New()
	router.POST("/api/v1/items", handler.CreateItem)

	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	fields := map[string]string{
		"item_name":   "กล้องถ่ายรูป",
		"category":    "กล้อง",
		"description": "กล้องสำหรับงานอีเวนต์",
		"price":       "850",
		"type":        "รายวัน",
	}
	for name, value := range fields {
		if err := writer.WriteField(name, value); err != nil {
			t.Fatal(err)
		}
	}
	file, err := writer.CreateFormFile("images", "camera.png")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := file.Write([]byte("\x89PNG\r\n\x1a\nvalid-test-image")); err != nil {
		t.Fatal(err)
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}

	request := httptest.NewRequest(http.MethodPost, "/api/v1/items", body)
	request.Header.Set("Content-Type", writer.FormDataContentType())
	request.Header.Set("Authorization", "Bearer valid-token")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	if response.Code != http.StatusCreated {
		t.Fatalf("expected status 201, got %d: %s", response.Code, response.Body.String())
	}
	if repository.item == nil || repository.item.Status != "pending" {
		t.Fatalf("expected pending item, got %#v", repository.item)
	}
	if repository.item.Type != "รายวัน" {
		t.Fatalf("expected daily rental type, got %q", repository.item.Type)
	}
	if len(repository.images) != 1 || repository.images[0].ContentType != "image/png" {
		t.Fatalf("expected one PNG image, got %#v", repository.images)
	}
}

func TestGetAllItemsPreservesRankedOrderAndMetrics(t *testing.T) {
	gin.SetMode(gin.TestMode)
	repository := &itemHandlerRepository{
		rankedItems: []domain.RankedItem{
			{
				Item:             domain.Item{ID: 29, ItemName: "กล้องยอดนิยม"},
				Rating:           4.8,
				ReviewCount:      12,
				PaidBookingCount: 7,
			},
			{
				Item:             domain.Item{ID: 8, ItemName: "กล้องใหม่"},
				Rating:           0,
				ReviewCount:      0,
				PaidBookingCount: 0,
			},
		},
	}
	handler := ports.NewItemHandler(repository, itemTokenVerifier{})
	router := gin.New()
	router.GET("/api/v1/items", handler.GetAllItems)

	request := httptest.NewRequest(http.MethodGet, "/api/v1/items", nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

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
