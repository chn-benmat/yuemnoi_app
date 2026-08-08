package domain

import "context"

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

// AIService defines the domain-facing contract for an AI provider.
type AIService interface {
	GetAIResponse(ctx context.Context, query string, history []ChatMessage) (map[string]interface{}, error)
}
