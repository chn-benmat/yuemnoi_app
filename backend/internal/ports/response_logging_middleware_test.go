package ports

import (
	"bytes"
	"log"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestResponseLoggingMiddlewareLogsRedactedJSONResponse(t *testing.T) {
	gin.SetMode(gin.TestMode)

	previousWriter := log.Writer()
	previousFlags := log.Flags()
	previousPrefix := log.Prefix()
	t.Cleanup(func() {
		log.SetOutput(previousWriter)
		log.SetFlags(previousFlags)
		log.SetPrefix(previousPrefix)
	})

	var output bytes.Buffer
	log.SetOutput(&output)
	log.SetFlags(0)
	log.SetPrefix("")

	router := gin.New()
	router.Use(responseLoggingMiddleware())
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
		`"answer":"พบอุปกรณ์ 2 รายการ"`,
		`"access_token":"[REDACTED]"`,
		`"email":"[REDACTED]"`,
	} {
		if !strings.Contains(logged, expected) {
			t.Errorf("log output %q does not contain %q", logged, expected)
		}
	}

	for _, secret := range []string{"secret-access-token", "customer@example.com"} {
		if strings.Contains(logged, secret) {
			t.Errorf("log output contains sensitive value %q", secret)
		}
	}
}
