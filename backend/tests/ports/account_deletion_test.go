package ports_test

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	sbadapter "github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	sbclient "github.com/nedpals/supabase-go"
)

type deletionRequests struct {
	domain.AccountDeletionRepository
	due                   time.Time
	scheduleErr           error
	restoreErr            error
	scheduledUser         string
	restoredUser, session string
}

func (r *deletionRequests) Schedule(_ context.Context, userID string) (time.Time, error) {
	r.scheduledUser = userID
	return r.due, r.scheduleErr
}

func (r *deletionRequests) Restore(_ context.Context, userID, session string) error {
	r.restoredUser, r.session = userID, session
	return r.restoreErr
}

func TestAccountDeletionRoutesUseVerifiedUserAndFreshSession(t *testing.T) {
	after := time.Now().UTC().Add(30 * 24 * time.Hour)
	const sessionID = "00000000-0000-4000-8000-000000000003"
	pendingToken := "header." + base64.RawURLEncoding.EncodeToString([]byte(`{"session_id":"`+sessionID+`"}`)) + ".signature"

	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/auth/v1/user" {
			t.Errorf("unexpected Supabase path %s", r.URL.Path)
			http.NotFound(w, r)
			return
		}
		metadata := map[string]any{}
		switch r.Header.Get("Authorization") {
		case "Bearer active":
		case "Bearer " + pendingToken, "Bearer malformed":
			metadata["account_delete_after"] = after
		default:
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"id": userTestID, "app_metadata": metadata})
	}))
	defer upstream.Close()

	for _, tc := range []struct {
		name, path, token, code string
		status                  int
		scheduleErr, restoreErr error
		scheduled, restored     bool
	}{
		{"schedule", "/api/user/account/deletion", "active", "", 200, nil, nil, true, false},
		{"rental blocks schedule", "/api/user/account/deletion", "active", "active_rentals", 409, errors.New("active_rentals"), nil, true, false},
		{"restore with authenticated session", "/api/auth/account/restore", pendingToken, "", 200, nil, nil, false, true},
		{"old sessions are refused", "/api/auth/account/restore", pendingToken, "account_reauth_required", 401, nil, errors.New("account_reauth_required"), false, true},
		{"malformed session cannot restore", "/api/auth/account/restore", "malformed", "account_reauth_required", 401, nil, nil, false, false},
		{"anonymous cannot schedule", "/api/user/account/deletion", "invalid", "", 401, nil, nil, false, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			store := &deletionRequests{due: after, scheduleErr: tc.scheduleErr, restoreErr: tc.restoreErr}
			gateway := sbadapter.NewSupabaseUserRepository(sbclient.CreateClient(upstream.URL, "test-key"), "test-key")
			app := ports.SetupRouterWithOperations(domain.OperationsOptions{AccountDeletion: store}, nil, gateway, nil, nil, nil, "test-secret")
			defer app.Shutdown()
			req := httptest.NewRequest(http.MethodPost, tc.path, strings.NewReader(`{"user_id":"someone-else"}`))
			req.Header.Set("Content-Type", "application/json")
			req.Header.Set("Authorization", "Bearer "+tc.token)
			req.Header.Set("X-App-Secret", "test-secret")
			response, err := app.Test(req)
			if err != nil {
				t.Fatal(err)
			}
			defer response.Body.Close()
			var result map[string]any
			if err = json.NewDecoder(response.Body).Decode(&result); err != nil {
				t.Fatal(err)
			}
			if response.StatusCode != tc.status {
				t.Fatalf("status=%d, payload=%v, want %d", response.StatusCode, result, tc.status)
			}
			if tc.code != "" && result["code"] != tc.code {
				t.Fatalf("code=%v, want %s", result["code"], tc.code)
			}
			if tc.scheduled && store.scheduledUser != userTestID || !tc.scheduled && store.scheduledUser != "" {
				t.Fatalf("scheduled user=%q", store.scheduledUser)
			}
			if tc.restored && (store.restoredUser != userTestID || store.session != sessionID) || !tc.restored && store.restoredUser != "" {
				t.Fatalf("restored user=%q session=%q", store.restoredUser, store.session)
			}
			if tc.scheduled && tc.status == 200 {
				got, err := time.Parse(time.RFC3339Nano, result["delete_after"].(string))
				if err != nil || !got.Equal(after) {
					t.Fatalf("delete_after=%v, want %v", result["delete_after"], after)
				}
			}
		})
	}
}
