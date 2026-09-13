package aiservice

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

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
	Message   string                   `json:"message"`
	Query     string                   `json:"query"`
	SessionID string                   `json:"session_id,omitempty"`
	History   []domain.ChatMessageItem `json:"history"`
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
	ID            string              `json:"id"`
	Title         string              `json:"title"`
	Options       []string            `json:"options"`
	Step          int                 `json:"step"`
	TotalSteps    int                 `json:"total_steps"`
	BranchTitles  map[string]string   `json:"branch_titles,omitempty"`
	BranchOptions map[string][]string `json:"branch_options,omitempty"`
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
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	Category    string   `json:"category"`
	Price       float64  `json:"price"`
	Type        string   `json:"type"`
	Status      string   `json:"status"`
	ImageURLs   []string `json:"image_urls"`
	Description string   `json:"description"`
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
	Response       string              `json:"response"`
	Intent         string              `json:"intent"`
	Confidence     float64             `json:"confidence"`
	AmbiguityLevel float64             `json:"ambiguity_level"`
	Clarification  *aiClarificationDTO `json:"clarification"`
	Questions      []aiQuestionStepDTO `json:"questions"`
	Items          []aiItemDTO         `json:"items"`
	SearchQuery    string              `json:"search_query"`
	SearchSources  []aiSearchSourceDTO `json:"search_sources"`
}

// SendMessage ส่งข้อความเพื่อรับคำตอบแบบสมบูรณ์รอบเดียว (Non-Streaming)
func (c *Client) SendMessage(ctx context.Context, req domain.ChatbotRequest) (*domain.ChatbotResponse, error) {
	effectiveMsg := req.EffectiveMessage()
	if strings.TrimSpace(effectiveMsg) == "" {
		return nil, fmt.Errorf("message cannot be empty")
	}

	payload := aiChatRequestDTO{
		Message:   effectiveMsg,
		Query:     effectiveMsg,
		SessionID: req.SessionID,
		History:   req.History,
	}

	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("marshal request error: %w", err)
	}

	targetURL := fmt.Sprintf("%s/api/v1/chat", c.baseURL)
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
		respBody, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("ai service returned status %d: %s", resp.StatusCode, string(respBody))
	}

	var aiResp aiChatResponseDTO
	if err := json.NewDecoder(resp.Body).Decode(&aiResp); err != nil {
		return nil, fmt.Errorf("decode ai response error: %w", err)
	}

	// แปลงข้อมูลจาก DTO ภายในของ AI Service ให้เป็น Domain Response ที่สอดคล้องกับ Mobile Client
	recommended := make([]domain.RecommendedItem, 0, len(aiResp.Items))
	for _, it := range aiResp.Items {
		imgURL := ""
		if len(it.ImageURLs) > 0 {
			imgURL = it.ImageURLs[0]
		}
		recommended = append(recommended, domain.RecommendedItem{
			ID:          it.ID,
			Name:        it.Name,
			Category:    it.Category,
			Price:       it.Price,
			PriceUnit:   it.Type,
			Status:      it.Status,
			ImageURL:    imgURL,
			Description: it.Description,
		})
	}

	var questions []domain.ClarificationQuestion
	suggestedReplies := make([]string, 0)
	rawQuestions := aiResp.Questions
	if len(rawQuestions) == 0 && aiResp.Clarification != nil {
		rawQuestions = aiResp.Clarification.Questions
	}

	if len(rawQuestions) > 0 {
		for _, q := range rawQuestions {
			questions = append(questions, domain.ClarificationQuestion{
				ID:            q.ID,
				Title:         q.Title,
				Options:       q.Options,
				Step:          q.Step,
				TotalSteps:    q.TotalSteps,
				BranchTitles:  q.BranchTitles,
				BranchOptions: q.BranchOptions,
			})
		}
		if len(questions) > 0 {
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
		Status:           "success",
		Answer:           aiResp.Response,
		RecommendedItems: recommended,
		Questions:        questions,
		SuggestedReplies: suggestedReplies,
		SearchQuery:      aiResp.SearchQuery,
		SearchSources:    sources,
	}, nil
}

// SendMessageStream ส่งคำขอไปยัง AI Service เพื่อรับ Server-Sent Events (SSE) Stream
func (c *Client) SendMessageStream(ctx context.Context, req domain.ChatbotRequest) (io.ReadCloser, error) {
	effectiveMsg := req.EffectiveMessage()
	if strings.TrimSpace(effectiveMsg) == "" {
		return nil, fmt.Errorf("message cannot be empty")
	}

	payload := aiChatRequestDTO{
		Message:   effectiveMsg,
		Query:     effectiveMsg,
		SessionID: req.SessionID,
		History:   req.History,
	}

	bodyBytes, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("marshal stream request error: %w", err)
	}

	targetURL := fmt.Sprintf("%s/api/v1/chat/stream", c.baseURL)
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
	streamClient := &http.Client{
		Timeout: 3 * time.Minute,
	}
	resp, err := streamClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("call ai service stream error: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		respBody, _ := io.ReadAll(resp.Body)
		_ = resp.Body.Close()
		return nil, fmt.Errorf("ai service stream returned status %d: %s", resp.StatusCode, string(respBody))
	}

	return resp.Body, nil
}
