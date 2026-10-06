package tests

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/aiservice"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

// ใช้สัญญาชุดเดียวกับ Python และ Flutter ตรวจการส่งต่อ ไม่วัดความเข้าใจของโมเดล
func TestAIChatSharedContractThroughHandlerAndAdapter(t *testing.T) {
	raw, err := os.ReadFile("../../ai_service/tests/fixtures/chat_contract.json")
	require.NoError(t, err)
	var fixture struct {
		Request  domain.ChatbotRequest `json:"request"`
		Response json.RawMessage       `json:"response"`
		SSE      string                `json:"sse"`
	}
	require.NoError(t, json.Unmarshal(raw, &fixture))
	gin.SetMode(gin.TestMode)
	for _, stream := range []bool{false, true} {
		for _, answer := range []string{"choice", "text", "skip", "active", "legacy"} {
			name := answer
			if stream {
				name += "-stream"
			}
			t.Run(name, func(t *testing.T) {
				req := fixture.Request
				req.QuestionnaireAnswers = append([]domain.QuestionnaireAnswer{}, fixture.Request.QuestionnaireAnswers...)
				switch answer {
				case "active":
					questionID := req.Context.Questions[0].ID
					req.ActiveQuestionID = &questionID
					req.QuestionnaireAnswers = nil
					req.Query = "เปลี่ยนสินค้าแทนการตอบคำถามเดิม"
				case "text":
					text := "ริมน้ำที่ลมแรง"
					req.QuestionnaireAnswers[0].OptionID = nil
					req.QuestionnaireAnswers[0].Text = &text
				case "skip":
					req.QuestionnaireSkipped = true
				case "legacy":
					req.Context = nil
					req.SessionID = ""
					req.QuestionnaireAnswers = nil
				}
				upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					require.Equal(t, "fixture-key", r.Header.Get("X-Internal-Service-Key"))
					var forwarded domain.ChatbotRequest
					require.NoError(t, json.NewDecoder(r.Body).Decode(&forwarded))
					expectedContext, err := json.Marshal(req.Context)
					require.NoError(t, err)
					actualContext, err := json.Marshal(forwarded.Context)
					require.NoError(t, err)
					require.JSONEq(t, string(expectedContext), string(actualContext))
					require.Equal(t, req.QuestionnaireAnswers, forwarded.QuestionnaireAnswers)
					require.Equal(t, req.QuestionnaireSkipped, forwarded.QuestionnaireSkipped)
					require.Equal(t, req.SessionID, forwarded.SessionID)
					require.Equal(t, req.ActiveQuestionID, forwarded.ActiveQuestionID)
					if stream {
						require.Equal(t, "/api/v1/chat/stream", r.URL.Path)
						w.Header().Set("Content-Type", "text/event-stream")
						_, _ = io.WriteString(w, fixture.SSE)
					} else {
						require.Equal(t, "/api/v1/chat", r.URL.Path)
						w.Header().Set("Content-Type", "application/json")
						_, _ = w.Write(fixture.Response)
					}
				}))
				defer upstream.Close()
				client := aiservice.NewClient(upstream.URL, "fixture-key", time.Second)
				handler := ports.NewChatbotHandler(client, nil)
				router := gin.New()
				path := "/api/v1/chat-ai"
				if stream {
					path += "/stream"
					router.POST(path, handler.SendMessageStream)
				} else {
					router.POST(path, handler.SendMessage)
				}
				body, err := json.Marshal(req)
				require.NoError(t, err)
				request := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(body))
				request.Header.Set("Content-Type", "application/json")
				recorder := httptest.NewRecorder()
				router.ServeHTTP(recorder, request)
				require.Equal(t, http.StatusOK, recorder.Code)
				if stream {
					require.Equal(t, fixture.SSE, recorder.Body.String())
				} else {
					var response domain.ChatbotResponse
					require.NoError(t, json.Unmarshal(recorder.Body.Bytes(), &response))
					require.Equal(t, "fixture-session", response.Context.SessionID)
					require.Equal(t, "broad", *response.RequestScope)
					require.False(t, *response.InformationSufficient)
					require.Equal(t, "clarify", *response.NextAction)
					require.Equal(t, "general", *response.ResponseFlow)
					require.Len(t, response.Questions, 1)
					require.Equal(t, "location", response.Questions[0].Dimension)
					require.Equal(t, "outdoor", response.Questions[0].Choices[1].ID)
					require.Equal(t, response.Questions, response.Context.Questions)
					require.Empty(t, response.RecommendedItems)
					require.Empty(t, response.SuggestedReplies)
					require.NotEmpty(t, response.References)
					require.Equal(t, "rental.request_in_chat", response.References[0].ID)
				}
			})
		}
	}
}

func TestAIChatProviderFailureDoesNotExposeUpstreamBody(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
		_, _ = io.WriteString(w, "private-provider-details")
	}))
	defer upstream.Close()
	client := aiservice.NewClient(upstream.URL, "", time.Second)
	_, err := client.SendMessage(context.Background(), domain.ChatbotRequest{Query: "คำถาม"})
	require.Error(t, err)
	require.False(t, strings.Contains(err.Error(), "private-provider-details"))
	_, err = client.SendMessageStream(context.Background(), domain.ChatbotRequest{Query: "คำถาม"})
	require.Error(t, err)
	require.False(t, strings.Contains(err.Error(), "private-provider-details"))
}
