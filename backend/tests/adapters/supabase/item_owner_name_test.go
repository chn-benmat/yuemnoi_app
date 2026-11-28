package supabase_test

import (
	"context"
	"encoding/json"
	supabaseadapter "github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	supabaseclient "github.com/nedpals/supabase-go"
	"net/http"
	"net/http/httptest"
	"strings"
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
				case "/rest/v1/item_tb":
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

func TestItemDetailCarriesDatabaseRates(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/rest/v1/item_tb":
			_, _ = w.Write([]byte(`[{"id":12,"user_id":"owner-12","price":400,"type":"daily","hourly_rate":null,"daily_rate":400}]`))
		case "/rest/v1/public_profile_v":
			_, _ = w.Write([]byte(`[]`))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer server.Close()
	repo := supabaseadapter.NewSupabaseItemRepository(supabaseclient.CreateClient(server.URL, "test-key"), "test-key")
	item, err := repo.FindByID(context.Background(), 12)
	if err != nil {
		t.Fatal(err)
	}
	body, err := json.Marshal(item)
	if err != nil {
		t.Fatal(err)
	}
	var response map[string]any
	if err := json.Unmarshal(body, &response); err != nil {
		t.Fatal(err)
	}
	// แอปต้องแยกได้ว่าไม่มีเรตรายชั่วโมง (null) กับไม่ได้ส่งคอลัมน์มา
	hourly, hasHourly := response["hourly_rate"]
	if !hasHourly || hourly != nil || response["daily_rate"] != float64(400) {
		t.Fatalf("rates in response = hourly %v (%v), daily %v", hourly, hasHourly, response["daily_rate"])
	}
}

func TestItemDetailReadsTheItemTableWithComputedFlags(t *testing.T) {
	var selected []string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/rest/v1/item_tb":
			selected = strings.Split(r.URL.Query().Get("select"), ",")
			_, _ = w.Write([]byte(`[{"id":13,"user_id":"owner-13","daily_rate":300,"account_deletion_hidden":true,"is_rental_occupied":true}]`))
		case "/rest/v1/public_profile_v":
			_, _ = w.Write([]byte(`[]`))
		default:
			t.Errorf("unexpected request: %s", r.URL.Path)
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer server.Close()
	repo := supabaseadapter.NewSupabaseItemRepository(supabaseclient.CreateClient(server.URL, "test-key"), "test-key")
	item, err := repo.FindByID(context.Background(), 13)
	if err != nil {
		t.Fatal(err)
	}
	// ประกาศของบัญชีที่รอลบต้องถูกซ่อนจากหน้ารายละเอียด จึงต้องขอ computed field นี้ทุกครั้ง
	for _, want := range []string{"*", "is_rental_occupied", "is_rental_queue_held", "account_deletion_hidden"} {
		found := false
		for _, column := range selected {
			found = found || column == want
		}
		if !found {
			t.Fatalf("select %v is missing %q", selected, want)
		}
	}
	if !item.AccountDeletionHidden || !item.IsRentalOccupied {
		t.Fatalf("item flags = hidden %v occupied %v", item.AccountDeletionHidden, item.IsRentalOccupied)
	}
}
