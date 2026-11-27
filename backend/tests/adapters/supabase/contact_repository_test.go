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
