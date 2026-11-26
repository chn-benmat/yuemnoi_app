package ports_test

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	sbadapter "github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	ports "github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	sbclient "github.com/nedpals/supabase-go"
)

const adminTestID = "00000000-0000-4000-8000-000000000001"
const userTestID = "00000000-0000-4000-8000-000000000002"

type accessTestStore struct{}

func (accessTestStore) RPC(_ context.Context, name string, args map[string]any) (json.RawMessage, error) {
	if name != "admin_read" || args["p_module"] != "me" {
		return nil, errors.New("unexpected_rpc")
	}
	if args["p_actor"] != adminTestID {
		return nil, errors.New("staff_required")
	}
	return json.RawMessage(`{"user_id":"` + adminTestID + `","role":"staff"}`), nil
}
func (accessTestStore) UploadEvidence(context.Context, string, []byte, string) error { return nil }
func (accessTestStore) ReadEvidence(context.Context, string) ([]byte, string, error) {
	return nil, "", nil
}
func (accessTestStore) DeleteEvidence(context.Context, string) error { return nil }

func TestDashboardOnlyAccessAcrossApplicationAndDashboard(t *testing.T) {
	deleteAfter := time.Now().UTC().Add(30 * 24 * time.Hour)
	authServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/auth/v1/token", "/auth/v1/verify":
			var body struct{ Email string }
			if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
				t.Errorf("decode credentials: %v", err)
			}
			token := "user-token"
			if strings.EqualFold(body.Email, "admin@example.invalid") {
				token = "admin-token"
			}
			if strings.EqualFold(body.Email, "pending@example.invalid") {
				token = "pending-token"
			}
			_ = json.NewEncoder(w).Encode(map[string]string{"access_token": token, "refresh_token": "refresh-token"})
		case "/auth/v1/user":
			switch r.Header.Get("Authorization") {
			case "Bearer admin-token":
				_, _ = w.Write([]byte(`{"id":"` + adminTestID + `","app_metadata":{"dashboard_only":true}}`))
			case "Bearer user-token":
				_, _ = w.Write([]byte(`{"id":"` + userTestID + `","app_metadata":{},"user_metadata":{"dashboard_only":true}}`))
			case "Bearer pending-token":
				_ = json.NewEncoder(w).Encode(map[string]any{"id": userTestID, "app_metadata": map[string]any{"account_delete_after": deleteAfter}})
			case "Bearer expired-deletion-token":
				_ = json.NewEncoder(w).Encode(map[string]any{"id": userTestID, "app_metadata": map[string]any{"account_delete_after": deleteAfter.Add(-31 * 24 * time.Hour)}})
			default:
				w.WriteHeader(http.StatusUnauthorized)
			}
		default:
			t.Errorf("unexpected Auth request: %s %s", r.Method, r.URL.Path)
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer authServer.Close()

	tests := []struct {
		name, method, path, body, token string
		status                          int
		wantCode                        string
		wantTokens                      bool
	}{
		{"admin password in app", "POST", "/api/auth/login", `{"email":"admin@example.invalid","password":"password123"}`, "", 403, "dashboard_only", false},
		{"admin OTP in app", "POST", "/api/auth/verify-otp", `{"email":"admin@example.invalid","otp_code":"123456"}`, "", 403, "dashboard_only", false},
		{"admin existing or OAuth session", "GET", "/api/auth/session", "", "admin-token", 403, "dashboard_only", false},
		{"admin existing token profile", "GET", "/api/user/profile", "", "admin-token", 403, "dashboard_only", false},
		{"admin Google profile sync", "POST", "/api/auth/google-profile", "", "admin-token", 403, "dashboard_only", false},
		{"admin app password update", "POST", "/api/auth/change-password", `{"new_password":"new-password123"}`, "admin-token", 403, "dashboard_only", false},
		{"admin identity endpoint", "GET", "/api/identity/status", "", "admin-token", 403, "dashboard_only", false},
		{"admin dashboard login", "POST", "/api/admin/login", `{"email":"admin@example.invalid","password":"password123"}`, "", 200, "", true},
		{"admin dashboard session", "GET", "/api/admin/me", "", "admin-token", 200, "", false},
		{"regular account dashboard login", "POST", "/api/admin/login", `{"email":"user@example.invalid","password":"password123"}`, "", 403, "staff_required", false},
		{"regular app login ignores user metadata", "POST", "/api/auth/login", `{"email":"user@example.invalid","password":"password123"}`, "", 200, "", true},
		{"regular app session", "GET", "/api/auth/session", "", "user-token", 200, "", false},
		{"pending password authenticates for recovery", "POST", "/api/auth/login", `{"email":"pending@example.invalid","password":"password123"}`, "", 200, "", true},
		{"pending app session requests explicit restore", "GET", "/api/auth/session", "", "pending-token", 409, "account_deletion_pending", false},
		{"pending account cannot use private API", "GET", "/api/user/profile", "", "pending-token", 409, "account_deletion_pending", false},
		{"expired account cannot restore through session", "GET", "/api/auth/session", "", "expired-deletion-token", 410, "account_deletion_expired", false},
		{"invalid session", "GET", "/api/auth/session", "", "invalid-token", 401, "", false},
		{"missing session", "GET", "/api/auth/session", "", "", 401, "", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gateway := sbadapter.NewSupabaseUserRepository(sbclient.CreateClient(authServer.URL, "test-key"), "test-key")
			app := ports.SetupRouterWithOperations(domain.OperationsOptions{Store: accessTestStore{}}, nil, gateway, nil, nil, nil, "test-secret")
			defer app.Shutdown()
			request := httptest.NewRequest(tt.method, tt.path, strings.NewReader(tt.body))
			request.Header.Set("Content-Type", "application/json")
			request.Header.Set("X-App-Secret", "test-secret")
			if tt.token != "" {
				request.Header.Set("Authorization", "Bearer "+tt.token)
			}
			response, err := app.Test(request)
			if err != nil {
				t.Fatal(err)
			}
			defer response.Body.Close()
			body, err := io.ReadAll(response.Body)
			if err != nil {
				t.Fatal(err)
			}
			if response.StatusCode != tt.status {
				t.Fatalf("status = %d, want %d; body = %s", response.StatusCode, tt.status, body)
			}
			var result map[string]any
			if err := json.Unmarshal(body, &result); err != nil {
				t.Fatal(err)
			}
			if tt.wantCode != "" && result["code"] != tt.wantCode {
				t.Errorf("code = %v, want %q", result["code"], tt.wantCode)
			}
			if tt.wantCode == "account_deletion_pending" {
				raw, _ := result["delete_after"].(string)
				got, err := time.Parse(time.RFC3339Nano, raw)
				if err != nil || !got.Equal(deleteAfter) {
					t.Errorf("delete_after = %v, want %v", result["delete_after"], deleteAfter)
				}
			}
			_, hasTokens := result["access_token"]
			if hasTokens != tt.wantTokens {
				t.Errorf("token exposure = %t, want %t", hasTokens, tt.wantTokens)
			}
		})
	}
}
