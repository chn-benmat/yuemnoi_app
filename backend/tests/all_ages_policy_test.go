package tests

import (
	"encoding/json"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	"github.com/stretchr/testify/require"
)

func TestBusinessGuardIgnoresLegacyMinorFlagAndKeepsSuspension(t *testing.T) {
	for _, suspended := range []bool{false, true} {
		for _, path := range []string{"/api/items", "/api/rentals"} {
			t.Run(path+"/suspended="+map[bool]string{true: "true", false: "false"}[suspended], func(t *testing.T) {
				store := &opsStore{call: func(name string, _ map[string]any) (json.RawMessage, error) {
					require.Equal(t, "identity_status", name)
					return json.Marshal(map[string]any{"can_list": true, "enforcement": true,
						"control": map[string]any{"is_minor": true, "suspended": suspended}})
				}}
				app := ports.SetupRouterWithOperations(domain.OperationsOptions{Store: store}, nil, opsVerifier{}, nil, nil, nil, nil, "")
				request := httptest.NewRequest("POST", path, strings.NewReader("{}"))
				request.Header.Set("Authorization", "Bearer test-token")
				request.Header.Set("Content-Type", "application/json")
				response, err := app.Test(request)
				require.NoError(t, err)
				defer response.Body.Close()
				if suspended {
					require.Equal(t, 403, response.StatusCode)
				} else {
					require.Equal(t, 400, response.StatusCode)
				}
			})
		}
	}
}

func TestGuardianEndpointsAreRetired(t *testing.T) {
	store := &opsStore{call: func(string, map[string]any) (json.RawMessage, error) {
		t.Fatal("retired endpoint must not call the database")
		return nil, nil
	}}
	app := ports.SetupRouterWithOperations(domain.OperationsOptions{Store: store}, nil, opsVerifier{}, nil, nil, nil, nil, "")
	for _, endpoint := range []struct{ method, path string }{
		{"POST", "/api/identity/guardians"},
		{"GET", "/api/admin/guardians"},
		{"GET", "/api/admin/guardian-detail"},
		{"POST", "/api/admin/actions/guardian-review/identity"},
		{"POST", "/api/admin/actions/revoke-guardian/identity"},
	} {
		request := httptest.NewRequest(endpoint.method, endpoint.path, nil)
		request.Header.Set("Authorization", "Bearer test-token")
		response, err := app.Test(request)
		require.NoError(t, err)
		response.Body.Close()
		require.Equal(t, 404, response.StatusCode, endpoint.path)
	}
	require.Empty(t, store.events)
}
