package aiservice

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

// อ่านเฉพาะรหัสตามสัญญา ไม่เปิดเผย body หรือ header ที่มีข้อมูลลับ
func serviceError(resp *http.Response) error {
	failure := &domain.AIServiceError{StatusCode: resp.StatusCode, Code: "service_unavailable"}
	var payload struct {
		Detail struct {
			Code string `json:"error_code"`
		} `json:"detail"`
	}
	if json.NewDecoder(io.LimitReader(resp.Body, 16384)).Decode(&payload) == nil {
		switch payload.Detail.Code {
		case "providers_rate_limited", "quota_temporarily_unavailable", "quota_exhausted", "providers_busy", "review_unavailable", "structured_output_invalid", "response_quality_rejected", "timeout", "deadline_exceeded", "providers_exhausted", "request_budget_exceeded", "logical_call_budget_exceeded", "catalog_unavailable", "knowledge_unavailable", "processing_failed":
			failure.Code = payload.Detail.Code
		}
	}
	if seconds, err := strconv.Atoi(resp.Header.Get("Retry-After")); err == nil && seconds >= 0 {
		failure.RetryAfterSeconds = &seconds
	}
	return failure
}

// Client ทำหน้าที่เป็น HTTP Adapter ในการเชื่อมต่อไปยัง Python FastAPI AI Service
type Client struct {
	baseURL     string
	internalKey string
	httpClient  *http.Client
}

// NewClient สร้างอินสแตนซ์ใหม่สำหรับติดต่อกับ AI Service
func NewClient(baseURL string, internalKey string, timeout time.Duration) *Client {
	cleanURL := strings.TrimRight(strings.TrimSpace(baseURL), "/")
	if timeout <= 0 {
		timeout = 60 * time.Second
	}

	return &Client{
		baseURL:     cleanURL,
		internalKey: strings.TrimSpace(internalKey),
		httpClient: &http.Client{
			Timeout: timeout,
		},
	}
}

// aiChatRequestDTO โครงสร้าง Request ที่ส่งไปยัง AI Service (FastAPI)
type aiChatRequestDTO struct {
	Message              string                       `json:"message"`
	Query                string                       `json:"query"`
	SessionID            string                       `json:"session_id,omitempty"`
	History              []domain.ChatMessageItem     `json:"history,omitempty"`
	Context              *domain.ChatSessionContext   `json:"context,omitempty"`
	QuestionnaireAnswers []domain.QuestionnaireAnswer `json:"questionnaire_answers,omitempty"`
	QuestionnaireSkipped bool                         `json:"questionnaire_skipped,omitempty"`
	ActiveQuestionID     *string                      `json:"active_question_id,omitempty"`
}

// aiChoiceOptionDTO โครงสร้างตัวเลือกสำหรับคำถามถามกลับ
type aiChoiceOptionDTO struct {
	ID          string `json:"id"`
	Label       string `json:"label"`
	Description string `json:"description"`
	ActionValue string `json:"action_value"`
}

// aiQuestionStepDTO โครงสร้างขั้นตอนคำถามพร้อมระบบ Adaptive Branching
type aiQuestionStepDTO struct {
	Dimension        string                             `json:"dimension"`
	Choices          []domain.QuestionChoice            `json:"choices"`
	ID               string                             `json:"id"`
	Title            string                             `json:"title"`
	Options          []string                           `json:"options"`
	Step             int                                `json:"step"`
	TotalSteps       int                                `json:"total_steps"`
	BranchTitles     map[string]string                  `json:"branch_titles,omitempty"`
	BranchOptions    map[string][]string                `json:"branch_options,omitempty"`
	BranchQuestionID *string                            `json:"branch_question_id,omitempty"`
	BranchChoices    map[string][]domain.QuestionChoice `json:"branch_choices,omitempty"`
}

// aiClarificationDTO โครงสร้างคำถามถามกลับเมื่อข้อมูลไม่ชัดเจน
type aiClarificationDTO struct {
	Question         string              `json:"question"`
	MissingDimension string              `json:"missing_dimension"`
	Options          []aiChoiceOptionDTO `json:"options"`
	Questions        []aiQuestionStepDTO `json:"questions"`
}

// aiItemDTO โครงสร้างข้อมูลสินค้าจาก AI Service
type aiItemDTO struct {
	PriceDisplay  string   `json:"price_display"`
	UnitDisplay   string   `json:"unit_display"`
	StatusDisplay string   `json:"status_display"`
	ID            string   `json:"id"`
	Name          string   `json:"name"`
	ItemName      string   `json:"item_name"`
	Category      string   `json:"category"`
	Price         float64  `json:"price"`
	Type          string   `json:"type"`
	Unit          string   `json:"unit"`
	PriceUnit     string   `json:"price_unit"`
	Status        string   `json:"status"`
	ImageURLs     []string `json:"image_urls"`
	ImageURL      string   `json:"image_url"`
	Description   string   `json:"description"`
}

// aiSearchSourceDTO โครงสร้างข้อมูลแหล่งอ้างอิงจาก AI Service
type aiSearchSourceDTO struct {
	Title   string `json:"title"`
	Link    string `json:"link"`
	URL     string `json:"url"`
	Domain  string `json:"domain"`
	Snippet string `json:"snippet"`
}

// aiChatResponseDTO โครงสร้าง Response ที่ได้รับกลับมาจาก FastAPI
type aiChatResponseDTO struct {
	RequestScope          *string                    `json:"request_scope"`
	InformationSufficient *bool                      `json:"information_sufficient"`
	NextAction            *string                    `json:"next_action"`
	ResponseFlow          *string                    `json:"response_flow"`
	ResponseKind          *string                    `json:"response_kind"`
	Context               *domain.ChatSessionContext `json:"context"`
	References            []domain.EvidenceReference `json:"references"`
	SuggestedReplies      []string                   `json:"suggested_replies"`
	Response              string                     `json:"response"`
	Intent                string                     `json:"intent"`
	Confidence            float64                    `json:"confidence"`
	AmbiguityLevel        float64                    `json:"ambiguity_level"`
	Clarification         *aiClarificationDTO        `json:"clarification"`
	Questions             []aiQuestionStepDTO        `json:"questions"`
	Items                 []aiItemDTO                `json:"items"`
	SearchQuery           string                     `json:"search_query"`
	SearchSources         []aiSearchSourceDTO        `json:"search_sources"`
}

// SendMessage ส่งข้อความเพื่อรับคำตอบแบบสมบูรณ์รอบเดียว (Non-Streaming)
func (c *Client) SendMessage(ctx context.Context, req domain.ChatbotRequest) (*domain.ChatbotResponse, error) {
	effectiveMsg := req.EffectiveMessage()
	if strings.TrimSpace(effectiveMsg) == "" {
		return nil, fmt.Errorf("message cannot be empty")
	}

	payload := aiChatRequestDTO{
		Message:              effectiveMsg,
		Query:                effectiveMsg,
		SessionID:            req.SessionID,
		History:              req.History,
		Context:              req.Context,
		QuestionnaireAnswers: req.QuestionnaireAnswers,
		QuestionnaireSkipped: req.QuestionnaireSkipped,
		ActiveQuestionID:     req.ActiveQuestionID,
	}

	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("marshal request error: %w", err)
	}

	targetURL := fmt.Sprintf("%s/api/chat", c.baseURL)
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, targetURL, bytes.NewReader(bodyBytes))
	if err != nil {
		return nil, fmt.Errorf("create http request error: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Accept", "application/json")
	if c.internalKey != "" {
		httpReq.Header.Set("X-Internal-Service-Key", c.internalKey)
	}

	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("call ai service error: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, serviceError(resp)
	}

	var aiResp aiChatResponseDTO
	if err := json.NewDecoder(resp.Body).Decode(&aiResp); err != nil {
		return nil, fmt.Errorf("decode ai response error: %w", err)
	}

	// แปลงข้อมูลจาก DTO ภายในของ AI Service ให้เป็น Domain Response ที่สอดคล้องกับ Mobile Client
	recommended := make([]domain.RecommendedItem, 0, len(aiResp.Items))
	for _, it := range aiResp.Items {
		name := it.Name
		if name == "" {
			name = it.ItemName
		}
		imgURL := it.ImageURL
		if imgURL == "" && len(it.ImageURLs) > 0 {
			imgURL = it.ImageURLs[0]
		}
		unit := it.PriceUnit
		if unit == "" {
			unit = it.Unit
		}
		if unit == "" {
			unit = it.Type
		}
		recommended = append(recommended, domain.RecommendedItem{
			PriceDisplay:  it.PriceDisplay,
			UnitDisplay:   it.UnitDisplay,
			StatusDisplay: it.StatusDisplay,
			ID:            it.ID,
			Name:          name,
			ItemName:      name,
			Category:      it.Category,
			Price:         it.Price,
			PriceUnit:     unit,
			Unit:          unit,
			Status:        it.Status,
			ImageURL:      imgURL,
			Description:   it.Description,
		})
	}

	var questions []domain.ClarificationQuestion
	suggestedReplies := append([]string{}, aiResp.SuggestedReplies...)
	rawQuestions := aiResp.Questions
	if len(rawQuestions) == 0 && aiResp.Clarification != nil {
		rawQuestions = aiResp.Clarification.Questions
	}

	if len(rawQuestions) > 0 {
		for _, q := range rawQuestions {
			questions = append(questions, domain.ClarificationQuestion{
				ID:               q.ID,
				Dimension:        q.Dimension,
				Choices:          q.Choices,
				Title:            q.Title,
				Options:          q.Options,
				Step:             q.Step,
				TotalSteps:       q.TotalSteps,
				BranchTitles:     q.BranchTitles,
				BranchOptions:    q.BranchOptions,
				BranchQuestionID: q.BranchQuestionID,
				BranchChoices:    q.BranchChoices,
			})
		}
		if len(questions) > 0 && len(suggestedReplies) == 0 && aiResp.Context == nil {
			suggestedReplies = append(suggestedReplies, questions[0].Options...)
		}
	} else if aiResp.Clarification != nil && aiResp.Clarification.Question != "" {
		opts := make([]string, 0, len(aiResp.Clarification.Options))
		for _, opt := range aiResp.Clarification.Options {
			opts = append(opts, opt.Label)
			suggestedReplies = append(suggestedReplies, opt.Label)
		}
		questions = append(questions, domain.ClarificationQuestion{
			ID:         "clarification-1",
			Title:      aiResp.Clarification.Question,
			Options:    opts,
			Step:       1,
			TotalSteps: 1,
		})
	}

	sources := make([]domain.SearchSource, 0, len(aiResp.SearchSources))
	for _, s := range aiResp.SearchSources {
		targetURL := s.URL
		if targetURL == "" {
			targetURL = s.Link
		}
		sources = append(sources, domain.SearchSource{
			Title:   s.Title,
			URL:     targetURL,
			Domain:  s.Domain,
			Snippet: s.Snippet,
		})
	}

	return &domain.ChatbotResponse{
		RequestScope:          aiResp.RequestScope,
		InformationSufficient: aiResp.InformationSufficient,
		NextAction:            aiResp.NextAction,
		ResponseFlow:          aiResp.ResponseFlow,
		ResponseKind:          aiResp.ResponseKind,
		Status:                "success",
		Answer:                aiResp.Response,
		RecommendedItems:      recommended,
		Questions:             questions,
		SuggestedReplies:      suggestedReplies,
		SearchQuery:           aiResp.SearchQuery,
		SearchSources:         sources,
		Context:               aiResp.Context,
		References:            aiResp.References,
	}, nil
}

// SendMessageStream ส่งคำขอไปยัง AI Service เพื่อรับ Server-Sent Events (SSE) Stream
func (c *Client) SendMessageStream(ctx context.Context, req domain.ChatbotRequest) (io.ReadCloser, error) {
	effectiveMsg := req.EffectiveMessage()
	if strings.TrimSpace(effectiveMsg) == "" {
		return nil, fmt.Errorf("message cannot be empty")
	}

	payload := aiChatRequestDTO{
		Message:              effectiveMsg,
		Query:                effectiveMsg,
		SessionID:            req.SessionID,
		History:              req.History,
		Context:              req.Context,
		QuestionnaireAnswers: req.QuestionnaireAnswers,
		QuestionnaireSkipped: req.QuestionnaireSkipped,
		ActiveQuestionID:     req.ActiveQuestionID,
	}

	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("marshal stream request error: %w", err)
	}

	targetURL := fmt.Sprintf("%s/api/chat/stream", c.baseURL)
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, targetURL, bytes.NewReader(bodyBytes))
	if err != nil {
		return nil, fmt.Errorf("create stream http request error: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Accept", "text/event-stream")
	if c.internalKey != "" {
		httpReq.Header.Set("X-Internal-Service-Key", c.internalKey)
	}

	// ใช้ Client พร้อม Timeout สำหรับการสตรีม ป้องกัน Goroutine แขวนค้าง
	resp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("call ai service stream error: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		err := serviceError(resp)
		_ = resp.Body.Close()
		return nil, err
	}

	return resp.Body, nil
}
