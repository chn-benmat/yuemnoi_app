package ports

import (
	"net/http"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gin-gonic/gin"
)

type AIHandler struct {
	aiService domain.AIService
}

func NewAIHandler(aiService domain.AIService) *AIHandler {
	return &AIHandler{aiService: aiService}
}

// [POST] /api/v1/chat-ai - รับข้อความจากผู้ใช้และส่งต่อไปยัง AI Service
func (h *AIHandler) HandleChat(c *gin.Context) {
	var req domain.ChatRequest
	// 1. ตรวจสอบและถอดรหัส JSON Payload จาก HTTP Request
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request payload: " + err.Error()})
		return
	}

	ctx := c.Request.Context()

	// 2. เรียกใช้งานฟังก์ชันที่แท้จริงใน ai_service.go (GetAIResponse) พร้อมส่ง Context, Query และ History
	response, err := h.aiService.GetAIResponse(ctx, req.Query, req.History)
	if err != nil {
		// ส่งข้อความ Error กลับไปแจ้งฝูงผู้ใช้หากติดต่อ Python API หรือประมวลผลโมเดลล้มเหลว
		c.JSON(http.StatusInternalServerError, gin.H{"error": "AI service failed: " + err.Error()})
		return
	}

	// 3. ส่งผลลัพธ์ (Response) ที่ได้จาก Python API กลับไปให้ผู้ใช้ตรงๆ
	c.JSON(http.StatusOK, response)
}

// [POST] /api/v1/chat-ai/stream - สตรีมข้อความ SSE จาก AI Service ส่งต่อไปยังผู้ใช้แบบพิมพ์ดีด
func (h *AIHandler) HandleStreamChat(c *gin.Context) {
	var req domain.ChatRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request payload: " + err.Error()})
		return
	}

	ctx := c.Request.Context()
	stream, err := h.aiService.StreamAIResponse(ctx, req.Query, req.History)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "AI stream failed: " + err.Error()})
		return
	}
	defer stream.Close()

	c.Writer.Header().Set("Content-Type", "text/event-stream")
	c.Writer.Header().Set("Cache-Control", "no-cache")
	c.Writer.Header().Set("Connection", "keep-alive")
	c.Writer.Header().Set("X-Accel-Buffering", "no")
	c.Writer.WriteHeader(http.StatusOK)
	c.Writer.Flush()

	buf := make([]byte, 1024)
	for {
		select {
		case <-ctx.Done():
			return
		default:
			n, err := stream.Read(buf)
			if n > 0 {
				if _, writeErr := c.Writer.Write(buf[:n]); writeErr != nil {
					return
				}
				c.Writer.Flush()
			}
			if err != nil {
				return
			}
		}
	}
}

// [POST] /api/v1/chat-ai/feedback - รับฟีดแบ็กความพึงพอใจ (ถูกใจ / ไม่ถูกใจ) จากผู้ใช้
func (h *AIHandler) HandleFeedback(c *gin.Context) {
	var req domain.AIFeedbackRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid feedback payload: " + err.Error()})
		return
	}

	if userIDVal, exists := c.Get("user_id"); exists {
		if uidStr, ok := userIDVal.(string); ok && uidStr != "" {
			req.UserID = &uidStr
		}
	}

	ctx := c.Request.Context()
	result, err := h.aiService.SubmitFeedback(ctx, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to submit feedback: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, result)
}
