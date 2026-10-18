package ports

import (
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/gofiber/fiber/v3"
	"github.com/jellydator/ttlcache/v3"
	"golang.org/x/time/rate"
)

// RateLimiter ใช้ token bucket ของ x/time/rate และให้ ttlcache ดูแลอายุข้อมูลแต่ละ IP
type RateLimiter struct {
	rate     rate.Limit
	capacity int
	entries  *ttlcache.Cache[string, *rate.Limiter]
}

// NewRateLimiter สร้าง RateLimiter ด้วยอัตราการสร้าง Token และขนาดบัคเก็ตสูงสุด
func NewRateLimiter(tokensPerSecond float64, capacity float64) *RateLimiter {
	return &RateLimiter{
		rate:     rate.Limit(tokensPerSecond),
		capacity: int(capacity),
		entries: ttlcache.New[string, *rate.Limiter](
			ttlcache.WithTTL[string, *rate.Limiter](10 * time.Minute),
		),
	}
}

// Allow ตรวจสอบว่าคำขอสำหรับ key ที่ระบุ (เช่น Client IP) ได้รับอนุญาตหรือไม่
func (rl *RateLimiter) Allow(key string) bool {
	// กวาดเฉพาะข้อมูลหมดอายุเมื่อมีคำขอ จึงไม่สร้าง worker ที่ต้องปิดพร้อม app
	rl.entries.DeleteExpired()
	entry, _ := rl.entries.GetOrSetFunc(key, func() *rate.Limiter {
		return rate.NewLimiter(rl.rate, rl.capacity)
	})
	return entry.Value().Allow()
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
