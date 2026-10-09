package tests

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	"github.com/stretchr/testify/require"
)

func TestAllAPIEndpointsPreflightAndUnsupportedMethod(t *testing.T) {
	for _, tc := range apiContractCases() {
		t.Run(tc.method+" "+tc.pattern, func(t *testing.T) {
			f := newAPIContractFixture(t)
			app := f.app()
			request := httptest.NewRequest(http.MethodOptions, tc.path, nil)
			request.Header.Set("Origin", "https://client.yuemnoi.com")
			recorder := httptest.NewRecorder()
			performFiberRequest(t, app, recorder, request)
			require.Equal(t, 204, recorder.Code)
			require.Empty(t, recorder.Body.String())
			require.Equal(t, "https://client.yuemnoi.com", recorder.Header().Get("Access-Control-Allow-Origin"))
			require.Contains(t, recorder.Header().Get("Access-Control-Allow-Headers"), "X-App-Secret")
			require.Empty(t, f.calls)

			tc.method = http.MethodPatch
			recorder = contractRequest(t, app, tc, "Bearer "+contractBearer, contractAppKey)
			require.Equal(t, 404, recorder.Code)
			require.Equal(t, "404 page not found", recorder.Body.String())
			require.Empty(t, f.calls)
		})
	}
}

func TestAPICORSRejectsImpersonatedHosts(t *testing.T) {
	app := ports.SetupRouter(nil, nil, nil, nil, nil, nil, "")
	for _, origin := range []string{
		"https://evilyuemnoi.com", "https://yuemnoi.com.evil.test", "http://localhost.evil.test",
		"http://127.0.0.1.evil.test", "https://evil.test/yuemnoi.com", "null", "garbage.ts.net",
	} {
		t.Run(origin, func(t *testing.T) {
			request := httptest.NewRequest(http.MethodOptions, "/api/items", nil)
			request.Header.Set("Origin", origin)
			recorder := httptest.NewRecorder()
			performFiberRequest(t, app, recorder, request)
			require.Equal(t, 204, recorder.Code)
			require.Empty(t, recorder.Header().Get("Access-Control-Allow-Origin"))
			require.Empty(t, recorder.Header().Get("Access-Control-Allow-Credentials"))
		})
	}
}

func TestAPIAllAuthAndAIRoutesEnforceRateLimits(t *testing.T) {
	for _, tc := range apiContractCases() {
		limit := 0
		if strings.HasPrefix(tc.path, "/api/auth/") {
			limit = 5
		} else if strings.HasPrefix(tc.path, "/api/chat-ai") {
			limit = 15
		}
		if limit == 0 {
			continue
		}
		t.Run(tc.pattern, func(t *testing.T) {
			f := newAPIContractFixture(t)
			app := f.app()
			for index := 0; index <= limit; index++ {
				recorder := contractRequest(t, app, tc, "Bearer "+contractBearer, contractAppKey)
				if index < limit {
					require.Equal(t, tc.status, recorder.Code, recorder.Body.String())
				} else {
					require.Equal(t, 429, recorder.Code)
					require.Contains(t, recorder.Header().Get("Content-Type"), "application/json")
				}
			}
			require.Equal(t, limit, f.calls[tc.op], "rate-limited request reached adapter")
		})
	}
}

func TestAPITransportRejectsInvalidAndOversizedBodiesOverTCP(t *testing.T) {
	f := newAPIContractFixture(t)
	baseURL := startFiberListener(t, f.app())
	client := &http.Client{Timeout: 5 * time.Second}
	for _, c := range []struct {
		name, contentType, body string
		status                  int
	}{
		{"malformed multipart", "multipart/form-data; boundary=absent", "invalid body", 400},
		{"body exceeds 32 MiB", "application/json", strings.Repeat("x", (32<<20)+1), 413},
	} {
		t.Run(c.name, func(t *testing.T) {
			request, err := http.NewRequest("POST", baseURL+"/api/items", strings.NewReader(c.body))
			require.NoError(t, err)
			request.Header.Set("Content-Type", c.contentType)
			request.Header.Set("Authorization", "Bearer "+contractBearer)
			request.Header.Set("X-App-Secret", contractAppKey)
			if c.status == 413 {
				// รอ server ตรวจขนาดจาก headers ก่อนส่ง body ที่เกินเพดาน
				request.Header.Set("Expect", "100-continue")
			}
			response, err := client.Do(request)
			require.NoError(t, err)
			defer response.Body.Close()
			require.Equal(t, c.status, response.StatusCode)
			_, err = io.Copy(io.Discard, response.Body)
			require.NoError(t, err)
		})
	}
	response, err := client.Get(baseURL + "/health")
	require.NoError(t, err)
	defer response.Body.Close()
	require.Equal(t, 200, response.StatusCode)
}
