package ports

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
	"golang.org/x/time/rate"
)

func TestCORSHTTPContract(t *testing.T) {
	app := SetupRouterWithOperations(domain.OperationsOptions{}, nil, nil, nil, nil, nil, nil, "test-secret")
	t.Cleanup(func() { _ = app.Shutdown() })
	for _, tt := range []struct {
		name, origin, allowOrigin, credentials string
	}{
		{"native", "", "*", ""},
		{"localhost port", "http://localhost:54321", "http://localhost:54321", "true"},
		{"loopback", "http://127.0.0.1:8080", "http://127.0.0.1:8080", "true"},
		{"site", "https://yuemnoi.com", "https://yuemnoi.com", "true"},
		{"subdomain", "https://admin.yuemnoi.com", "https://admin.yuemnoi.com", "true"},
		{"tailscale", "https://device.example.ts.net", "https://device.example.ts.net", "true"},
		{"lookalike", "https://yuemnoi.com.example.invalid", "", ""},
		{"path", "https://example.invalid/yuemnoi.com", "", ""},
		{"userinfo", "https://user@yuemnoi.com", "", ""},
		{"root path", "https://yuemnoi.com/", "", ""},
		{"scheme", "ftp://yuemnoi.com", "", ""},
		{"query", "https://yuemnoi.com?x=1", "", ""},
		{"fragment", "https://yuemnoi.com#x", "", ""},
	} {
		t.Run(tt.name, func(t *testing.T) {
			for _, method := range []string{http.MethodGet, http.MethodOptions, "bare OPTIONS"} {
				path := "/health"
				requestMethod := method
				if method == "bare OPTIONS" {
					requestMethod = http.MethodOptions
				}
				if requestMethod == http.MethodOptions {
					path = "/api/auth/login"
				}
				req := httptest.NewRequest(requestMethod, path, nil)
				if tt.origin != "" {
					req.Header.Set("Origin", tt.origin)
				}
				if method == http.MethodOptions {
					req.Header.Set("Access-Control-Request-Method", "POST")
					req.Header.Set("Access-Control-Request-Headers", "Content-Type, X-App-Secret")
				}
				res, err := app.Test(req)
				if err != nil {
					t.Fatal(err)
				}
				_ = res.Body.Close()
				wantStatus := http.StatusOK
				if requestMethod == http.MethodOptions {
					wantStatus = http.StatusNoContent
				}
				if res.StatusCode != wantStatus || res.Header.Get("Access-Control-Allow-Origin") != tt.allowOrigin || res.Header.Get("Access-Control-Allow-Credentials") != tt.credentials {
					t.Fatalf("%s: status=%d origin=%q credentials=%q", method, res.StatusCode, res.Header.Get("Access-Control-Allow-Origin"), res.Header.Get("Access-Control-Allow-Credentials"))
				}
				if res.Header.Get("Access-Control-Allow-Headers") != "Origin, Content-Type, Accept, Authorization, X-Requested-With, X-App-Secret" || res.Header.Get("Access-Control-Allow-Methods") != "POST, GET, OPTIONS, PUT, DELETE, PATCH" {
					t.Fatalf("%s: CORS methods/headers changed: %v", method, res.Header)
				}
			}
		})
	}
}

func TestRateLimiterConcurrentRequestsShareOneBucket(t *testing.T) {
	limiter := NewRateLimiter(0.0001, 5)
	var allowed atomic.Int32
	var requests sync.WaitGroup
	for range 100 {
		requests.Go(func() {
			if limiter.Allow("client") {
				allowed.Add(1)
			}
		})
	}
	requests.Wait()
	if allowed.Load() != 5 {
		t.Fatalf("concurrent burst allowed %d, want 5", allowed.Load())
	}
}

func TestRateLimiterTouchesActiveKeysAndEvictsIdleKeys(t *testing.T) {
	limiter := NewRateLimiter(0.0001, 1)
	limiter.Allow("active")
	entry := limiter.entries.Get("active")
	before := entry.ExpiresAt()
	if remaining := time.Until(before); remaining < 10*time.Minute-time.Second || remaining > 10*time.Minute {
		t.Fatalf("idle bucket TTL=%v, want 10 minutes", remaining)
	}
	stale := limiter.entries.Set("idle", rate.NewLimiter(0.0001, 1), time.Millisecond)
	time.Sleep(time.Until(stale.ExpiresAt()) + time.Millisecond)
	if limiter.Allow("active") {
		t.Fatal("active bucket was reset")
	}
	if !entry.ExpiresAt().After(before) || limiter.entries.Len() != 1 {
		t.Fatalf("idle cleanup or active expiry refresh changed: before=%v after=%v len=%d", before, entry.ExpiresAt(), limiter.entries.Len())
	}
}

func TestRouterRateLimitGroupsShareQuotaAcrossTheirRoutes(t *testing.T) {
	app := SetupRouterWithOperations(domain.OperationsOptions{}, nil, nil, nil, nil, nil, nil, "test-secret")
	t.Cleanup(func() { _ = app.Shutdown() })
	send := func(path, key string, want int) {
		t.Helper()
		req := httptest.NewRequest(http.MethodPost, path, strings.NewReader("{}"))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-App-Secret", key)
		req.Header.Set("X-Real-IP", "192.0.2.10")
		res, err := app.Test(req)
		if err != nil {
			t.Fatal(err)
		}
		_ = res.Body.Close()
		if res.StatusCode != want {
			t.Fatalf("%s: status=%d, want %d", path, res.StatusCode, want)
		}
	}
	for range 6 {
		send("/api/auth/login", "invalid-key", http.StatusUnauthorized)
	}
	for _, path := range []string{"/api/auth/login", "/api/auth/send-otp", "/api/auth/verify-otp", "/api/auth/register", "/api/auth/login"} {
		send(path, "test-secret", http.StatusBadRequest)
	}
	send("/api/admin/login", "test-secret", http.StatusTooManyRequests)
	for i := range 15 {
		path := "/api/chat-ai"
		if i%2 != 0 {
			path += "/stream"
		}
		send(path, "test-secret", http.StatusBadRequest)
	}
	send("/api/chat-ai/stream", "test-secret", http.StatusTooManyRequests)
	for _, path := range []string{"/api/identity/sessions", "/api/identity/sessions/session/submit", "/api/complaints", "/api/identity/sessions", "/api/complaints"} {
		send(path, "test-secret", http.StatusUnauthorized)
	}
	send("/api/complaints", "test-secret", http.StatusTooManyRequests)
}

func TestCORSResponsesVaryByOrigin(t *testing.T) {
	app := SetupRouterWithOperations(domain.OperationsOptions{}, nil, nil, nil, nil, nil, nil, "test-secret")
	t.Cleanup(func() { _ = app.Shutdown() })
	for _, origin := range []string{"", "https://yuemnoi.com", "https://example.invalid"} {
		req := httptest.NewRequest(http.MethodGet, "/health", nil)
		if origin != "" {
			req.Header.Set("Origin", origin)
		}
		res, err := app.Test(req)
		if err != nil {
			t.Fatal(err)
		}
		_ = res.Body.Close()
		if res.Header.Get("Vary") != "Origin" {
			t.Fatalf("origin %q: Vary=%q, want Origin so shared caches cannot mix CORS responses", origin, res.Header.Get("Vary"))
		}
	}
}

func TestRateLimiterTokenBucketRefillsAfterRejectedRequests(t *testing.T) {
	limiter := NewRateLimiter(2.5, 2)
	if !limiter.Allow("a") || !limiter.Allow("a") || limiter.Allow("a") || !limiter.Allow("b") {
		t.Fatal("initial burst or independent client quota changed")
	}
	for range 20 {
		if limiter.Allow("a") {
			t.Fatal("rejected requests unexpectedly refill the bucket")
		}
	}
	time.Sleep(450 * time.Millisecond)
	if !limiter.Allow("a") {
		t.Fatal("fractional-rate bucket did not refill one token; rejected requests must not create debt")
	}
}

func TestRateLimitMiddlewarePreservesProxyKeyAndResponse(t *testing.T) {
	limiter := NewRateLimiter(0.0001, 1)
	app := NewHTTPApp()
	app.Use(RateLimitMiddleware(limiter, "rate limited"))
	app.Post("/first", func(c fiber.Ctx) error { return c.SendStatus(http.StatusNoContent) })
	app.Post("/second", func(c fiber.Ctx) error { return c.SendStatus(http.StatusNoContent) })
	t.Cleanup(func() { _ = app.Shutdown() })
	for i, tt := range []struct {
		path, forwarded, realIP string
		status                  int
	}{
		{"/first", "", "192.0.2.1", 204},
		{"/second", "", "192.0.2.1", 429},
		{"/first", "", "192.0.2.2", 204},
		{"/second", "192.0.2.1", "192.0.2.3", 429},
	} {
		req := httptest.NewRequest(http.MethodPost, tt.path, nil)
		req.Header.Set("X-Real-IP", tt.realIP)
		if tt.forwarded != "" {
			req.Header.Set("X-Forwarded-For", tt.forwarded)
		}
		res, err := app.Test(req)
		if err != nil {
			t.Fatal(err)
		}
		if res.StatusCode != tt.status {
			t.Fatalf("request %d status=%d, want %d", i, res.StatusCode, tt.status)
		}
		if tt.status == 429 {
			var body struct {
				Status int    `json:"status"`
				Error  string `json:"error"`
			}
			if err := json.NewDecoder(res.Body).Decode(&body); err != nil || body.Status != 429 || body.Error != "rate limited" {
				t.Fatalf("429 contract changed: %+v, %v", body, err)
			}
			if res.Header.Get("Retry-After") != "" || res.Header.Get("X-Rate-Limit-Limit") != "" {
				t.Fatal("unexpected public rate-limit headers")
			}
		}
		_ = res.Body.Close()
	}
}
