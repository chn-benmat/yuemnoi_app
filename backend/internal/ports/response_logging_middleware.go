package ports

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"strings"

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

func responseLoggingMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		writer := &responseLogWriter{ResponseWriter: c.Writer}
		c.Writer = writer

		c.Next()

		log.Printf(
			"api_response method=%s path=%s status=%d body=%s",
			c.Request.Method,
			c.Request.URL.Path,
			c.Writer.Status(),
			safeBodyForLog(writer.body.Bytes()),
		)
	}
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
