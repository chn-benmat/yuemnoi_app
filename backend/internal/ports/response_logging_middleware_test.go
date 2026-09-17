package ports

import (
	"bytes"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/assert"
)

func TestResponseLoggingMiddlewareLogsRedactedJSONResponse(t *testing.T) {
	gin.SetMode(gin.TestMode)

	var output bytes.Buffer
	testLogger := slog.New(slog.NewTextHandler(&output, nil))
	previousLogger := slog.Default()
	slog.SetDefault(testLogger)
	t.Cleanup(func() {
		slog.SetDefault(previousLogger)
	})

	router := gin.New()
	router.Use(ResponseLoggingMiddleware())
	router.GET("/result", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"answer":       "พบอุปกรณ์ 2 รายการ",
			"access_token": "secret-access-token",
			"profile": gin.H{
				"email": "customer@example.com",
			},
		})
	})

	request := httptest.NewRequest(http.MethodGet, "/result", nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

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
