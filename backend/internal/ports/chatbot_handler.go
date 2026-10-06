package ports

import (
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gin-gonic/gin"
)

// รักษารหัสโควตาและเวลาลองใหม่ โดยไม่ส่งรายละเอียดจากระบบภายใน
func writeAIError(c *gin.Context, err error) {
	statusCode := http.StatusBadGateway
	code := "service_unavailable"
	var serviceErr *domain.AIServiceError
	if errors.As(err, &serviceErr) {
		code = serviceErr.Code
		if serviceErr.StatusCode == http.StatusServiceUnavailable || serviceErr.StatusCode == http.StatusTooManyRequests {
			statusCode = http.StatusServiceUnavailable
		}
		if serviceErr.RetryAfterSeconds != nil {
			c.Header("Retry-After", fmt.Sprint(*serviceErr.RetryAfterSeconds))
		}
	}
	c.JSON(statusCode, gin.H{"status": "error", "error_code": code, "error": "ผู้ช่วย AI ขัดข้องชั่วคราว กรุณาลองใหม่อีกครั้ง"})
}

// ChatbotHandler จัดการคำขอเกี่ยวกับ AI Chatbot จาก Flutter Client
type ChatbotHandler struct {
	gateway       domain.AIChatbotGateway
	tokenVerifier domain.TokenVerifier
}

// NewChatbotHandler สร้างอินสแตนซ์ของ ChatbotHandler
func NewChatbotHandler(
	gateway domain.AIChatbotGateway,
	tokenVerifier domain.TokenVerifier,
) *ChatbotHandler {
	return &ChatbotHandler{
		gateway:       gateway,
		tokenVerifier: tokenVerifier,
	}
}

// SendMessage รับข้อความคำถามจากผู้ใช้ และส่งต่อให้ AI Service เพื่อตอบกลับแบบสมบูรณ์รอบเดียว
func (h *ChatbotHandler) SendMessage(c *gin.Context) {
	var req domain.ChatbotRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "รูปแบบข้อมูลไม่ถูกต้อง"})
		return
	}

	effectiveMsg := strings.TrimSpace(req.EffectiveMessage())
	if effectiveMsg == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "กรุณาระบุข้อความคำถาม"})
		return
	}

	// เรียกใช้งาน Gateway ส่งคำขอไปยัง AI Service
	resp, err := h.gateway.SendMessage(c.Request.Context(), req)
	if err != nil {
		writeAIError(c, err)
		return
	}

	c.JSON(http.StatusOK, resp)
}

// SendMessageStream รับคำขอและสตรีมคำตอบของ AI กลับไปยัง Mobile Client แบบ Real-time SSE (Typewriter Effect)
func (h *ChatbotHandler) SendMessageStream(c *gin.Context) {
	var req domain.ChatbotRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "รูปแบบข้อมูลไม่ถูกต้อง"})
		return
	}

	effectiveMsg := strings.TrimSpace(req.EffectiveMessage())
	if effectiveMsg == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "กรุณาระบุข้อความคำถาม"})
		return
	}

	// เริ่มต้นการขอสตรีมจาก AI Service
	streamBody, err := h.gateway.SendMessageStream(c.Request.Context(), req)
	if err != nil {
		writeAIError(c, err)
		return
	}
	defer streamBody.Close()

	// ตั้งค่า Headers สำหรับ Server-Sent Events (SSE)
	c.Writer.Header().Set("Content-Type", "text/event-stream")
	c.Writer.Header().Set("Cache-Control", "no-cache")
	c.Writer.Header().Set("Connection", "keep-alive")
	c.Writer.Header().Set("Transfer-Encoding", "chunked")
	c.Writer.Header().Set("X-Accel-Buffering", "no")
	c.Writer.WriteHeader(http.StatusOK)

	flusher, hasFlusher := c.Writer.(http.Flusher)
	if hasFlusher {
		flusher.Flush()
	}

	// อ่านและส่งต่อสตรีมทีละ Chunk ไปยัง Client ทันที
	buf := make([]byte, 1024)
	for {
		select {
		case <-c.Request.Context().Done():
			// Client ยกเลิกการเชื่อมต่อ หรือปิดหน้าแอป
			return
		default:
		}

		n, readErr := streamBody.Read(buf)
		if n > 0 {
			if _, writeErr := c.Writer.Write(buf[:n]); writeErr != nil {
				return
			}
			if hasFlusher {
				flusher.Flush()
			}
		}

		if readErr != nil {
			if readErr != io.EOF {
				// ส่ง Event แจ้งเตือนข้อผิดพลาดถ้าสตรีมขาดช่วงกะทันหัน
				_, _ = fmt.Fprintf(c.Writer, "event: error\ndata: {\"error_code\": \"stream_interrupted\"}\n\n")
				if hasFlusher {
					flusher.Flush()
				}
			}
			break
		}
	}
}
