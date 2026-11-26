package supabase_test

import (
	"context"
	"encoding/json"
	supabaseadapter "github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	supabaseclient "github.com/nedpals/supabase-go"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestItemDetailUsesOwnerAccountName(t *testing.T) {
	for _, tc := range []struct {
		name, displayName, want string
	}{
		{"display name", "  Alice Camera  ", "Alice Camera"},
		{"empty name", " ", "ผู้ใช้งาน"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				switch r.URL.Path {
				case "/rest/v1/account_deletion_item_v":
					_, _ = w.Write([]byte(`[{"id":11,"user_id":"owner-11","item_name":"Camera"}]`))
				case "/rest/v1/public_profile_v":
					if r.URL.Query().Get("user_id") != "eq.owner-11" {
						t.Error("profile must be scoped to the item's owner")
					}
					_ = json.NewEncoder(w).Encode([]map[string]string{{
						"user_id": "owner-11", "display_name": tc.displayName,
					}})
				default:
					t.Errorf("unexpected request: %s", r.URL.Path)
					w.WriteHeader(http.StatusNotFound)
				}
			}))
			defer server.Close()
			repo := supabaseadapter.NewSupabaseItemRepository(supabaseclient.CreateClient(server.URL, "test-key"), "test-key")
			item, err := repo.FindByID(context.Background(), 11)
			if err != nil {
				t.Fatal(err)
			}
			if item.OwnerName != tc.want {
				t.Errorf("owner name = %q, want %q", item.OwnerName, tc.want)
			}
		})
	}
}
