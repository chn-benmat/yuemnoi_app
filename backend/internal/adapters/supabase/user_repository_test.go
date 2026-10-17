package supabase

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	supabaseclient "github.com/nedpals/supabase-go"
)

func TestAppTokenAccessUsesCurrentTrustedMetadata(t *testing.T) {
	dashboardOnly := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/auth/v1/user" || r.Header.Get("Authorization") != "Bearer existing-token" || r.Header.Get("apikey") != "test-key" {
			t.Errorf("unexpected identity request")
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"id":            "existing-user",
			"app_metadata":  map[string]any{"dashboard_only": dashboardOnly},
			"user_metadata": map[string]any{"dashboard_only": true},
		})
	}))
	defer server.Close()
	repository := NewSupabaseUserRepository(supabaseclient.CreateClient(server.URL, "test-key"), "test-key")
	if _, err := repository.AppUserIDFromToken(context.Background(), "existing-token"); err != nil {
		t.Fatalf("regular user with editable metadata was blocked: %v", err)
	}
	dashboardOnly = true
	if _, err := repository.AppUserIDFromToken(context.Background(), "existing-token"); err != domain.ErrDashboardOnly {
		t.Fatalf("existing app token error = %v, want dashboard_only", err)
	}
	if id, err := repository.UserIDFromToken(context.Background(), "existing-token"); err != nil || id != "existing-user" {
		t.Fatalf("dashboard identity changed: id=%q err=%v", id, err)
	}
}

func TestChangePasswordSendsAuthenticatedUpdateRequest(t *testing.T) {
	var requestBody struct {
		Password string `json:"password"`
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/auth/v1/user" {
			t.Errorf("request path = %q, want %q", r.URL.Path, "/auth/v1/user")
		}
		if r.Method != http.MethodPut {
			t.Errorf("request method = %q, want %q", r.Method, http.MethodPut)
		}
		if got := r.Header.Get("apikey"); got != "test-key" {
			t.Errorf("apikey header = %q, want %q", got, "test-key")
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-access-token" {
			t.Errorf("Authorization header = %q, want %q", got, "Bearer test-access-token")
		}
		if err := json.NewDecoder(r.Body).Decode(&requestBody); err != nil {
			t.Errorf("decode request body: %v", err)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"id":"test-user"}`))
	}))
	defer server.Close()

	client := supabaseclient.CreateClient(server.URL, "test-key")
	repository := NewSupabaseUserRepository(client, "test-key")

	if err := repository.ChangePassword(context.Background(), "test-access-token", "new-password"); err != nil {
		t.Fatalf("ChangePassword() error = %v", err)
	}
	if requestBody.Password != "new-password" {
		t.Errorf("password = %q, want %q", requestBody.Password, "new-password")
	}
}

func TestChangePasswordIncludesCurrentSupabaseErrorMessage(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusForbidden)
		_, _ = w.Write([]byte(`{"code":403,"error_code":"bad_jwt","msg":"invalid JWT"}`))
	}))
	defer server.Close()

	client := supabaseclient.CreateClient(server.URL, "test-key")
	repository := NewSupabaseUserRepository(client, "test-key")

	err := repository.ChangePassword(context.Background(), "invalid-token", "new-password")
	if err == nil {
		t.Fatal("ChangePassword() error = nil, want Supabase Auth error")
	}
	if got := err.Error(); !strings.Contains(got, "bad_jwt: invalid JWT") {
		t.Errorf("ChangePassword() error = %q, want decoded error_code and msg", got)
	}
}

func TestSyncGoogleProfileImageUpdatesProfileFromAvatarMetadata(t *testing.T) {
	const avatarURL = "https://lh3.googleusercontent.com/a/google-avatar"
	var updatedImageURL string

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/auth/v1/user":
			if got := r.Header.Get("Authorization"); got != "Bearer google-access-token" {
				t.Errorf("Authorization header = %q, want bearer token", got)
			}
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"id":"google-user","user_metadata":{"avatar_url":"` + avatarURL + `"}}`))
		case "/rest/v1/profile_tb":
			if r.Method != http.MethodPatch {
				t.Errorf("request method = %q, want %q", r.Method, http.MethodPatch)
			}
			if got := r.URL.Query().Get("user_id"); got != "eq.google-user" {
				t.Errorf("user_id filter = %q, want %q", got, "eq.google-user")
			}
			var requestBody struct {
				UserImageURL string `json:"user_image_url"`
			}
			if err := json.NewDecoder(r.Body).Decode(&requestBody); err != nil {
				t.Errorf("decode request body: %v", err)
			}
			updatedImageURL = requestBody.UserImageURL
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`[{"user_id":"google-user"}]`))
		default:
			t.Errorf("unexpected request path %q", r.URL.Path)
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer server.Close()

	client := supabaseclient.CreateClient(server.URL, "test-key")
	repository := NewSupabaseUserRepository(client, "test-key")

	imageURL, err := repository.SyncGoogleProfileImage(
		context.Background(),
		"google-access-token",
	)
	if err != nil {
		t.Fatalf("SyncGoogleProfileImage() error = %v", err)
	}
	if imageURL != avatarURL {
		t.Errorf("image URL = %q, want %q", imageURL, avatarURL)
	}
	if updatedImageURL != avatarURL {
		t.Errorf("updated image URL = %q, want %q", updatedImageURL, avatarURL)
	}
}

func TestGoogleProfileImageURLFallsBackToPicture(t *testing.T) {
	metadata := map[string]interface{}{
		"avatar_url": "  ",
		"picture":    "https://lh3.googleusercontent.com/a/google-picture",
	}

	got := googleProfileImageURL(metadata)
	if got != "https://lh3.googleusercontent.com/a/google-picture" {
		t.Errorf("googleProfileImageURL() = %q", got)
	}
}

func TestSendOTPUsesPasswordlessMagicLinkFlow(t *testing.T) {
	var requestBody struct {
		Email      string `json:"email"`
		CreateUser *bool  `json:"create_user"`
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/auth/v1/otp" {
			t.Errorf("request path = %q, want %q", r.URL.Path, "/auth/v1/otp")
		}
		if got := r.Header.Get("apikey"); got != "test-key" {
			t.Errorf("apikey header = %q, want %q", got, "test-key")
		}
		if err := json.NewDecoder(r.Body).Decode(&requestBody); err != nil {
			t.Errorf("decode request body: %v", err)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{}`))
	}))
	defer server.Close()

	client := supabaseclient.CreateClient(server.URL, "test-key")
	repository := NewSupabaseUserRepository(client, "test-key")

	if err := repository.SendOTP(context.Background(), " user@example.com "); err != nil {
		t.Fatalf("SendOTP() error = %v", err)
	}
	if requestBody.Email != "user@example.com" {
		t.Errorf("email = %q, want %q", requestBody.Email, "user@example.com")
	}
	if requestBody.CreateUser == nil || *requestBody.CreateUser {
		t.Errorf("create_user = %v, want pointer to false", requestBody.CreateUser)
	}
}

func TestVerifyOTPUsesEmailType(t *testing.T) {
	var requestBody struct {
		Email string                      `json:"email"`
		Token string                      `json:"token"`
		Type  supabaseclient.EmailOtpType `json:"type"`
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/auth/v1/verify" {
			t.Errorf("request path = %q, want %q", r.URL.Path, "/auth/v1/verify")
		}
		if err := json.NewDecoder(r.Body).Decode(&requestBody); err != nil {
			t.Errorf("decode request body: %v", err)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"access_token":"test-access-token","refresh_token":"test-refresh-token"}`))
	}))
	defer server.Close()

	client := supabaseclient.CreateClient(server.URL, "test-key")
	repository := NewSupabaseUserRepository(client, "test-key")

	tokens, err := repository.VerifyOTP(context.Background(), "user@example.com", "123456")
	if err != nil {
		t.Fatalf("VerifyOTP() error = %v", err)
	}
	if tokens.AccessToken != "test-access-token" {
		t.Errorf("access token = %q, want %q", tokens.AccessToken, "test-access-token")
	}
	if tokens.RefreshToken != "test-refresh-token" {
		t.Errorf("refresh token = %q, want %q", tokens.RefreshToken, "test-refresh-token")
	}
	if requestBody.Email != "user@example.com" {
		t.Errorf("email = %q, want %q", requestBody.Email, "user@example.com")
	}
	if requestBody.Token != "123456" {
		t.Errorf("token = %q, want %q", requestBody.Token, "123456")
	}
	if requestBody.Type != supabaseclient.EmailOtpTypeEmail {
		t.Errorf("type = %q, want %q", requestBody.Type, supabaseclient.EmailOtpTypeEmail)
	}
}
