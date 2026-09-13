package tests

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	supabaseadapter "github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	supabaseclient "github.com/nedpals/supabase-go"
)

func TestConversationContactRepositoryReturnsMetadataPhoneForParticipant(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/rest/v1/conversation_tb":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`[{"renter_id":"requester-1","owner_id":"contact-1"}]`))
		case "/auth/v1/admin/users/contact-1":
			if got := r.Header.Get("Authorization"); got != "Bearer service-key" {
				t.Fatalf("unexpected authorization header: %q", got)
			}
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"id":"contact-1","phone":"0899999999","user_metadata":{"phone":"0812345678"}}`))
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	client := supabaseclient.CreateClient(server.URL, "service-key")
	repository := supabaseadapter.NewSupabaseConversationContactRepository(client)

	phone, err := repository.PhoneForConversation(
		context.Background(),
		"requester-1",
		"conversation-1",
	)
	if err != nil {
		t.Fatal(err)
	}
	if phone != "0812345678" {
		t.Fatalf("phone = %q, want metadata phone", phone)
	}
}

func TestConversationContactRepositoryRejectsNonParticipant(t *testing.T) {
	adminCalled := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/rest/v1/conversation_tb":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`[{"renter_id":"renter-1","owner_id":"owner-1"}]`))
		case "/auth/v1/admin/users/renter-1", "/auth/v1/admin/users/owner-1":
			adminCalled = true
			http.Error(w, "must not be called", http.StatusInternalServerError)
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()

	client := supabaseclient.CreateClient(server.URL, "service-key")
	repository := supabaseadapter.NewSupabaseConversationContactRepository(client)

	_, err := repository.PhoneForConversation(
		context.Background(),
		"outsider-1",
		"conversation-1",
	)
	if !errors.Is(err, domain.ErrContactForbidden) {
		t.Fatalf("error = %v, want ErrContactForbidden", err)
	}
	if adminCalled {
		t.Fatal("admin user endpoint was called for a non-participant")
	}
}
