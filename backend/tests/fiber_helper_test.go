package tests

import (
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gofiber/fiber/v3"
	"github.com/stretchr/testify/require"
)

// ใช้ Fiber transport จริงใน tests และเก็บรูปแบบ assertion ของสัญญา HTTP เดิม
func performFiberRequest(t *testing.T, app *fiber.App, recorder *httptest.ResponseRecorder, request *http.Request) {
	t.Helper()
	response, err := app.Test(request, fiber.TestConfig{Timeout: 0})
	require.NoError(t, err)
	defer response.Body.Close()
	for key, values := range response.Header {
		for _, value := range values {
			recorder.Header().Add(key, value)
		}
	}
	recorder.WriteHeader(response.StatusCode)
	_, err = io.Copy(recorder, response.Body)
	require.NoError(t, err)
}
