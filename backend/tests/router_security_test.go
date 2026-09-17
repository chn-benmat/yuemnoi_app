package tests

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

func TestRouterSecurityMiddleware(t *testing.T) {
	gin.SetMode(gin.TestMode)

	router := ports.SetupRouter(nil, nil, nil, nil, nil, nil, "test-app-secret")
	tests := []struct {
		name       string
		method     string
		path       string
		appSecret  string
		wantStatus int
	}{
		{
			name:       "rejects request without app secret",
			method:     http.MethodGet,
			path:       "/api/v1/items",
			wantStatus: http.StatusUnauthorized,
		},
		{
			name:       "rejects request with incorrect app secret",
			method:     http.MethodGet,
			path:       "/api/v1/items",
			appSecret:  "incorrect",
			wantStatus: http.StatusUnauthorized,
		},
		{
			name:       "allows request with correct app secret",
			method:     http.MethodGet,
			path:       "/missing",
			appSecret:  "test-app-secret",
			wantStatus: http.StatusNotFound,
		},
		{
			name:       "allows health check without app secret",
			method:     http.MethodGet,
			path:       "/health",
			wantStatus: http.StatusOK,
		},
		{
			name:       "allows cors preflight without app secret",
			method:     http.MethodOptions,
			path:       "/api/v1/items",
			wantStatus: http.StatusNoContent,
		},
		{
			name:       "blocks environment file scans before app secret check",
			method:     http.MethodGet,
			path:       "/.env",
			wantStatus: http.StatusNotFound,
		},
		{
			name:       "blocks git directory scans case insensitively",
			method:     http.MethodGet,
			path:       "/.GIT/config",
			wantStatus: http.StatusNotFound,
		},
		{
			name:       "blocks php scans case insensitively",
			method:     http.MethodGet,
			path:       "/shell.PHP",
			wantStatus: http.StatusNotFound,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			request := httptest.NewRequest(tt.method, tt.path, nil)
			if tt.appSecret != "" {
				request.Header.Set("X-App-Secret", tt.appSecret)
			}
			response := httptest.NewRecorder()

			router.ServeHTTP(response, request)

			assert.Equal(t, tt.wantStatus, response.Code)
		})
	}
}

func TestRouterAllowsRequestsWhenAppSecretIsNotConfigured(t *testing.T) {
	gin.SetMode(gin.TestMode)

	router := ports.SetupRouter(nil, nil, nil, nil, nil, nil, "")
	request := httptest.NewRequest(http.MethodGet, "/missing", nil)
	response := httptest.NewRecorder()

	router.ServeHTTP(response, request)

	assert.Equal(t, http.StatusNotFound, response.Code)
}

func TestRouterMultiKeyRotation(t *testing.T) {
	gin.SetMode(gin.TestMode)

	// จำลองสถานการณ์ Multi-Key Rotation: เซิร์ฟเวอร์รองรับทั้งคีย์ใหม่และคีย์เดิม
	router := ports.SetupRouter(nil, nil, nil, nil, nil, nil, "new-secret-2026,old-secret-2025")

	tests := []struct {
		name       string
		key        string
		wantStatus int
	}{
		{
			name:       "allows new secret key during rotation",
			key:        "new-secret-2026",
			wantStatus: http.StatusNotFound,
		},
		{
			name:       "allows old secret key during rotation",
			key:        "old-secret-2025",
			wantStatus: http.StatusNotFound,
		},
		{
			name:       "rejects unrecognized secret key",
			key:        "wrong-secret-key",
			wantStatus: http.StatusUnauthorized,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			request := httptest.NewRequest(http.MethodGet, "/missing", nil)
			request.Header.Set("X-App-Secret", tt.key)
			response := httptest.NewRecorder()

			router.ServeHTTP(response, request)
			assert.Equal(t, tt.wantStatus, response.Code)
		})
	}
}
