package domain

import (
	"context"
	"io"
)

// ChatMessage represents one message exchanged with the AI service.
type ChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// ChatRequest contains the query and conversation history accepted by the AI API.
type ChatRequest struct {
	Query   string        `json:"query" binding:"required"`
	History []ChatMessage `json:"history"`
}

// AIFeedbackRequest represents user feedback (Like/Dislike) on an AI response.
type AIFeedbackRequest struct {
	MessageID       string  `json:"message_id" binding:"required"`
	UserQuery       string  `json:"user_query" binding:"required"`
	AIResponse      string  `json:"ai_response" binding:"required"`
	Rating          int     `json:"rating" binding:"required"` // 1 = Thumbs Up, -1 = Thumbs Down
	ReasonCategory  *string `json:"reason_category,omitempty"`
	FeedbackComment *string `json:"feedback_comment,omitempty"`
	ResolvedMode    *string `json:"resolved_mode,omitempty"`
	UserID          *string `json:"user_id,omitempty"`
	SessionID       *string `json:"session_id,omitempty"`
}

// AIService defines the domain-facing contract for an AI provider.
type AIService interface {
	GetAIResponse(ctx context.Context, query string, history []ChatMessage) (map[string]interface{}, error)
	StreamAIResponse(ctx context.Context, query string, history []ChatMessage) (io.ReadCloser, error)
	SubmitFeedback(ctx context.Context, req AIFeedbackRequest) (map[string]interface{}, error)
}
