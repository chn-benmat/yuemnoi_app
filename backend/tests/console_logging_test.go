package tests

import (
	"bytes"
	"context"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/logging"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	"github.com/gofiber/fiber/v3"
	"github.com/stretchr/testify/require"
)

func TestConsoleLoggingHTTPStatusColors(t *testing.T) {
	for _, tc := range []struct {
		status int
		color  string
	}{
		{200, "\x1b[32m"},
		{201, "\x1b[32m"},
		{204, "\x1b[32m"},
		{302, ""},
		{400, "\x1b[33m"},
		{401, "\x1b[33m"},
		{404, "\x1b[33m"},
		{429, "\x1b[33m"},
		{500, "\x1b[31m"},
		{502, "\x1b[31m"},
		{503, "\x1b[31m"},
	} {
		t.Run(strconv.Itoa(tc.status), func(t *testing.T) {
			var output bytes.Buffer
			logger := slog.New(logging.NewTextHandler(&output, nil, true))
			logger.Info("http_request", "status", tc.status, "latency_ms", 5)
			field := "status=" + strconv.Itoa(tc.status)
			if tc.color == "" {
				require.NotContains(t, output.String(), "\x1b[")
				require.Contains(t, output.String(), field)
			} else {
				require.Contains(t, output.String(), tc.color+field+"\x1b[0m latency_ms=5")
			}
		})
	}
}

func TestConsoleLoggingLevelsAndPlainOutput(t *testing.T) {
	for _, tc := range []struct {
		level slog.Level
		color string
	}{
		{slog.LevelDebug, ""},
		{slog.LevelInfo, ""},
		{slog.LevelWarn, "\x1b[33m"},
		{slog.LevelError, "\x1b[31m"},
	} {
		t.Run(tc.level.String(), func(t *testing.T) {
			for _, useColor := range []bool{false, true} {
				var output bytes.Buffer
				logger := slog.New(logging.NewTextHandler(&output, &slog.HandlerOptions{Level: slog.LevelDebug}, useColor))
				logger.Log(context.Background(), tc.level, "server event", "status", 500)
				field := "level=" + tc.level.String()
				if useColor && tc.color != "" {
					require.Contains(t, output.String(), tc.color+field+"\x1b[0m")
				} else {
					require.Contains(t, output.String(), field)
				}
				if !useColor {
					require.NotContains(t, output.String(), "\x1b[")
					require.Contains(t, output.String(), "status=500")
				}
			}
		})
	}
}

func TestConsoleLoggingPreservesQuotedValuesAndDerivedLoggers(t *testing.T) {
	var output bytes.Buffer
	logger := slog.New(logging.NewTextHandler(&output, nil, true)).With("status", 200)
	message := `example "status=500" level=ERROR`
	logger.WithGroup("request").Info(message, "note", "status=404 level=WARN", "path", "/status=500")
	logged := output.String()
	require.Contains(t, logged, "\x1b[32mstatus=200\x1b[0m")
	require.Contains(t, logged, `msg="example \"status=500\" level=ERROR"`)
	require.Contains(t, logged, `request.note="status=404 level=WARN"`)
	require.Contains(t, logged, `request.path="/status=500"`)
	require.NotContains(t, logged, "\x1b[31m")
	require.NotContains(t, logged, "\x1b[33m")
}

func TestConsoleLoggingUsesFinalHTTPStatus(t *testing.T) {
	var output bytes.Buffer
	previousLogger := slog.Default()
	slog.SetDefault(slog.New(logging.NewTextHandler(&output, nil, true)))
	t.Cleanup(func() { slog.SetDefault(previousLogger) })

	app := ports.SetupRouter(nil, nil, nil, nil, nil, nil, "")
	app.Get("/test/error", func(c fiber.Ctx) error {
		return errors.New("test server error")
	})
	for _, tc := range []struct {
		path   string
		status int
		color  string
	}{
		{"/health", http.StatusOK, "\x1b[32m"},
		{"/missing-route", http.StatusNotFound, "\x1b[33m"},
		{"/test/error", http.StatusInternalServerError, "\x1b[31m"},
	} {
		t.Run(tc.path, func(t *testing.T) {
			output.Reset()
			response, err := app.Test(httptest.NewRequest(http.MethodGet, tc.path, nil))
			require.NoError(t, err)
			defer response.Body.Close()
			require.Equal(t, tc.status, response.StatusCode)
			require.Contains(t, output.String(), tc.color+"status="+strconv.Itoa(tc.status)+"\x1b[0m")
		})
	}
}
