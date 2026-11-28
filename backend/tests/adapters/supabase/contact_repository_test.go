package supabase_test

import (
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	supabase "github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	supabaseclient "github.com/nedpals/supabase-go"
)

func TestPhoneForConversationWithDeletedParticipant(t *testing.T) {
	for _, tc := range []struct {
		name string
		room string
	}{
		{name: "deleted owner", room: `[{"renter_id":"viewer","owner_id":null}]`},
		{name: "deleted renter", room: `[{"renter_id":null,"owner_id":"viewer"}]`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path != "/rest/v1/conversation_tb" {
					t.Errorf("unexpected request: %s", r.URL.Path)
					http.NotFound(w, r)
					return
				}
				w.Header().Set("Content-Type", "application/json")
				fmt.Fprint(w, tc.room)
			}))
			defer server.Close()

			repository := supabase.NewSupabaseConversationContactRepository(supabaseclient.CreateClient(server.URL, "test-key"))
			phone, err := repository.PhoneForConversation(t.Context(), "viewer", "room")
			if phone != "" || !errors.Is(err, domain.ErrContactPhoneNotFound) {
				t.Fatalf("expected missing contact phone, got phone=%q err=%v", phone, err)
			}
		})
	}
}

func TestPhoneForConversationReadsProfilePhone(t *testing.T) {
	for _, tc := range []struct {
		name, profile, want string
		missing             bool
	}{
		{name: "profile phone wins over Auth metadata", profile: `[{"phone":"0812345678"}]`, want: "0812345678"},
		{name: "no profile phone despite Auth metadata", profile: `[{"phone":null}]`, missing: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				switch r.URL.Path {
				case "/rest/v1/conversation_tb":
					fmt.Fprint(w, `[{"renter_id":"viewer","owner_id":"owner"}]`)
				case "/rest/v1/profile_tb":
					if r.URL.Query().Get("user_id") != "eq.owner" {
						t.Errorf("profile lookup must target the other participant: %s", r.URL.RawQuery)
					}
					fmt.Fprint(w, tc.profile)
				case "/auth/v1/admin/users/owner":
					fmt.Fprint(w, `{"id":"owner","phone":"66899999999","user_metadata":{"phone":"0899999999"},"app_metadata":{}}`)
				default:
					t.Errorf("unexpected request: %s", r.URL.Path)
					http.NotFound(w, r)
				}
			}))
			defer server.Close()

			repository := supabase.NewSupabaseConversationContactRepository(supabaseclient.CreateClient(server.URL, "test-key"))
			phone, err := repository.PhoneForConversation(t.Context(), "viewer", "room")
			if tc.missing {
				if phone != "" || !errors.Is(err, domain.ErrContactPhoneNotFound) {
					t.Fatalf("expected missing phone, got %q err=%v", phone, err)
				}
				return
			}
			if err != nil || phone != tc.want {
				t.Fatalf("phone=%q err=%v, want %q", phone, err, tc.want)
			}
		})
	}
}
