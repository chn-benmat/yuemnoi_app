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
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				if r.Method != http.MethodPost {
					t.Errorf("unexpected method %s", r.Method)
					http.Error(w, "use the owner-scoped RPC", http.StatusMethodNotAllowed)
					return
				}
				var body map[string]any
				if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
					t.Errorf("decode request: %v", err)
				}
				if body["p_item_id"] != float64(7) || body["p_actor"] != "actor" {
					t.Errorf("missing item or owner scope: %v", body)
				}
				switch r.URL.Path {
				case "/rest/v1/rpc/get_item_auto_reply":
					if owner {
						_, _ = w.Write([]byte(`[{"enabled":false,"message":""}]`))
					} else {
						_, _ = w.Write([]byte(`[]`))
					}
				case "/rest/v1/rpc/save_item_auto_reply":
					if body["p_enabled"] != false || body["p_message"] != "สวัสดี" {
						t.Errorf("unexpected payload: %v", body)
					}
					if owner {
						_, _ = w.Write([]byte(`[{"enabled":false,"message":"สวัสดี"}]`))
					} else {
						_, _ = w.Write([]byte(`[]`))
					}
				default:
					t.Errorf("unexpected path %s", r.URL.Path)
					http.NotFound(w, r)
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
			saved, err := repo.SaveAutoReply(context.Background(), 7, "actor", domain.ItemAutoReply{Enabled: false, Message: "สวัสดี"})
			if owner && (err != nil || saved.Enabled || saved.Message != "สวัสดี") {
				t.Fatalf("unexpected saved settings: %+v %v", saved, err)
			}
			if !owner && !errors.Is(err, domain.ErrItemNotFound) {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}
