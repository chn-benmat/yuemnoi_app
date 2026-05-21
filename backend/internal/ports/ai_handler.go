package ports

import (
	"net/http"

	"github.com/Chanachai04/yuemnoi_app/backend/internal/adapters/service"
	"github.com/gin-gonic/gin"
)

type AIHandler struct {
	aiService *service.AIService
}

func NewAIHandler(aiService *service.AIService) *AIHandler {
	return &AIHandler{aiService: aiService}
}

// ChatRequest ปรับให้ตรงสเปกโครงสร้างข้อมูลที่ยิงมาจาก Postman หรือ Frontend
type ChatRequest struct {
	Query   string                `json:"query" binding:"required"`
	History []service.ChatMessage `json:"history"` // ดึง Struct ChatMessage มาจากแพ็กเกจ service
}

// [POST] /api/v1/chat-ai - รับข้อความจากผู้ใช้และส่งต่อไปยัง AI Service
func (h *AIHandler) HandleChat(c *gin.Context) {
	var req ChatRequest
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
