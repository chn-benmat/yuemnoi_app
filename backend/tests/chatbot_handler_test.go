package tests

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

// mockAIChatbotGateway จำลองการทำงานของ AIChatbotGateway สำหรับ Unit Test
type mockAIChatbotGateway struct {
	sendMessageFunc       func(ctx context.Context, req domain.ChatbotRequest) (*domain.ChatbotResponse, error)
	sendMessageStreamFunc func(ctx context.Context, req domain.ChatbotRequest) (io.ReadCloser, error)
}

func (m *mockAIChatbotGateway) SendMessage(ctx context.Context, req domain.ChatbotRequest) (*domain.ChatbotResponse, error) {
	if m.sendMessageFunc != nil {
		return m.sendMessageFunc(ctx, req)
	}
	return nil, errors.New("not implemented")
}

func (m *mockAIChatbotGateway) SendMessageStream(ctx context.Context, req domain.ChatbotRequest) (io.ReadCloser, error) {
	if m.sendMessageStreamFunc != nil {
		return m.sendMessageStreamFunc(ctx, req)
	}
	return nil, errors.New("not implemented")
}

func TestChatbotSendMessageSuccess(t *testing.T) {
	gin.SetMode(gin.TestMode)

	mockGateway := &mockAIChatbotGateway{
		sendMessageFunc: func(ctx context.Context, req domain.ChatbotRequest) (*domain.ChatbotResponse, error) {
			assert.Equal(t, "มีกล้อง Sony ไหม", req.EffectiveMessage())
			assert.Len(t, req.History, 2)
			return &domain.ChatbotResponse{
				Status: "success",
				Answer: "มีกล้อง Sony A7IV ให้เช่าครับ",
				RecommendedItems: []domain.RecommendedItem{
					{
						ID:       "item-1",
						Name:     "Sony A7IV",
						Price:    800,
						Status:   "available",
						Category: "Camera",
					},
				},
			}, nil
		},
	}

	handler := ports.NewChatbotHandler(mockGateway, nil)
	router := gin.New()
	router.POST("/api/chat-ai", handler.SendMessage)

	reqBody := domain.ChatbotRequest{
		Query: "มีกล้อง Sony ไหม",
		History: []domain.ChatMessageItem{
			{Role: "user", Content: "สวัสดีครับ"},
			{Role: "assistant", Content: "สวัสดีครับ มีอะไรให้ช่วยไหมครับ"},
		},
	}
	bodyBytes, _ := json.Marshal(reqBody)
	req := httptest.NewRequest(http.MethodPost, "/api/chat-ai", bytes.NewReader(bodyBytes))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
	var resp domain.ChatbotResponse
	err := json.Unmarshal(w.Body.Bytes(), &resp)
	assert.NoError(t, err)
	assert.Equal(t, "success", resp.Status)
	assert.Equal(t, "มีกล้อง Sony A7IV ให้เช่าครับ", resp.Answer)
	assert.Len(t, resp.RecommendedItems, 1)
	assert.Equal(t, "Sony A7IV", resp.RecommendedItems[0].Name)
}

func TestChatbotSendMessageEmptyValidation(t *testing.T) {
	gin.SetMode(gin.TestMode)

	handler := ports.NewChatbotHandler(&mockAIChatbotGateway{}, nil)
	router := gin.New()
	router.POST("/api/chat-ai", handler.SendMessage)

	reqBody := domain.ChatbotRequest{
		Query:   "   ",
		Message: "",
	}
	bodyBytes, _ := json.Marshal(reqBody)
	req := httptest.NewRequest(http.MethodPost, "/api/chat-ai", bytes.NewReader(bodyBytes))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusBadRequest, w.Code)
	assert.Contains(t, w.Body.String(), "กรุณาระบุข้อความคำถาม")
}

func TestChatbotSendMessageGatewayError(t *testing.T) {
	gin.SetMode(gin.TestMode)

	mockGateway := &mockAIChatbotGateway{
		sendMessageFunc: func(ctx context.Context, req domain.ChatbotRequest) (*domain.ChatbotResponse, error) {
			return nil, errors.New("connection refused to ai service")
		},
	}

	handler := ports.NewChatbotHandler(mockGateway, nil)
	router := gin.New()
	router.POST("/api/chat-ai", handler.SendMessage)

	reqBody := domain.ChatbotRequest{Query: "สอบถามสินค้า"}
	bodyBytes, _ := json.Marshal(reqBody)
	req := httptest.NewRequest(http.MethodPost, "/api/chat-ai", bytes.NewReader(bodyBytes))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusBadGateway, w.Code)
	assert.Contains(t, w.Body.String(), "ผู้ช่วย AI ขัดข้องชั่วคราว")
}

func TestChatbotSendMessageStreamSuccess(t *testing.T) {
	gin.SetMode(gin.TestMode)

	ssePayload := "event: delta\ndata: {\"text\": \"สวั\"}\n\nevent: delta\ndata: {\"text\": \"สดี\"}\n\nevent: done\ndata: {\"status\": \"done\"}\n\n"
	mockGateway := &mockAIChatbotGateway{
		sendMessageStreamFunc: func(ctx context.Context, req domain.ChatbotRequest) (io.ReadCloser, error) {
			assert.Equal(t, "ทักทาย", req.EffectiveMessage())
			return io.NopCloser(strings.NewReader(ssePayload)), nil
		},
	}

	handler := ports.NewChatbotHandler(mockGateway, nil)
	router := gin.New()
	router.POST("/api/chat-ai/stream", handler.SendMessageStream)

	reqBody := domain.ChatbotRequest{Query: "ทักทาย"}
	bodyBytes, _ := json.Marshal(reqBody)
	req := httptest.NewRequest(http.MethodPost, "/api/chat-ai/stream", bytes.NewReader(bodyBytes))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
	assert.Equal(t, "text/event-stream", w.Header().Get("Content-Type"))
	assert.Contains(t, w.Body.String(), "event: delta")
	assert.Contains(t, w.Body.String(), "event: done")
}
