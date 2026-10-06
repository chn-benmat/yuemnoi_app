package tests

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/aiservice"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/stretchr/testify/require"
)

// ตรวจ JSON และ SSE ส่งชนิดเดียวกัน โดยยังรับคำตอบรุ่นเก่าที่ไม่มีฟิลด์ได้
func TestAIResponseKindAndCanonicalDisplaySurviveGateway(t *testing.T) {
	for _, kind := range []string{"", "clarification", "conversation", "information", "overview", "recommendation", "item_details", "comparison", "technical", "app_information"} {
		t.Run(kind, func(t *testing.T) {
			payload := map[string]any{"response": "ข้อความจริง", "items": []map[string]any{{
				"id": "fixture", "name": "fixture", "price": 650.5, "type": "daily", "status": "available",
				"price_display": "650.5 บาทต่อวัน", "unit_display": "วัน", "status_display": "มีในคลัง"}}}
			if kind != "" {
				payload["response_kind"] = kind
			}
			raw, err := json.Marshal(payload)
			require.NoError(t, err)
			wire := "event: ready\ndata: " + string(raw) + "\n\nevent: metadata\ndata: " + string(raw) + "\n\nevent: done\ndata: " + string(raw) + "\n\n"
			upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.URL.Path == "/api/v1/chat/stream" {
					w.Header().Set("Content-Type", "text/event-stream")
					_, _ = io.WriteString(w, wire)
				} else {
					w.Header().Set("Content-Type", "application/json")
					_, _ = w.Write(raw)
				}
			}))
			defer upstream.Close()
			client := aiservice.NewClient(upstream.URL, "", time.Second)
			response, err := client.SendMessage(context.Background(), domain.ChatbotRequest{Query: "fixture"})
			require.NoError(t, err)
			if kind == "" {
				require.Nil(t, response.ResponseKind)
			} else {
				require.Equal(t, kind, *response.ResponseKind)
			}
			require.Equal(t, 650.5, response.RecommendedItems[0].Price)
			require.Equal(t, "daily", response.RecommendedItems[0].PriceUnit)
			require.Equal(t, "650.5 บาทต่อวัน", response.RecommendedItems[0].PriceDisplay)
			require.Equal(t, "วัน", response.RecommendedItems[0].UnitDisplay)
			require.Equal(t, "มีในคลัง", response.RecommendedItems[0].StatusDisplay)
			stream, err := client.SendMessageStream(context.Background(), domain.ChatbotRequest{Query: "fixture"})
			require.NoError(t, err)
			defer stream.Close()
			forwarded, err := io.ReadAll(stream)
			require.NoError(t, err)
			require.Equal(t, wire, string(forwarded))
		})
	}
}
