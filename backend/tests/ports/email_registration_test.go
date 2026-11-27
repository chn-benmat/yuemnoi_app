package ports_test

import (
	"bytes"
	"context"
	"encoding/json"
	"mime/multipart"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/emaildns"
	supabaseadapter "github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	supabaseclient "github.com/nedpals/supabase-go"
)

type registrationGateway struct {
	domain.AuthGateway
	registered bool
}

func (g *registrationGateway) Register(context.Context, domain.RegisterUser) (*domain.RegisterResult, error) {
	g.registered = true
	return &domain.RegisterResult{UserID: userTestID}, nil
}

type registrationDNS struct {
	mx       []*net.MX
	mxErr    error
	hosts    []string
	hostErr  error
	mxName   string
	hostName string
}

func (d *registrationDNS) LookupMX(_ context.Context, name string) ([]*net.MX, error) {
	d.mxName = name
	return d.mx, d.mxErr
}

func (d *registrationDNS) LookupHost(_ context.Context, name string) ([]string, error) {
	d.hostName = name
	return d.hosts, d.hostErr
}

func registrationRequest(t *testing.T, email string) *http.Request {
	t.Helper()
	var body bytes.Buffer
	form := multipart.NewWriter(&body)
	for field, value := range map[string]string{
		"display_name": "Test User", "email": email, "phone": "0812345678", "password": "test-password",
	} {
		if err := form.WriteField(field, value); err != nil {
			t.Fatal(err)
		}
	}
	if err := form.Close(); err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest(http.MethodPost, "/api/auth/register", &body)
	req.Header.Set("Content-Type", form.FormDataContentType())
	req.Header.Set("X-App-Secret", "test-secret")
	return req
}

func TestRegistrationChecksEmailDomainBeforeSignup(t *testing.T) {
	notFound := &net.DNSError{IsNotFound: true}
	timedOut := &net.DNSError{IsTemporary: true, IsTimeout: true}
	tests := []struct {
		name       string
		email      string
		dns        registrationDNS
		wantMX     string
		wantHost   string
		wantSignup bool
	}{
		{
			name: "missing domain", email: "person@example.invalid",
			dns:    registrationDNS{mxErr: notFound, hostErr: notFound},
			wantMX: "example.invalid.", wantHost: "example.invalid.",
		},
		{
			name: "domain opts out even with an IP address", email: "person@example.test",
			dns:    registrationDNS{mx: []*net.MX{{Host: "."}}, hosts: []string{"192.0.2.1"}},
			wantMX: "example.test.",
		},
		{
			name: "mail server available", email: "person@ExAmPle.test",
			dns:    registrationDNS{mx: []*net.MX{{Host: "mx.example.test."}}},
			wantMX: "example.test.", wantSignup: true,
		},
		{
			name: "IP fallback without MX", email: "person@example.test",
			dns:    registrationDNS{mxErr: notFound, hosts: []string{"2001:db8::1"}},
			wantMX: "example.test.", wantHost: "example.test.", wantSignup: true,
		},
		{
			name: "temporary MX failure", email: "person@example.test",
			dns:    registrationDNS{mxErr: timedOut},
			wantMX: "example.test.", wantSignup: true,
		},
		{
			name: "temporary IP lookup failure", email: "person@example.test",
			dns:    registrationDNS{mxErr: notFound, hostErr: timedOut},
			wantMX: "example.test.", wantHost: "example.test.", wantSignup: true,
		},
		{
			name: "internationalized domain", email: "person@bücher.test",
			dns:    registrationDNS{mx: []*net.MX{{Host: "mx.example.test."}}},
			wantMX: "xn--bcher-kva.test.", wantSignup: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gateway := &registrationGateway{}
			checkedGateway := domain.WithRegistrationEmailCheck(gateway, emaildns.NewChecker(&tt.dns))
			app := ports.SetupRouterWithOperations(domain.OperationsOptions{}, nil, checkedGateway, nil, nil, nil, "test-secret")
			t.Cleanup(func() { _ = app.Shutdown() })
			resp, err := app.Test(registrationRequest(t, tt.email))
			if err != nil {
				t.Fatal(err)
			}
			defer resp.Body.Close()
			var result struct {
				Error                string `json:"error"`
				ConfirmationRequired bool   `json:"confirmation_required"`
			}
			if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
				t.Fatal(err)
			}
			if tt.dns.mxName != tt.wantMX || tt.dns.hostName != tt.wantHost {
				t.Fatalf("MX lookup = %q, host lookup = %q, want %q and %q", tt.dns.mxName, tt.dns.hostName, tt.wantMX, tt.wantHost)
			}
			if gateway.registered != tt.wantSignup || result.ConfirmationRequired != tt.wantSignup {
				t.Fatalf("registered = %t, confirmation required = %t, want %t", gateway.registered, result.ConfirmationRequired, tt.wantSignup)
			}
			if tt.wantSignup {
				if resp.StatusCode != http.StatusCreated || result.Error != "" {
					t.Fatalf("status = %d, error = %q, want 201 without error", resp.StatusCode, result.Error)
				}
			} else if resp.StatusCode != http.StatusBadRequest || result.Error != "โดเมนนี้รับอีเมลไม่ได้ กรุณาตรวจสอบส่วนหลัง @" {
				t.Fatalf("status = %d, error = %q, want 400 with an email domain message", resp.StatusCode, result.Error)
			}
		})
	}
}

func TestRegistrationHandlesExistingSupabaseAccounts(t *testing.T) {
	tests := []struct {
		name             string
		identities       json.RawMessage
		echoSignupData   bool
		wantStatus       int
		wantError        string
		wantConfirmation bool
	}{
		{
			name:           "confirmed account such as Google sign-in",
			identities:     json.RawMessage(`[]`),
			echoSignupData: true,
			wantStatus:     http.StatusConflict,
			wantError:      "อีเมลนี้ถูกใช้งานในระบบแล้ว โปรดใช้อีเมลอื่น",
		},
		{
			name:             "email awaiting confirmation",
			identities:       json.RawMessage(`[{"provider":"email"}]`),
			wantStatus:       http.StatusCreated,
			wantConfirmation: true,
		},
		{
			name:             "invited account awaiting confirmation",
			identities:       json.RawMessage(`[]`),
			wantStatus:       http.StatusCreated,
			wantConfirmation: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			authServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				switch {
				case r.Method == http.MethodGet && r.URL.Path == "/auth/v1/settings":
					_, _ = w.Write([]byte(`{"mailer_autoconfirm":false}`))
				case r.Method == http.MethodPost && r.URL.Path == "/auth/v1/signup":
					var body struct {
						Data map[string]string `json:"data"`
					}
					if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
						t.Errorf("decode signup request: %v", err)
						w.WriteHeader(http.StatusBadRequest)
						return
					}
					metadata := map[string]string{}
					if tt.echoSignupData {
						metadata = body.Data
					}
					_ = json.NewEncoder(w).Encode(map[string]any{
						"id":            userTestID,
						"identities":    tt.identities,
						"user_metadata": metadata,
					})
				default:
					t.Errorf("unexpected Auth request: %s %s", r.Method, r.URL.Path)
					w.WriteHeader(http.StatusNotFound)
				}
			}))
			t.Cleanup(authServer.Close)
			repository := supabaseadapter.NewSupabaseUserRepository(supabaseclient.CreateClient(authServer.URL, "test-key"), "test-key")
			dns := &registrationDNS{mx: []*net.MX{{Host: "mx.example.test."}}}
			gateway := domain.WithRegistrationEmailCheck(repository, emaildns.NewChecker(dns))
			app := ports.SetupRouterWithOperations(domain.OperationsOptions{}, nil, gateway, nil, nil, nil, "test-secret")
			t.Cleanup(func() { _ = app.Shutdown() })

			resp, err := app.Test(registrationRequest(t, "existing@example.test"))
			if err != nil {
				t.Fatal(err)
			}
			defer resp.Body.Close()
			var result struct {
				Error                string `json:"error"`
				ConfirmationRequired bool   `json:"confirmation_required"`
				UserID               string `json:"user_id"`
			}
			if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
				t.Fatal(err)
			}
			if resp.StatusCode != tt.wantStatus || result.Error != tt.wantError || result.ConfirmationRequired != tt.wantConfirmation {
				t.Fatalf("status = %d, error = %q, confirmation required = %t; want %d, %q, %t",
					resp.StatusCode, result.Error, result.ConfirmationRequired, tt.wantStatus, tt.wantError, tt.wantConfirmation)
			}
			if result.UserID != "" {
				t.Fatal("registration exposed a user ID for an existing account")
			}
		})
	}
}
