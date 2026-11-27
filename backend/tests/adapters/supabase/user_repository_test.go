package supabase_test

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	supabase "github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	supabaseclient "github.com/nedpals/supabase-go"
)

func TestRegisterUsesSupabaseEmailConfirmation(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/auth/v1/settings":
			_, _ = w.Write([]byte(`{"mailer_autoconfirm":false}`))
		case "/auth/v1/signup":
			var body struct {
				Email    string            `json:"email"`
				Password string            `json:"password"`
				Phone    string            `json:"phone"`
				Data     map[string]string `json:"data"`
			}
			if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
				t.Errorf("decode signup request: %v", err)
			}
			if r.Method != http.MethodPost || r.URL.Query().Get("redirect_to") != "yuemnoi://login-callback/" ||
				body.Email != "new@example.com" || body.Password != "test-password" || body.Phone != "" ||
				body.Data["display_name"] != "Test name" || body.Data["phone"] != "+66812345678" {
				t.Error("signup should send email credentials and keep the contact phone in profile metadata")
			}
			_ = json.NewEncoder(w).Encode(map[string]any{
				"id":                 "new-user",
				"email_confirmed_at": nil,
				"identities":         []map[string]string{{"provider": "email"}},
				"user_metadata":      body.Data,
			})
		default:
			t.Errorf("unexpected request: %s", r.URL.Path)
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer server.Close()
	repository := supabase.NewSupabaseUserRepository(supabaseclient.CreateClient(server.URL, "test-key"), "test-key")

	result, err := repository.Register(context.Background(), domain.RegisterUser{
		Email: "new@example.com", Password: "test-password", DisplayName: "Test name", Phone: "+66812345678",
	})
	if err != nil || result == nil || result.UserID != "new-user" {
		t.Fatalf("Register() = %v, %v", result, err)
	}
}

func TestGetProfileReturnsUsernameChangeTime(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/rest/v1/profile_tb":
			columns := strings.Split(r.URL.Query().Get("select"), ",")
			profile := map[string]string{
				"user_id": "u1", "username": "elle.com_", "display_name": "ELLE",
				"email": "elle@example.com", "phone": "+66812345678",
				"user_image_url": "https://example.com/profile.png",
			}
			for _, column := range columns {
				if column == "username_changed_at" {
					profile[column] = "2026-11-27T05:00:00Z"
				}
			}
			_ = json.NewEncoder(w).Encode([]map[string]string{profile})
		default:
			t.Errorf("unexpected request: %s", r.URL.Path)
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer server.Close()
	repository := supabase.NewSupabaseUserRepository(supabaseclient.CreateClient(server.URL, "test-key"), "test-key")

	profile, err := repository.GetProfile(context.Background(), "u1")
	if err != nil {
		t.Fatal(err)
	}
	response, err := json.Marshal(profile)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(response), `"username_changed_at":"2026-11-27T05:00:00Z"`) {
		t.Fatalf("GetProfile() returned %s, want persisted username change time", response)
	}
}

func TestRegisterStopsWhenSupabaseAutoConfirmsEmail(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/auth/v1/settings" {
			t.Errorf("request with auto-confirm enabled: %s", r.URL.Path)
		}
		_, _ = w.Write([]byte(`{"mailer_autoconfirm":true}`))
	}))
	defer server.Close()
	repository := supabase.NewSupabaseUserRepository(supabaseclient.CreateClient(server.URL, "test-key"), "test-key")

	result, err := repository.Register(context.Background(), domain.RegisterUser{})
	if result != nil || err == nil {
		t.Fatalf("Register() = %v, %v, want an error without creating a user", result, err)
	}
}

func TestLoginDistinguishesUnconfirmedEmail(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error_code":"email_not_confirmed","msg":"Email not confirmed"}`))
	}))
	defer server.Close()
	repository := supabase.NewSupabaseUserRepository(supabaseclient.CreateClient(server.URL, "test-key"), "test-key")

	_, err := repository.Login(context.Background(), "pending@example.com", "test-password")
	if !errors.Is(err, domain.ErrEmailNotConfirmed) {
		t.Fatalf("Login() error = %v, want email not confirmed", err)
	}
}

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
	repository := supabase.NewSupabaseUserRepository(supabaseclient.CreateClient(server.URL, "test-key"), "test-key")
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
	repository := supabase.NewSupabaseUserRepository(client, "test-key")

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
	repository := supabase.NewSupabaseUserRepository(client, "test-key")

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
	repository := supabase.NewSupabaseUserRepository(client, "test-key")

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
	const picture = "https://lh3.googleusercontent.com/a/google-picture"
	var saved string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/auth/v1/user":
			_ = json.NewEncoder(w).Encode(map[string]any{"id": "google-user", "user_metadata": map[string]string{"avatar_url": "  ", "picture": picture}})
		case "/rest/v1/profile_tb":
			var body struct {
				URL string `json:"user_image_url"`
			}
			if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
				t.Error(err)
			}
			saved = body.URL
			_, _ = w.Write([]byte(`[{"user_id":"google-user"}]`))
		default:
			t.Errorf("unexpected request %s", r.URL.Path)
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer server.Close()
	repository := supabase.NewSupabaseUserRepository(supabaseclient.CreateClient(server.URL, "test-key"), "test-key")
	got, err := repository.SyncGoogleProfileImage(context.Background(), "google-access-token")
	if err != nil || got != picture || saved != picture {
		t.Fatalf("fallback image=%q saved=%q err=%v", got, saved, err)
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
	repository := supabase.NewSupabaseUserRepository(client, "test-key")

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
	repository := supabase.NewSupabaseUserRepository(client, "test-key")

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
