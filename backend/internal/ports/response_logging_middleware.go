package ports

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
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

type responseLogWriter struct {
	gin.ResponseWriter
	body bytes.Buffer
}

func (w *responseLogWriter) Write(data []byte) (int, error) {
	n, err := w.ResponseWriter.Write(data)
	_, _ = w.body.Write(data[:n])
	return n, err
}

func (w *responseLogWriter) WriteString(data string) (int, error) {
	n, err := w.ResponseWriter.WriteString(data)
	_, _ = w.body.WriteString(data[:n])
	return n, err
}

// ResponseLoggingMiddleware บันทึก Structured Log ของ API Response โดยปกปิดข้อมูลที่มีความอ่อนไหว (PII / Secrets) อัตโนมัติ
func ResponseLoggingMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		writer := &responseLogWriter{ResponseWriter: c.Writer}
		c.Writer = writer

		c.Next()

		slog.InfoContext(
			c.Request.Context(),
			"api_response",
			slog.String("method", c.Request.Method),
			slog.String("path", c.Request.URL.Path),
			slog.Int("status", c.Writer.Status()),
			slog.Int64("latency_ms", time.Since(start).Milliseconds()),
			slog.String("body", safeBodyForLog(writer.body.Bytes())),
		)
	}
}

func responseLoggingMiddleware() gin.HandlerFunc {
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
