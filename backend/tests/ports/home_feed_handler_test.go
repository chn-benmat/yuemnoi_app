package ports_test

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"

	supabaseadapter "github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	supabaseclient "github.com/nedpals/supabase-go"
	"github.com/stretchr/testify/assert"
)

func TestHomeFeedRoute(t *testing.T) {
	const emptyPage = `{"items":[],"next_cursor":null}`
	const defaultParams = `{"p_viewer_id":null,"p_latitude":null,"p_longitude":null,"p_recent_categories":[],"p_cursor":null,"p_limit":24}`
	const fingerprint = "ae0123456789abcdef0123456789abcd"
	const page = `{"items":[{"id":9007199254740993,"item_name":"Camera","pickup_location":"Library","availability_tier":0,"is_rental_occupied":false,"item_image_url":["https://example.invalid/camera.jpg"]}],"next_cursor":"v2:0:25000:9007199254740993:1795800000:` + fingerprint + `"}`
	for _, tc := range []struct {
		name, secret, authorization, request, params, upstreamBody string
		upstreamStatus, status, authCalls                          int
		response, code                                             string
	}{
		{name: "app key required", request: `{}`, status: 401},
		{name: "wrong app key blocks bearer verification", secret: "wrong", authorization: "Bearer user-token", request: `{}`, status: 401},
		{name: "guest defaults", secret: "app-test-key", request: `{"viewer_id":"forged"}`, params: defaultParams, upstreamBody: emptyPage, status: 200, response: emptyPage},
		{name: "verified viewer and unmodified card payload", secret: "app-test-key", authorization: "bEaReR user-token", authCalls: 1,
			request: `{"viewer_id":"forged","latitude":0,"longitude":100.5,"recent_categories":[" camera ","อุปกรณ์"],"cursor":"v2:1:100000:1:1795800000:` + fingerprint + `","limit":48}`,
			params:  `{"p_viewer_id":"00000000-0000-4000-8000-000000000002","p_latitude":0,"p_longitude":100.5,"p_recent_categories":["camera","อุปกรณ์"],"p_cursor":"v2:1:100000:1:1795800000:` + fingerprint + `","p_limit":48}`, upstreamBody: page, status: 200, response: page},
		{name: "invalid bearer", secret: "app-test-key", authorization: "Bearer invalid", request: `{}`, status: 401, authCalls: 1},
		{name: "malformed authorization", secret: "app-test-key", authorization: "Basic invalid", request: `{}`, status: 401},
		{name: "dashboard only", secret: "app-test-key", authorization: "Bearer admin-token", request: `{}`, status: 403, authCalls: 1, code: "dashboard_only"},
		{name: "invalid JSON", secret: "app-test-key", request: `{`, status: 400},
		{name: "latitude requires longitude", secret: "app-test-key", request: `{"latitude":13.7}`, status: 400},
		{name: "latitude out of range", secret: "app-test-key", request: `{"latitude":90.0001,"longitude":100.5}`, status: 400},
		{name: "longitude out of range", secret: "app-test-key", request: `{"latitude":13.7,"longitude":-180.0001}`, status: 400},
		{name: "nonfinite coordinates", secret: "app-test-key", request: `{"latitude":13.7,"longitude":1e309}`, status: 400},
		{name: "nonstring category", secret: "app-test-key", request: `{"recent_categories":[11]}`, status: 400},
		{name: "null category", secret: "app-test-key", request: `{"recent_categories":[null]}`, status: 400},
		{name: "too many categories", secret: "app-test-key", request: `{"recent_categories":[` + strings.Repeat(`"a",`, 10) + `"b"]}`, status: 400},
		{name: "category too long", secret: "app-test-key", request: `{"recent_categories":["` + strings.Repeat("ก", 101) + `"]}`, status: 400},
		{name: "limit below minimum", secret: "app-test-key", request: `{"limit":0}`, status: 400},
		{name: "limit above maximum", secret: "app-test-key", request: `{"limit":49}`, status: 400},
		{name: "empty cursor", secret: "app-test-key", request: `{"cursor":""}`, status: 400, code: "invalid_home_feed_cursor"},
		{name: "bad cursor version", secret: "app-test-key", request: `{"cursor":"v1:0:0:1:1795800000:` + fingerprint + `"}`, status: 400},
		{name: "bad cursor tier", secret: "app-test-key", request: `{"cursor":"v2:2:0:1:1795800000:` + fingerprint + `"}`, status: 400},
		{name: "bad cursor score", secret: "app-test-key", request: `{"cursor":"v2:0:100001:1:1795800000:` + fingerprint + `"}`, status: 400},
		{name: "bad cursor item id", secret: "app-test-key", request: `{"cursor":"v2:0:0:0:1795800000:` + fingerprint + `"}`, status: 400},
		{name: "noncanonical cursor item id", secret: "app-test-key", request: `{"cursor":"v2:0:0:01:1795800000:` + fingerprint + `"}`, status: 400},
		{name: "bad cursor epoch", secret: "app-test-key", request: `{"cursor":"v2:0:0:1:0:` + fingerprint + `"}`, status: 400},
		{name: "noncanonical cursor epoch", secret: "app-test-key", request: `{"cursor":"v2:0:0:1:1111111111111:` + fingerprint + `"}`, status: 400},
		{name: "overflowing cursor item id", secret: "app-test-key", request: `{"cursor":"v2:0:0:9223372036854775808:1795800000:` + fingerprint + `"}`, status: 400},
		{name: "bad cursor fingerprint", secret: "app-test-key", request: `{"cursor":"v2:0:0:1:1795800000:badfingerprint"}`, status: 400},
		{name: "SQL rejects expired cursor", secret: "app-test-key", request: `{"cursor":"v2:0:0:1:1:` + fingerprint + `"}`,
			params: `{"p_viewer_id":null,"p_latitude":null,"p_longitude":null,"p_recent_categories":[],"p_cursor":"v2:0:0:1:1:` + fingerprint + `","p_limit":24}`, upstreamStatus: 400, upstreamBody: `{"code":"22023","message":"cursor expired"}`, status: 400, code: "invalid_home_feed_cursor"},
		{name: "upstream unexpected error remains generic", secret: "app-test-key", request: `{}`, params: defaultParams, upstreamStatus: 500,
			upstreamBody: `{"code":"XX000","message":"private data"}`, status: 500},
		{name: "malformed RPC page", secret: "app-test-key", request: `{}`, params: defaultParams, upstreamBody: `{"items":null}`, status: 500},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var authCalls, rpcCalls atomic.Int32
			supabase := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				switch r.URL.Path {
				case "/auth/v1/user":
					authCalls.Add(1)
					switch r.Header.Get("Authorization") {
					case "Bearer user-token":
						_, _ = io.WriteString(w, `{"id":"00000000-0000-4000-8000-000000000002","app_metadata":{}}`)
					case "Bearer admin-token":
						_, _ = io.WriteString(w, `{"id":"00000000-0000-4000-8000-000000000001","app_metadata":{"dashboard_only":true}}`)
					default:
						w.WriteHeader(http.StatusUnauthorized)
					}
				case "/rest/v1/rpc/get_home_feed_v2":
					rpcCalls.Add(1)
					body, err := io.ReadAll(r.Body)
					assert.NoError(t, err)
					assert.Equal(t, http.MethodPost, r.Method)
					assert.Equal(t, "service-role-test-key", r.Header.Get("apikey"))
					assert.Equal(t, "Bearer service-role-test-key", r.Header.Get("Authorization"))
					assert.JSONEq(t, tc.params, string(body))
					if tc.upstreamStatus != 0 {
						w.WriteHeader(tc.upstreamStatus)
					}
					_, _ = io.WriteString(w, tc.upstreamBody)
				default:
					t.Errorf("unexpected Supabase request %s %s", r.Method, r.URL.Path)
					w.WriteHeader(http.StatusNotFound)
				}
			}))
			t.Cleanup(supabase.Close)

			client := supabaseclient.CreateClient(supabase.URL, "service-role-test-key")
			gateway := supabaseadapter.NewSupabaseUserRepository(client, "service-role-test-key")
			app := ports.SetupRouter(nil, gateway, nil, nil, nil, "app-test-key")
			t.Cleanup(func() { _ = app.Shutdown() })
			ports.RegisterHomeFeedRoutes(app, supabaseadapter.NewSupabaseHomeFeedRepository(client), gateway)
			request := httptest.NewRequest(http.MethodPost, "/api/home/feed", strings.NewReader(tc.request))
			request.Header.Set("Content-Type", "application/json")
			request.Header.Set("X-App-Secret", tc.secret)
			request.Header.Set("Authorization", tc.authorization)
			response, err := app.Test(request)
			if err != nil {
				t.Fatal(err)
			}
			defer response.Body.Close()
			body, err := io.ReadAll(response.Body)
			if err != nil {
				t.Fatal(err)
			}
			assert.Equal(t, tc.status, response.StatusCode, string(body))
			assert.Equal(t, tc.authCalls, int(authCalls.Load()))
			if tc.params == "" {
				assert.Zero(t, rpcCalls.Load())
			} else {
				assert.EqualValues(t, 1, rpcCalls.Load())
			}
			if tc.status == 200 {
				assert.Equal(t, "private, no-store", response.Header.Get("Cache-Control"))
				assert.JSONEq(t, tc.response, string(body))
				if tc.response == page {
					assert.Contains(t, string(body), `"id":9007199254740993`)
				}
			} else {
				assert.NotContains(t, string(body), "private data")
			}
			if tc.code != "" {
				var errorBody struct{ Code string }
				assert.NoError(t, json.Unmarshal(body, &errorBody))
				assert.Equal(t, tc.code, errorBody.Code)
			}
		})
	}
}
