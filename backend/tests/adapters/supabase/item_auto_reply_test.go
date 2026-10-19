package supabase_test

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	supabase "github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	supabaseclient "github.com/nedpals/supabase-go"
)

func TestAutoReplyStorageIsOwnerScopedAndKeepsExplicitFalse(t *testing.T) {
	for _, owner := range []bool{true, false} {
		t.Run(map[bool]string{true: "owner", false: "stranger"}[owner], func(t *testing.T) {
			settingsCalls := 0
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				if r.URL.Path == "/rest/v1/item_tb" {
					if r.URL.Query().Get("id") != "eq.7" || r.URL.Query().Get("user_id") != "eq.actor" {
						t.Error("missing ownership scope")
					}
					if owner {
						_, _ = w.Write([]byte(`[{"id":7}]`))
					} else {
						_, _ = w.Write([]byte(`[]`))
					}
					return
				}
				settingsCalls++
				if r.URL.Path != "/rest/v1/item_auto_reply_tb" {
					t.Errorf("unexpected path %s", r.URL.Path)
				}
				if r.Method == "POST" {
					var body map[string]interface{}
					_ = json.NewDecoder(r.Body).Decode(&body)
					if body["item_id"] != float64(7) || body["enabled"] != false || body["message"] != "สวัสดี" {
						t.Errorf("unexpected payload: %v", body)
					}
					_, _ = w.Write([]byte(`[{"enabled":false,"message":"สวัสดี"}]`))
				} else {
					if r.URL.Query().Get("item_id") != "eq.7" {
						t.Error("missing item scope")
					}
					_, _ = w.Write([]byte(`[]`))
				}
			}))
			defer server.Close()
			repo := supabase.NewSupabaseItemRepository(supabaseclient.CreateClient(server.URL, "key"), "key")
			loaded, err := repo.GetAutoReply(context.Background(), 7, "actor")
			if owner && (err != nil || loaded.Enabled || loaded.Message != "") {
				t.Fatalf("unexpected defaults: %+v %v", loaded, err)
			}
			if !owner && !errors.Is(err, domain.ErrItemNotFound) {
				t.Fatalf("unexpected error: %v", err)
			}
			_, err = repo.SaveAutoReply(context.Background(), 7, "actor", domain.ItemAutoReply{Enabled: false, Message: "สวัสดี"})
			if owner && err != nil {
				t.Fatal(err)
			}
			if !owner && (!errors.Is(err, domain.ErrItemNotFound) || settingsCalls != 0) {
				t.Fatal("unowned settings accessed")
			}
		})
	}
}
