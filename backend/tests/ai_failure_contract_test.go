package tests

import (
	"bytes"
	"encoding/json"
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

// ส่งรหัสแยกโควตาชั่วคราว โควตารายวัน คิว และการตรวจคำตอบ โดยไม่เปิดเผยรายละเอียดภายใน
func TestAIRateLimitContract(t *testing.T) {
	gin.SetMode(gin.TestMode)
	for _, testCase := range []struct {
		code       string
		retryAfter string
	}{
		{code: "providers_rate_limited", retryAfter: "60"},
		{code: "quota_temporarily_unavailable", retryAfter: "37"},
		{code: "quota_exhausted", retryAfter: "41490"},
		{code: "providers_busy"},
		{code: "review_unavailable"},
		{code: "structured_output_invalid"},
		{code: "response_quality_rejected"},
		{code: "providers_exhausted"},
	} {
		t.Run(testCase.code, func(t *testing.T) {
			upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if testCase.retryAfter != "" {
					w.Header().Set("Retry-After", testCase.retryAfter)
				}
				w.WriteHeader(http.StatusServiceUnavailable)
				_ = json.NewEncoder(w).Encode(map[string]any{"detail": map[string]string{
					"error_code": testCase.code, "private": "private-detail",
				}})
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
				require.Equal(t, testCase.retryAfter, response.Header().Get("Retry-After"))
				var payload map[string]any
				require.NoError(t, json.Unmarshal(response.Body.Bytes(), &payload))
				require.Equal(t, testCase.code, payload["error_code"])
				require.NotContains(t, response.Body.String(), "private-detail")
				require.NotContains(t, response.Header().Get("Content-Type"), "event-stream")
			}
		})
	}
}

// แม้เปิด SSE ด้วย HTTP 200 แล้ว รหัสข้อผิดพลาดและเวลารอต้องส่งถึง Flutter ครบ
func TestAIStreamFailureContract(t *testing.T) {
	gin.SetMode(gin.TestMode)
	for _, code := range []string{"quota_temporarily_unavailable", "quota_exhausted", "providers_busy", "review_unavailable", "structured_output_invalid", "response_quality_rejected"} {
		t.Run(code, func(t *testing.T) {
			data := map[string]any{"error_code": code}
			if code == "quota_temporarily_unavailable" || code == "quota_exhausted" {
				data["retry_after_seconds"] = 37
			}
			payload, err := json.Marshal(data)
			require.NoError(t, err)
			sse := "event: error\ndata: " + string(payload) + "\n\n"
			upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "text/event-stream")
				_, _ = io.WriteString(w, sse)
			}))
			defer upstream.Close()
			router := gin.New()
			handler := ports.NewChatbotHandler(aiservice.NewClient(upstream.URL, "", time.Second), nil)
			router.POST("/api/chat-ai/stream", handler.SendMessageStream)
			request := httptest.NewRequest(http.MethodPost, "/api/chat-ai/stream", bytes.NewBufferString(`{"query":"ถาม"}`))
			request.Header.Set("Content-Type", "application/json")
			response := httptest.NewRecorder()
			router.ServeHTTP(response, request)
			require.Equal(t, http.StatusOK, response.Code)
			require.Equal(t, sse, response.Body.String())
		})
	}
}
