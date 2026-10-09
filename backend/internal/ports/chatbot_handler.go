package ports

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
)

// รักษารหัสโควตาและเวลาลองใหม่ โดยไม่ส่งรายละเอียดจากระบบภายใน
func writeAIError(c fiber.Ctx, err error) error {
	statusCode := http.StatusBadGateway
	code := "service_unavailable"
	var serviceErr *domain.AIServiceError
	if errors.As(err, &serviceErr) {
		code = serviceErr.Code
		if serviceErr.StatusCode == http.StatusServiceUnavailable || serviceErr.StatusCode == http.StatusTooManyRequests {
			statusCode = http.StatusServiceUnavailable
		}
		if serviceErr.RetryAfterSeconds != nil {
			c.Set("Retry-After", fmt.Sprint(*serviceErr.RetryAfterSeconds))
		}
	}
	return c.Status(statusCode).JSON(fiber.Map{"status": "error", "error_code": code, "error": "ยืมหน่อย AI ขัดข้องชั่วคราว กรุณาลองใหม่อีกครั้ง"})
}

// ChatbotHandler รับคำขอ AI และส่งต่อผ่าน domain gateway
type ChatbotHandler struct {
	gateway       domain.AIChatbotGateway
	tokenVerifier domain.TokenVerifier
}

func NewChatbotHandler(gateway domain.AIChatbotGateway, tokenVerifier domain.TokenVerifier) *ChatbotHandler {
	return &ChatbotHandler{gateway: gateway, tokenVerifier: tokenVerifier}
}

func (h *ChatbotHandler) SendMessage(c fiber.Ctx) error {
	var req domain.ChatbotRequest
	if err := c.Bind().JSON(&req); err != nil {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "รูปแบบข้อมูลไม่ถูกต้อง"})
	}
	if strings.TrimSpace(req.EffectiveMessage()) == "" {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "กรุณาระบุข้อความคำถาม"})
	}
	resp, err := h.gateway.SendMessage(c.Context(), req)
	if err != nil {
		return writeAIError(c, err)
	}
	return c.JSON(resp)
}

func (h *ChatbotHandler) SendMessageStream(c fiber.Ctx) error {
	var req domain.ChatbotRequest
	if err := c.Bind().JSON(&req); err != nil {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "รูปแบบข้อมูลไม่ถูกต้อง"})
	}
	if strings.TrimSpace(req.EffectiveMessage()) == "" {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "กรุณาระบุข้อความคำถาม"})
	}

	// สตรีมมีอายุเกิน handler จึงให้ callback เป็นเจ้าของ context และการปิด upstream
	ctx, cancel := context.WithCancel(c.Context())
	if timeout := c.App().Config().WriteTimeout; timeout > 0 {
		cancel()
		ctx, cancel = context.WithTimeout(c.Context(), timeout)
	}
	stopShutdown := func() bool { return false }
	if shutdown, ok := ctx.Value(streamShutdownKey{}).(context.Context); ok {
		stopShutdown = context.AfterFunc(shutdown, cancel)
	}
	streamBody, err := h.gateway.SendMessageStream(ctx, req)
	if err != nil {
		stopShutdown()
		cancel()
		return writeAIError(c, err)
	}

	c.Set("Content-Type", "text/event-stream")
	c.Set("Cache-Control", "no-cache")
	c.Set("Connection", "keep-alive")
	c.Set("X-Accel-Buffering", "no")
	c.Response().ImmediateHeaderFlush = true
	return c.SendStreamWriter(func(writer *bufio.Writer) {
		defer func() {
			stopShutdown()
			cancel()
			_ = streamBody.Close()
			if release, ok := ctx.Value(requestCancelKey{}).(context.CancelFunc); ok {
				release()
			}
		}()
		forwardAIStream(ctx, writer, streamBody)
	})
}

type streamChunk struct {
	data []byte
	err  error
}

func forwardAIStream(ctx context.Context, writer *bufio.Writer, body io.Reader) {
	chunks := make(chan streamChunk, 1)
	go func() {
		for {
			buf := make([]byte, 1024)
			n, err := body.Read(buf)
			select {
			case chunks <- streamChunk{data: buf[:n], err: err}:
			case <-ctx.Done():
				return
			}
			if err != nil {
				return
			}
		}
	}()

	// SSE comments ตรวจการตัดการเชื่อมต่อระหว่างรอ upstream โดยไม่สร้างสถานะ AI ปลอม
	heartbeat := time.NewTicker(time.Second)
	defer heartbeat.Stop()
	atEventBoundary := true
	var tail string
	for {
		select {
		case <-ctx.Done():
			return
		case <-heartbeat.C:
			// ห้ามแทรก comment กลาง event ที่ upstream ส่งมาไม่ครบ
			if !atEventBoundary {
				continue
			}
			if _, err := writer.WriteString(": keep-alive\n\n"); err != nil {
				return
			}
			if err := writer.Flush(); err != nil {
				return
			}
		case chunk := <-chunks:
			if len(chunk.data) > 0 {
				tail += string(chunk.data)
				if len(tail) > 4 {
					tail = tail[len(tail)-4:]
				}
				atEventBoundary = strings.HasSuffix(tail, "\n\n") || strings.HasSuffix(tail, "\r\n\r\n")
				if _, err := writer.Write(chunk.data); err != nil {
					return
				}
				if err := writer.Flush(); err != nil {
					return
				}
			}
			if chunk.err != nil {
				if !errors.Is(chunk.err, io.EOF) {
					_, _ = writer.WriteString("event: error\ndata: {\"error_code\": \"stream_interrupted\"}\n\n")
					_ = writer.Flush()
				}
				return
			}
		}
	}
}
