package tests

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"mime/multipart"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/aiservice"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/config"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	"github.com/gofiber/fiber/v3"
	"github.com/stretchr/testify/require"
)

type transportAuthGateway struct {
	domain.AuthGateway
	registered domain.RegisterUser
	updated    domain.UpdateProfileRequest
	image      *domain.ProfileImage
}

func (*transportAuthGateway) UserIDFromToken(context.Context, string) (string, error) {
	return "verified-user", nil
}

func (m *transportAuthGateway) Register(_ context.Context, user domain.RegisterUser) (*domain.RegisterResult, error) {
	m.registered = user
	return &domain.RegisterResult{UserID: "registered-user"}, nil
}

func (m *transportAuthGateway) UpdateProfile(_ context.Context, _ string, req domain.UpdateProfileRequest, image *domain.ProfileImage) (*domain.UserProfile, error) {
	m.updated, m.image = req, image
	return &domain.UserProfile{UserID: "verified-user"}, nil
}

// ตรวจ binding จริงผ่าน routes เพื่อป้องกันการย้าย framework แล้ว validation หายไป
func TestFiberPreservesRequestValidation(t *testing.T) {
	for _, tc := range []struct{ path, body string }{
		{"/api/auth/login", `{"email":"invalid","password":"123456"}`},
		{"/api/auth/register", `{"display_name":"name","email":"a@example.test","phone":"0812345678","password":"123"}`},
		{"/api/auth/verify-otp", `{"email":"a@example.test","otp_code":"abcdef"}`},
		{"/api/auth/send-otp", `{"email":"invalid"}`},
		{"/api/auth/change-password", `{"new_password":"123"}`},
		{"/api/items", `{"item_name":"camera","description":"camera","category":"camera","price":1,"type":"unsupported"}`},
		{"/api/items", `{"item_name":"camera","description":"camera","category":"camera","price":-1,"type":"daily"}`},
		{"/api/rentals", `{"item_id":1,"start_at":"2026-10-09T01:00:00Z","end_at":"2026-10-10T01:00:00Z","rental_type":"daily"}`},
		{"/api/push/chat", `{"receiver_id":"other"}`},
		{"/api/chat/contact", `{}`},
		{"/api/chat-ai", `{broken`},
	} {
		t.Run(tc.path+tc.body, func(t *testing.T) {
			app := ports.SetupRouter(nil, &transportAuthGateway{}, nil, nil, nil, nil, "")
			request := httptest.NewRequest(http.MethodPost, tc.path, strings.NewReader(tc.body))
			request.Header.Set("Authorization", "Bearer verified")
			request.Header.Set("Content-Type", "application/json")
			recorder := httptest.NewRecorder()
			performFiberRequest(t, app, recorder, request)
			require.Equal(t, http.StatusBadRequest, recorder.Code, recorder.Body.String())
		})
	}
}

func multipartRequest(t *testing.T, method, path string, fields map[string]string, fileField string, count, size int) *http.Request {
	t.Helper()
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	for name, value := range fields {
		require.NoError(t, writer.WriteField(name, value))
	}
	if count > 0 {
		image := make([]byte, size)
		copy(image, "\x89PNG\r\n\x1a\n")
		for i := 0; i < count; i++ {
			file, err := writer.CreateFormFile(fileField, "image.png")
			require.NoError(t, err)
			_, err = file.Write(image)
			require.NoError(t, err)
		}
	}
	require.NoError(t, writer.Close())
	request := httptest.NewRequest(method, path, &body)
	request.Header.Set("Content-Type", writer.FormDataContentType())
	request.Header.Set("Authorization", "Bearer verified")
	return request
}

func TestFiberPreservesUploadLimits(t *testing.T) {
	fields := map[string]string{"item_name": "camera", "description": "camera", "category": "camera", "price": "10", "type": "daily"}
	for _, tc := range []struct {
		name, field string
		count, size int
		status      int
	}{
		{"five maximum size images", "images", 5, 5 << 20, http.StatusCreated},
		{"six images rejected", "images", 6, 16, http.StatusBadRequest},
		{"oversized image rejected", "images", 1, (5 << 20) + 1, http.StatusBadRequest},
	} {
		t.Run(tc.name, func(t *testing.T) {
			repository := &itemHandlerRepository{}
			app := ports.NewHTTPApp()
			app.Post("/api/items", ports.NewItemHandler(repository, itemTokenVerifier{}).CreateItem)
			recorder := httptest.NewRecorder()
			performFiberRequest(t, app, recorder, multipartRequest(t, http.MethodPost, "/api/items", fields, tc.field, tc.count, tc.size))
			require.Equal(t, tc.status, recorder.Code, recorder.Body.String())
			if tc.status == http.StatusCreated {
				require.Len(t, repository.images, 5)
			}
		})
	}
}

func TestFiberPreservesOptionalProfileImageAndPointerFields(t *testing.T) {
	auth := &transportAuthGateway{}
	app := ports.NewHTTPApp()
	handler := ports.NewUserHandler(auth)
	app.Post("/register", handler.Register)
	app.Put("/profile", handler.UpdateProfile)
	request := multipartRequest(t, http.MethodPost, "/register", map[string]string{
		"display_name": "name", "email": "a@example.test", "phone": "0812345678", "password": "123456",
	}, "image", 0, 0)
	recorder := httptest.NewRecorder()
	performFiberRequest(t, app, recorder, request)
	require.Equal(t, http.StatusCreated, recorder.Code, recorder.Body.String())
	require.Nil(t, auth.registered.ProfileImage)
	require.Equal(t, "+66812345678", auth.registered.Phone)

	for _, withImage := range []bool{false, true} {
		count, size := 0, 0
		if withImage {
			count, size = 1, 5<<20
		}
		request = multipartRequest(t, http.MethodPut, "/profile", map[string]string{"bio": ""}, "image", count, size)
		recorder = httptest.NewRecorder()
		performFiberRequest(t, app, recorder, request)
		require.Equal(t, http.StatusOK, recorder.Code, recorder.Body.String())
		require.Nil(t, auth.updated.DisplayName)
		require.Nil(t, auth.updated.Username)
		require.NotNil(t, auth.updated.Bio)
		require.Empty(t, *auth.updated.Bio)
		if withImage {
			require.Len(t, auth.image.Data, size)
		} else {
			require.Nil(t, auth.image)
		}
	}
}

func startFiberListener(t *testing.T, app *fiber.App) string {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	require.NoError(t, err)
	done := make(chan error, 1)
	go func() { done <- app.Listener(listener, fiber.ListenConfig{DisableStartupMessage: true}) }()
	t.Cleanup(func() {
		_ = app.ShutdownWithTimeout(2 * time.Second)
		select {
		case err := <-done:
			require.NoError(t, err)
		case <-time.After(3 * time.Second):
			t.Error("Fiber listener did not stop")
		}
	})
	return "http://" + listener.Addr().String()
}

func openAIStream(t *testing.T, url string) *http.Response {
	t.Helper()
	request, err := http.NewRequest(http.MethodPost, url+"/stream", strings.NewReader(`{"query":"hello"}`))
	require.NoError(t, err)
	request.Header.Set("Content-Type", "application/json")
	client := &http.Client{Transport: &http.Transport{DisableKeepAlives: true}, Timeout: 5 * time.Second}
	response, err := client.Do(request)
	require.NoError(t, err)
	t.Cleanup(func() { _ = response.Body.Close() })
	require.Equal(t, http.StatusOK, response.StatusCode)
	return response
}

// ต้องตรวจผ่าน TCP จริง เพราะ app.Test จะรวบรวม body จนสตรีมจบ
func TestFiberSSEFlushesBeforeUpstreamCompletesAndCancelsOnDisconnect(t *testing.T) {
	cancelled := make(chan struct{})
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		_, _ = io.WriteString(w, "event: status\ndata: {\"step\":\"planning\"}\n\n")
		w.(http.Flusher).Flush()
		<-r.Context().Done()
		close(cancelled)
	}))
	t.Cleanup(upstream.Close)
	app := ports.NewHTTPApp()
	app.Post("/stream", ports.NewChatbotHandler(aiservice.NewClient(upstream.URL, "", 10*time.Second), nil).SendMessageStream)
	response := openAIStream(t, startFiberListener(t, app))
	reader := bufio.NewReader(response.Body)
	line, err := reader.ReadString('\n')
	require.NoError(t, err)
	require.Equal(t, "event: status\n", line)
	require.NoError(t, response.Body.Close())
	select {
	case <-cancelled:
	case <-time.After(4 * time.Second):
		t.Fatal("upstream kept running after client disconnect")
	}
}

func TestFiberSSETimeoutAndShutdownCancelUpstream(t *testing.T) {
	for _, shutdown := range []bool{false, true} {
		t.Run(map[bool]string{false: "timeout", true: "shutdown"}[shutdown], func(t *testing.T) {
			cancelled := make(chan struct{})
			upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "text/event-stream")
				w.(http.Flusher).Flush()
				<-r.Context().Done()
				close(cancelled)
			}))
			t.Cleanup(upstream.Close)
			timeout := 200 * time.Millisecond
			if shutdown {
				timeout = 10 * time.Second
			}
			app := ports.NewHTTPApp(fiber.Config{ReadTimeout: time.Second, WriteTimeout: timeout})
			app.Post("/stream", ports.NewChatbotHandler(aiservice.NewClient(upstream.URL, "", 10*time.Second), nil).SendMessageStream)
			_ = openAIStream(t, startFiberListener(t, app))
			if shutdown {
				require.NoError(t, app.ShutdownWithTimeout(time.Second))
			}
			select {
			case <-cancelled:
			case <-time.After(2 * time.Second):
				t.Fatal("upstream did not receive cancellation")
			}
		})
	}
}

func TestFiberHeartbeatNeverSplitsAnUpstreamEvent(t *testing.T) {
	reader, writer := io.Pipe()
	app := ports.NewHTTPApp()
	app.Post("/stream", ports.NewChatbotHandler(&mockAIChatbotGateway{
		sendMessageStreamFunc: func(context.Context, domain.ChatbotRequest) (io.ReadCloser, error) { return reader, nil },
	}, nil).SendMessageStream)
	go func() {
		defer writer.Close()
		_, _ = io.WriteString(writer, "event: delta\ndata: {\"text\":\"hel")
		timer := time.NewTimer(1200 * time.Millisecond)
		defer timer.Stop()
		<-timer.C
		_, _ = io.WriteString(writer, "lo\"}\n\n")
	}()
	request := httptest.NewRequest(http.MethodPost, "/stream", strings.NewReader(`{"query":"hello"}`))
	recorder := httptest.NewRecorder()
	performFiberRequest(t, app, recorder, request)
	require.Equal(t, "event: delta\ndata: {\"text\":\"hello\"}\n\n", recorder.Body.String())
}

func TestFiberSSEFailureBeforeHeadersStaysJSON(t *testing.T) {
	cancelled := make(chan struct{})
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = io.Copy(io.Discard, r.Body)
		<-r.Context().Done()
		close(cancelled)
	}))
	t.Cleanup(upstream.Close)
	app := ports.NewHTTPApp()
	app.Post("/stream", ports.NewChatbotHandler(aiservice.NewClient(upstream.URL, "", 100*time.Millisecond), nil).SendMessageStream)
	request := httptest.NewRequest(http.MethodPost, "/stream", strings.NewReader(`{"query":"hello"}`))
	recorder := httptest.NewRecorder()
	performFiberRequest(t, app, recorder, request)
	require.Equal(t, http.StatusBadGateway, recorder.Code)
	require.Contains(t, recorder.Header().Get("Content-Type"), "application/json")
	require.NotContains(t, recorder.Header().Get("Content-Type"), "event-stream")
	select {
	case <-cancelled:
	case <-time.After(time.Second):
		t.Fatal("upstream did not stop at AI_SERVICE_TIMEOUT")
	}
}

func TestFiberSSEReadFailureDoesNotExposeUpstreamDetails(t *testing.T) {
	reader, writer := io.Pipe()
	app := ports.NewHTTPApp()
	app.Post("/stream", ports.NewChatbotHandler(&mockAIChatbotGateway{
		sendMessageStreamFunc: func(context.Context, domain.ChatbotRequest) (io.ReadCloser, error) { return reader, nil },
	}, nil).SendMessageStream)
	go func() {
		_, _ = io.WriteString(writer, "event: delta\ndata: {}\n\n")
		_ = writer.CloseWithError(errors.New("private upstream detail"))
	}()
	request := httptest.NewRequest(http.MethodPost, "/stream", strings.NewReader(`{"query":"hello"}`))
	recorder := httptest.NewRecorder()
	performFiberRequest(t, app, recorder, request)
	require.Equal(t, http.StatusOK, recorder.Code)
	require.Contains(t, recorder.Body.String(), "stream_interrupted")
	require.NotContains(t, recorder.Body.String(), "private upstream detail")
}

func TestFiberShutdownWaitsForNormalInFlightRequests(t *testing.T) {
	app := ports.NewHTTPApp()
	started, release := make(chan struct{}), make(chan struct{})
	app.Get("/slow", func(c fiber.Ctx) error {
		close(started)
		<-release
		return c.JSON(fiber.Map{"completed": true})
	})
	url := startFiberListener(t, app)
	result := make(chan error, 1)
	go func() {
		client := &http.Client{Timeout: 2 * time.Second}
		response, err := client.Get(url + "/slow")
		if err == nil {
			defer response.Body.Close()
			var payload map[string]bool
			err = json.NewDecoder(response.Body).Decode(&payload)
			if err == nil && !payload["completed"] {
				err = errors.New("in-flight request did not finish")
			}
		}
		result <- err
	}()
	select {
	case <-started:
	case <-time.After(time.Second):
		close(release)
		t.Fatal("request did not start")
	}
	shuttingDown := make(chan struct{})
	app.Hooks().OnPreShutdown(func() error {
		select {
		case <-shuttingDown:
		default:
			close(shuttingDown)
		}
		return nil
	})
	done := make(chan error, 1)
	go func() { done <- app.ShutdownWithTimeout(time.Second) }()
	select {
	case <-shuttingDown:
	case <-time.After(time.Second):
		close(release)
		t.Fatal("shutdown did not start")
	}
	close(release)
	require.NoError(t, <-result)
	require.NoError(t, <-done)
}

func TestFiberReleaseModeSupportsLegacyConfiguration(t *testing.T) {
	for _, tc := range []struct{ mode, legacy, want string }{
		{"", "release", "release"},
		{"release", "debug", "release"},
		{"debug", "release", "debug"},
	} {
		t.Run(tc.mode+tc.legacy, func(t *testing.T) {
			t.Setenv("APP_ENV", tc.mode)
			t.Setenv("GIN_MODE", tc.legacy)
			t.Setenv("SUPABASE_URL", "https://example.test")
			t.Setenv("SUPABASE_SERVICE_ROLE_KEY", "test")
			t.Setenv("APP_SECRET_KEY", "")
			t.Setenv("APP_SECRET_KEYS", "")
			t.Setenv("INTERNAL_SERVICE_KEY", "")
			cfg, err := config.Load()
			if tc.want == "release" {
				require.ErrorContains(t, err, "APP_SECRET_KEY is required")
			} else {
				require.NoError(t, err)
				require.Equal(t, tc.want, cfg.Mode)
			}
		})
	}
}

func TestFiberCORSRateLimitingAndCaseSensitivity(t *testing.T) {
	app := ports.SetupRouter(nil, nil, nil, nil, nil, nil, "")
	for _, origin := range []string{"http://localhost:3000", "https://client.yuemnoi.com", "https://untrusted.example", ""} {
		request := httptest.NewRequest(http.MethodOptions, "/api/items", nil)
		request.Header.Set("Origin", origin)
		recorder := httptest.NewRecorder()
		performFiberRequest(t, app, recorder, request)
		require.Equal(t, http.StatusNoContent, recorder.Code)
		if origin == "https://untrusted.example" {
			require.Empty(t, recorder.Header().Get("Access-Control-Allow-Origin"))
		} else if origin != "" {
			require.Equal(t, origin, recorder.Header().Get("Access-Control-Allow-Origin"))
		} else {
			require.Equal(t, "*", recorder.Header().Get("Access-Control-Allow-Origin"))
		}
	}
	for i := 0; i < 6; i++ {
		request := httptest.NewRequest(http.MethodPost, "/api/auth/missing", nil)
		request.Header.Set("X-Forwarded-For", "192.0.2.1")
		recorder := httptest.NewRecorder()
		performFiberRequest(t, app, recorder, request)
		require.Equal(t, http.StatusNotFound, recorder.Code)
	}
	for i := 0; i < 6; i++ {
		request := httptest.NewRequest(http.MethodPost, "/api/auth/login", strings.NewReader(`{}`))
		request.Header.Set("Content-Type", "application/json")
		request.Header.Set("X-Forwarded-For", "192.0.2.1")
		recorder := httptest.NewRecorder()
		performFiberRequest(t, app, recorder, request)
		if i < 5 {
			require.Equal(t, http.StatusBadRequest, recorder.Code)
		} else {
			require.Equal(t, http.StatusTooManyRequests, recorder.Code)
		}
	}
	request := httptest.NewRequest(http.MethodPost, "/api/auth/login", strings.NewReader(`{}`))
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("X-Forwarded-For", "192.0.2.2")
	recorder := httptest.NewRecorder()
	performFiberRequest(t, app, recorder, request)
	require.Equal(t, http.StatusBadRequest, recorder.Code)

	for _, methodPath := range []struct{ method, path string }{{http.MethodGet, "/HEALTH"}, {http.MethodHead, "/health"}} {
		request = httptest.NewRequest(methodPath.method, methodPath.path, nil)
		recorder = httptest.NewRecorder()
		performFiberRequest(t, app, recorder, request)
		require.Equal(t, http.StatusNotFound, recorder.Code)
	}

	request = httptest.NewRequest(http.MethodGet, "/health", nil)
	recorder = httptest.NewRecorder()
	performFiberRequest(t, app, recorder, request)
	var payload map[string]string
	require.NoError(t, json.Unmarshal(recorder.Body.Bytes(), &payload))
	require.Equal(t, map[string]string{"status": "ok"}, payload)
}

func TestFiberPreservesTrailingSlashRedirects(t *testing.T) {
	app := ports.SetupRouter(nil, nil, nil, nil, nil, nil, "required-app-key")
	for _, tc := range []struct {
		method, path, location string
		status                 int
	}{
		{http.MethodGet, "/api/items/?search=camera", "/api/items?search=camera", http.StatusMovedPermanently},
		{http.MethodGet, "/api/items/42/", "/api/items/42", http.StatusMovedPermanently},
		{http.MethodPost, "/api/auth/login/", "/api/auth/login", http.StatusTemporaryRedirect},
		{http.MethodPut, "/api/items/42/", "/api/items/42", http.StatusTemporaryRedirect},
	} {
		t.Run(tc.method+tc.path, func(t *testing.T) {
			request := httptest.NewRequest(tc.method, tc.path, nil)
			recorder := httptest.NewRecorder()
			performFiberRequest(t, app, recorder, request)
			require.Equal(t, tc.status, recorder.Code)
			require.Equal(t, tc.location, recorder.Header().Get("Location"))
		})
	}
}
