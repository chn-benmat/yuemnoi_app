package ports

import (
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/gofiber/fiber/v3"
)

const maxLoggedResponseChars = 16 * 1024

var sensitiveLogKeyFragments = []string{
	"authorization",
	"password",
	"token",
	"otp",
	"secret",
	"api_key",
	"apikey",
	"email",
	"phone",
	"full_name",
	"fullname",
	"display_name",
	"displayname",
	"user_id",
	"userid",
	"user_image",
	"profile_image",
	"owner_id",
	"ownerid",
	"latitude",
	"longitude",
	"address",
	"service_role",
	"supabase_key",
	"serper_api",
}

// บันทึกเฉพาะข้อมูลการรับส่งคำขอ โดยไม่เก็บ headers, query หรือข้อมูลส่วนตัวใน body
func accessLoggingMiddleware() fiber.Handler {
	return func(c fiber.Ctx) error {
		start := time.Now()
		err := c.Next()
		status := c.Response().StatusCode()
		if err != nil {
			status = fiber.StatusInternalServerError
			var httpErr *fiber.Error
			if errors.As(err, &httpErr) {
				status = httpErr.Code
				if status == fiber.StatusMethodNotAllowed {
					status = fiber.StatusNotFound
				}
			}
		}
		slog.InfoContext(c.Context(), "http_request",
			slog.String("method", c.Method()), slog.String("path", c.Path()),
			slog.Int("status", status), slog.Int64("latency_ms", time.Since(start).Milliseconds()))
		return err
	}
}

// ResponseLoggingMiddleware บันทึก Structured Log ของ API Response โดยปกปิดข้อมูลที่มีความอ่อนไหว (PII / Secrets) อัตโนมัติ
func ResponseLoggingMiddleware() fiber.Handler {
	return func(c fiber.Ctx) error {
		start := time.Now()
		err := c.Next()
		// ไม่อ่าน body stream เพื่อคงการส่งข้อมูลทันทีและไม่เก็บข้อความสนทนาใน log
		body := "<stream omitted>"
		if strings.HasPrefix(c.Path(), "/api/identity/") || strings.HasPrefix(c.Path(), "/api/admin/") {
			body = "<identity data omitted>"
		} else if !c.Response().IsBodyStream() {
			body = safeBodyForLog(c.Response().Body())
		}

		slog.InfoContext(
			c.Context(),
			"api_response",
			slog.String("method", c.Method()),
			slog.String("path", c.Path()),
			slog.Int("status", c.Response().StatusCode()),
			slog.Int64("latency_ms", time.Since(start).Milliseconds()),
			slog.String("body", body),
		)
		return err
	}
}

func responseLoggingMiddleware() fiber.Handler {
	return ResponseLoggingMiddleware()
}

func safeBodyForLog(body []byte) string {
	if len(body) == 0 {
		return "<empty>"
	}

	var payload any
	if err := json.Unmarshal(body, &payload); err != nil {
		return fmt.Sprintf("<non-JSON body omitted: %d bytes>", len(body))
	}

	redactSensitiveLogValues(payload)
	redactedBody, err := json.Marshal(payload)
	if err != nil {
		return fmt.Sprintf("<JSON body omitted: %d bytes>", len(body))
	}

	redactedText := string(redactedBody)
	redactedRunes := []rune(redactedText)
	if len(redactedRunes) > maxLoggedResponseChars {
		return string(redactedRunes[:maxLoggedResponseChars]) + "...<truncated>"
	}

	return redactedText
}

func redactSensitiveLogValues(value any) {
	switch typedValue := value.(type) {
	case map[string]any:
		for key, child := range typedValue {
			if isSensitiveLogKey(key) {
				typedValue[key] = "[REDACTED]"
				continue
			}
			redactSensitiveLogValues(child)
		}
	case []any:
		for _, child := range typedValue {
			redactSensitiveLogValues(child)
		}
	}
}

func isSensitiveLogKey(key string) bool {
	normalizedKey := strings.ToLower(key)
	for _, fragment := range sensitiveLogKeyFragments {
		if strings.Contains(normalizedKey, fragment) {
			return true
		}
	}
	return false
}
