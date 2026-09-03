package service

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

// aiService is the HTTP adapter for the domain AIService contract.
type aiService struct {
	baseURL    string
	httpClient *http.Client
}

// NewAIService creates an HTTP-backed implementation of domain.AIService.
func NewAIService(baseURL string) domain.AIService {
	return &aiService{
		baseURL: baseURL,
		httpClient: &http.Client{
			// ตั้งค่า Timeout รวมป้องกันไม่ให้ระบบค้างหาก AI Service ไม่ตอบกลับ
			Timeout: 60 * time.Second,
			Transport: &http.Transport{
				MaxIdleConns:        100,
				MaxIdleConnsPerHost: 20,
				IdleConnTimeout:     90 * time.Second,
			},
		},
	}
}

// GetAIResponse ส่งคำถามและประวัติการคุยไปยัง AI Service และรับผลลัพธ์กลับมา
func (s *aiService) GetAIResponse(ctx context.Context, query string, history []domain.ChatMessage) (map[string]interface{}, error) {
	url := fmt.Sprintf("%s/api/ai/chat", s.baseURL)

	// สร้าง Payload ตาม Schema ที่ FastAPI กำหนด
	reqPayload := domain.ChatRequest{
		Query:   query,
		History: history,
	}

	// แปลง Payload เป็น JSON Byte
	jsonData, err := json.Marshal(reqPayload)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request payload: %w", err)
	}

	// สร้าง HTTP Request พร้อมผูกกับ context.Context
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create http request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to send request to ai service: %w", err)
	}
	defer resp.Body.Close()

	//ตรวจสอบ HTTP Status Code
	if resp.StatusCode != http.StatusOK {
		// Decode Error Message จาก FastAPI เพิ่มเติมตรงนี้ได้
		return nil, fmt.Errorf("ai service returned non-200 status: %d", resp.StatusCode)
	}

	// ผลลัพธ์ (Decode Response)
	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode ai service response: %w", err)
	}

	return result, nil
}
