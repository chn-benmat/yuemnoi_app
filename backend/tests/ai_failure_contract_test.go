package tests

import (
	"bytes"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/aiservice"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

// โควตาล้มเหลวต้องตอบทันทีตามรหัสเดิม ไม่เปิด SSE หรือเปิดเผยข้อความจาก upstream
func TestAIRateLimitContract(t *testing.T) {
	gin.SetMode(gin.TestMode)
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Retry-After", "60")
		w.WriteHeader(http.StatusServiceUnavailable)
		_, _ = io.WriteString(w, `{"detail":{"error_code":"providers_rate_limited","private":"private-detail"}}`)
	}))
	defer upstream.Close()
	for _, path := range []string{"/api/chat-ai", "/api/chat-ai/stream"} {
		router := gin.New()
		handler := ports.NewChatbotHandler(aiservice.NewClient(upstream.URL, "", time.Second), nil)
		router.POST("/api/chat-ai", handler.SendMessage)
		router.POST("/api/chat-ai/stream", handler.SendMessageStream)
		request := httptest.NewRequest(http.MethodPost, path, bytes.NewBufferString(`{"query":"ถาม"}`))
		request.Header.Set("Content-Type", "application/json")
		response := httptest.NewRecorder()
		router.ServeHTTP(response, request)
		require.Equal(t, http.StatusServiceUnavailable, response.Code)
		require.Equal(t, "60", response.Header().Get("Retry-After"))
		require.Contains(t, response.Body.String(), "providers_rate_limited")
		require.NotContains(t, response.Body.String(), "private-detail")
		require.NotContains(t, response.Header().Get("Content-Type"), "event-stream")
	}
}
