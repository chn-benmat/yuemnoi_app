package ports

import (
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gofiber/fiber/v3"
	"golang.org/x/time/rate"
)

type rateLimiterEntry struct {
	limiter  *rate.Limiter
	lastSeen time.Time
}

// RateLimiter อิมพลีเมนต์ Token Bucket In-Memory ป้องกันการยิงสแปม/Brute-force
type RateLimiter struct {
	mu          sync.Mutex
	rate        rate.Limit
	capacity    int
	entries     map[string]*rateLimiterEntry
	nextCleanup time.Time
}

// NewRateLimiter สร้าง RateLimiter ด้วยอัตราการสร้าง Token และขนาดบัคเก็ตสูงสุด
func NewRateLimiter(tokensPerSecond float64, capacity float64) *RateLimiter {
	rl := &RateLimiter{
		rate:        rate.Limit(tokensPerSecond),
		capacity:    int(capacity),
		entries:     make(map[string]*rateLimiterEntry),
		nextCleanup: time.Now().Add(5 * time.Minute),
	}
	return rl
}

// Allow ตรวจสอบว่าคำขอสำหรับ key ที่ระบุ (เช่น Client IP) ได้รับอนุญาตหรือไม่
func (rl *RateLimiter) Allow(key string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	// กวาด IP ที่ไม่ได้ใช้งานเมื่อมีคำขอใหม่ จึงไม่มี goroutine ค้างหลังปิด app
	if !now.Before(rl.nextCleanup) {
		for key, entry := range rl.entries {
			if now.Sub(entry.lastSeen) > 10*time.Minute {
				delete(rl.entries, key)
			}
		}
		rl.nextCleanup = now.Add(5 * time.Minute)
	}
	entry, exists := rl.entries[key]
	if !exists {
		entry = &rateLimiterEntry{limiter: rate.NewLimiter(rl.rate, rl.capacity)}
		rl.entries[key] = entry
	}
	entry.lastSeen = now
	return entry.limiter.AllowN(now, 1)
}

// RateLimitMiddleware สร้าง Fiber middleware สำหรับจำกัดจำนวนคำขอตาม IP Address
func RateLimitMiddleware(limiter *RateLimiter, errorMessage string) fiber.Handler {
	return func(c fiber.Ctx) error {
		clientIP := c.IP()
		if c.IsProxyTrusted() && c.Get(fiber.HeaderXForwardedFor) == "" {
			if realIP := strings.TrimSpace(c.Get("X-Real-IP")); net.ParseIP(realIP) != nil {
				clientIP = realIP
			}
		}
		if !limiter.Allow(clientIP) {
			return c.Status(http.StatusTooManyRequests).JSON(fiber.Map{
				"status": http.StatusTooManyRequests,
				"error":  errorMessage,
			})
		}
		return c.Next()
	}
}
