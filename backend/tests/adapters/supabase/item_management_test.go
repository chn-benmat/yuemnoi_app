package supabase_test

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	supabase "github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	supabaseclient "github.com/nedpals/supabase-go"
)

func TestItemDeleteKeepsImagesWhenReferencesPreventDeletion(t *testing.T) {
	for _, blocked := range []bool{false, true} {
		t.Run(map[bool]string{false: "deletes row then images", true: "keeps referenced row and images"}[blocked], func(t *testing.T) {
			rowDeleted, imagesDeleted := false, false
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				switch r.URL.Path {
				case "/rest/v1/item_tb":
					if r.URL.Query().Get("id") != "eq.7" || r.URL.Query().Get("user_id") != "eq.owner" {
						t.Error("missing owner/id constraint")
					}
					if r.Method == http.MethodGet {
						_, _ = w.Write([]byte(`[{"id":7,"user_id":"owner","item_image_url":["https://test.invalid/storage/v1/object/public/item_bk/owner/7/image.jpg"]}]`))
					} else if r.Method == http.MethodDelete {
						if blocked {
							w.WriteHeader(409)
							_, _ = w.Write([]byte(`{"code":"23503","message":"foreign key violation"}`))
							return
						}
						rowDeleted = true
						_, _ = w.Write([]byte(`[]`))
					} else {
						t.Errorf("unexpected method %s", r.Method)
					}
				case "/storage/v1/object/item_bk":
					if !rowDeleted {
						t.Error("images deleted before row")
					}
					imagesDeleted = true
					_, _ = w.Write([]byte(`[]`))
				default:
					t.Errorf("unexpected path %s", r.URL.Path)
					w.WriteHeader(404)
				}
			}))
			defer server.Close()
			repo := supabase.NewSupabaseItemRepository(supabaseclient.CreateClient(server.URL, "test-key"), "test-key")
			err := repo.Delete(context.Background(), 7, "owner")
			if blocked && !errors.Is(err, domain.ErrItemInUse) {
				t.Fatalf("error=%v", err)
			}
			if !blocked && err != nil {
				t.Fatal(err)
			}
			if rowDeleted == blocked || imagesDeleted == blocked {
				t.Fatalf("row=%v images=%v blocked=%v", rowDeleted, imagesDeleted, blocked)
			}
		})
	}
}

func TestHiddenItemRentalAccessUsesBothActorAndItem(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/rest/v1/booking_tb" || r.URL.Query().Get("item_id") != "eq.7" || r.URL.Query().Get("user_id") != "eq.renter" {
			t.Error("incorrect rental access query")
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`[{"id":9}]`))
	}))
	defer server.Close()
	repo := supabase.NewSupabaseItemRepository(supabaseclient.CreateClient(server.URL, "test-key"), "test-key")
	allowed, err := repo.HasRentalAccess(context.Background(), 7, "renter")
	if err != nil || !allowed {
		t.Fatalf("allowed=%v error=%v", allowed, err)
	}
}
