package ports

import (
	"bytes"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gofiber/fiber/v3"
	"github.com/stretchr/testify/assert"
)

func TestResponseLoggingMiddlewareLogsRedactedJSONResponse(t *testing.T) {

	var output bytes.Buffer
	testLogger := slog.New(slog.NewTextHandler(&output, nil))
	previousLogger := slog.Default()
	slog.SetDefault(testLogger)
	t.Cleanup(func() {
		slog.SetDefault(previousLogger)
	})

	router := NewHTTPApp()
	router.Use(ResponseLoggingMiddleware())
	router.Get("/result", func(c fiber.Ctx) error {
		return c.Status(http.StatusOK).JSON(fiber.Map{
			"answer":       "พบอุปกรณ์ 2 รายการ",
			"access_token": "secret-access-token",
			"profile": fiber.Map{
				"email": "customer@example.com",
			},
		})
	})

	request := httptest.NewRequest(http.MethodGet, "/result", nil)
	result, err := router.Test(request)
	assert.NoError(t, err)
	defer result.Body.Close()
	assert.Equal(t, http.StatusOK, result.StatusCode)

	logged := output.String()
	for _, expected := range []string{
		"method=GET",
		"path=/result",
		"status=200",
		"latency_ms=",
		`\"answer\":\"พบอุปกรณ์ 2 รายการ\"`,
		`\"access_token\":\"[REDACTED]\"`,
		`\"email\":\"[REDACTED]\"`,
	} {
		assert.True(t, strings.Contains(logged, expected), "log output %q should contain %q", logged, expected)
	}

	for _, secret := range []string{"secret-access-token", "customer@example.com"} {
		assert.False(t, strings.Contains(logged, secret), "log output should not contain sensitive value %q", secret)
	}
}
