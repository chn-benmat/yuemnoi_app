package tests

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	"github.com/gofiber/fiber/v3"
	"github.com/stretchr/testify/require"
	"io"
	"log/slog"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

type opsStore struct {
	call       func(string, map[string]any) (json.RawMessage, error)
	events     []string
	failDelete bool
}

func (s *opsStore) RPC(_ context.Context, name string, args map[string]any) (json.RawMessage, error) {
	s.events = append(s.events, name)
	return s.call(name, args)
}
func (s *opsStore) UploadEvidence(context.Context, string, []byte, string) error {
	s.events = append(s.events, "upload")
	return nil
}
func (s *opsStore) ReadEvidence(context.Context, string) ([]byte, string, error) { return nil, "", nil }
func (s *opsStore) DeleteEvidence(context.Context, string) error {
	s.events = append(s.events, "delete")
	if s.failDelete {
		return errors.New("storage_failure")
	}
	return nil
}

type opsVerifier struct{ domain.AuthGateway }

func (opsVerifier) UserIDFromToken(_ context.Context, token string) (string, error) {
	if token == "test-token" {
		return "00000000-0000-4000-8000-000000000001", nil
	}
	return "", domain.ErrInvalidAccessToken
}

func TestIdentityEncryptionAndChecksum(t *testing.T) {
	key := bytes.Repeat([]byte{7}, 32)
	a, err := domain.EncryptIdentity([]byte("synthetic private data"), key)
	require.NoError(t, err)
	b, err := domain.EncryptIdentity([]byte("synthetic private data"), key)
	require.NoError(t, err)
	require.NotEqual(t, a, b)
	plain, err := domain.DecryptIdentity(a, key)
	require.NoError(t, err)
	require.Equal(t, "synthetic private data", string(plain))
	_, err = domain.DecryptIdentity(a, bytes.Repeat([]byte{8}, 32))
	require.Error(t, err)
	_, err = domain.DecryptIdentity("invalid", key)
	require.Error(t, err)
	require.True(t, domain.ValidThaiCitizenID("0000000000001"))
	require.False(t, domain.ValidThaiCitizenID("0000000000002"))
	require.False(t, domain.ValidThaiCitizenID("000000000000x"))
	require.NotEqual(t, domain.CitizenHMAC("0000000000001", key), domain.CitizenHMAC("0000000000001", bytes.Repeat([]byte{8}, 32)))
	now := time.Date(2026, 10, 10, 0, 0, 0, 0, time.UTC)
	minor, err := domain.IdentityAge("2006-10-11", now)
	require.NoError(t, err)
	require.True(t, minor)
	minor, err = domain.IdentityAge("2006-10-10", now)
	require.NoError(t, err)
	require.False(t, minor)
	_, err = domain.IdentityAge("2027-01-01", now)
	require.Error(t, err)
}
func TestIdentityBeginAllowsAllAges(t *testing.T) {
	now := time.Now().UTC()
	for _, tc := range []struct {
		name   string
		body   map[string]any
		minor  bool
		status int
	}{
		{name: "adult birthday today", body: map[string]any{"birth_date": now.AddDate(-20, 0, 0).Format("2006-01-02")}, status: 200},
		{name: "one day before twenty", body: map[string]any{"birth_date": now.AddDate(-20, 0, 1).Format("2006-01-02")}, minor: true, status: 200},
		{name: "age thirteen", body: map[string]any{"birth_date": now.AddDate(-13, 0, 0).Format("2006-01-02")}, minor: true, status: 200},
		{name: "newborn", body: map[string]any{"birth_date": now.Format("2006-01-02")}, minor: true, status: 200},
		{name: "false minor claim ignored", body: map[string]any{"birth_date": "2015-01-01", "is_minor": false}, minor: true, status: 200},
		{name: "true minor claim ignored", body: map[string]any{"birth_date": "2000-01-01", "is_minor": true}, status: 200},
		{name: "explicit adult without birthday", body: map[string]any{"is_minor": false}, status: 200},
		{name: "minor without guardian", body: map[string]any{"is_minor": true}, minor: true, status: 200},
		{name: "legacy minor category without birthday", body: map[string]any{"is_minor": true}, minor: true, status: 200},
		{name: "consent without birth date", body: map[string]any{}, status: 200},
		{name: "null legacy age", body: map[string]any{"is_minor": nil}, status: 200},
		{name: "age is not boolean", body: map[string]any{"is_minor": "false"}, status: 400},
		{name: "blank birthday", body: map[string]any{"birth_date": " "}, status: 400},
		{name: "invalid calendar day", body: map[string]any{"birth_date": "2001-02-29"}, status: 400},
		{name: "buddhist year rejected", body: map[string]any{"birth_date": "2543-01-01"}, status: 400},
		{name: "future", body: map[string]any{"birth_date": now.AddDate(0, 0, 1).Format("2006-01-02")}, status: 400},
		{name: "no maximum age", body: map[string]any{"birth_date": now.AddDate(-126, 0, 0).Format("2006-01-02")}, status: 200},
		{name: "missing consent", body: map[string]any{"birth_date": "2000-01-01", "consent_version": ""}, status: 400},
		{name: "wrong consent", body: map[string]any{"birth_date": "2000-01-01", "consent_version": "other"}, status: 400},
	} {
		t.Run(tc.name, func(t *testing.T) {
			store := &opsStore{call: func(name string, args map[string]any) (json.RawMessage, error) {
				require.Equal(t, "identity_begin", name)
				require.Equal(t, tc.minor, args["p_minor"])
				require.Equal(t, "identity-v1", args["p_consent"])
				require.Equal(t, "00000000-0000-4000-8000-000000000001", args["p_actor"])
				return json.RawMessage(`{"id":"test-session","capture_until":"2030-01-01T00:00:00Z"}`), nil
			}}
			app := ports.NewHTTPApp()
			app.Post("/identity", ports.NewOperationsHandler(domain.OperationsOptions{
				Store: store, EncryptionKey: bytes.Repeat([]byte{1}, 32), HMACKey: bytes.Repeat([]byte{2}, 32),
			}, opsVerifier{}).Begin)
			if _, exists := tc.body["consent_version"]; !exists {
				tc.body["consent_version"] = "identity-v1"
			}
			body, err := json.Marshal(tc.body)
			require.NoError(t, err)
			request := httptest.NewRequest("POST", "/identity", bytes.NewReader(body))
			request.Header.Set("Authorization", "Bearer test-token")
			request.Header.Set("Content-Type", "application/json")
			response, err := app.Test(request)
			require.NoError(t, err)
			defer response.Body.Close()
			require.Equal(t, tc.status, response.StatusCode)
			if tc.status == 400 {
				require.Empty(t, store.events)
			} else {
				require.Equal(t, []string{"identity_begin"}, store.events)
			}
		})
	}
}
func TestStaffErrorIsPrivate(t *testing.T) {
	for _, failure := range []string{"staff_required", "raw SQL citizen_id secret"} {
		store := &opsStore{call: func(string, map[string]any) (json.RawMessage, error) { return nil, errors.New(failure) }}
		app := fiber.New()
		app.Get("/admin/:module", ports.NewOperationsHandler(domain.OperationsOptions{Store: store}, opsVerifier{}).Read)
		request := httptest.NewRequest("GET", "/admin/users", nil)
		request.Header.Set("Authorization", "Bearer test-token")
		response, err := app.Test(request)
		require.NoError(t, err)
		body, err := io.ReadAll(response.Body)
		require.NoError(t, err)
		response.Body.Close()
		require.NotContains(t, string(body), "citizen_id")
		require.NotContains(t, string(body), "secret")
		if failure == "staff_required" {
			require.Equal(t, 403, response.StatusCode)
		} else {
			require.Equal(t, 503, response.StatusCode)
		}
	}
}

func TestInvalidIdentitySettingsReturnBadRequest(t *testing.T) {
	store := &opsStore{call: func(name string, args map[string]any) (json.RawMessage, error) {
		require.Equal(t, "admin_action", name)
		require.Equal(t, "settings", args["p_action"])
		return nil, errors.New("invalid_settings")
	}}
	app := fiber.New()
	app.Post("/admin/actions/:action/:target", ports.NewOperationsHandler(domain.OperationsOptions{Store: store}, opsVerifier{}).Action)
	request := httptest.NewRequest("POST", "/admin/actions/settings/identity", strings.NewReader(`{"identity_open_to_all":"yes","reason":"test invalid type"}`))
	request.Header.Set("Authorization", "Bearer test-token")
	request.Header.Set("Content-Type", "application/json")
	response, err := app.Test(request)
	require.NoError(t, err)
	defer response.Body.Close()
	require.Equal(t, 400, response.StatusCode)
	var body map[string]any
	require.NoError(t, json.NewDecoder(response.Body).Decode(&body))
	require.Equal(t, "invalid_settings", body["code"])
}
func TestBusinessGuardKeepsUnverifiedAdultsRenting(t *testing.T) {
	store := &opsStore{call: func(string, map[string]any) (json.RawMessage, error) {
		return json.RawMessage(`{"can_list":false,"enforcement":true,"control":null}`), nil
	}}
	app := ports.SetupRouterWithOperations(domain.OperationsOptions{Store: store}, nil, opsVerifier{}, nil, nil, nil, nil, "")
	for _, path := range []string{"/api/items", "/api/rentals"} {
		req := httptest.NewRequest("POST", path, strings.NewReader("{}"))
		req.Header.Set("Authorization", "Bearer test-token")
		req.Header.Set("Content-Type", "application/json")
		res, err := app.Test(req)
		require.NoError(t, err)
		res.Body.Close()
		if path == "/api/items" {
			require.Equal(t, 403, res.StatusCode)
		} else {
			require.NotEqual(t, 403, res.StatusCode)
		}
	}
}
func TestCleanupDoesNotEraseBeforeStorageDelete(t *testing.T) {
	for _, fail := range []bool{true, false} {
		store := &opsStore{failDelete: fail, call: func(_ string, args map[string]any) (json.RawMessage, error) {
			if args["p_done"] == nil && args["p_completed"] == nil {
				return json.RawMessage(`[{"id":"00000000-0000-4000-8000-000000000002","object_path":"synthetic/image"}]`), nil
			}
			return json.RawMessage("[]"), nil
		}}
		err := ports.CleanupIdentity(context.Background(), store)
		if fail {
			require.Error(t, err)
			require.Equal(t, []string{"identity_cleanup", "delete"}, store.events)
		} else {
			require.NoError(t, err)
			require.Equal(t, []string{"identity_cleanup", "delete", "identity_cleanup", "identity_cleanup"}, store.events)
		}
	}
}

func TestIdentityResponseBodyIsNeverLogged(t *testing.T) {
	var logs bytes.Buffer
	previous := slog.Default()
	slog.SetDefault(slog.New(slog.NewJSONHandler(&logs, nil)))
	t.Cleanup(func() { slog.SetDefault(previous) })
	app := fiber.New()
	app.Use(ports.ResponseLoggingMiddleware())
	app.Get("/api/identity/fixture", func(c fiber.Ctx) error {
		return c.JSON(fiber.Map{"citizen_id": "sensitive-fixture", "legal_name": "private-fixture"})
	})
	res, err := app.Test(httptest.NewRequest("GET", "/api/identity/fixture", nil))
	require.NoError(t, err)
	res.Body.Close()
	require.NotContains(t, logs.String(), "sensitive-fixture")
	require.NotContains(t, logs.String(), "private-fixture")
	require.Contains(t, logs.String(), "identity data omitted")
}
