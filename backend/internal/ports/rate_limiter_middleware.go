package ports

import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

type rateLimiterEntry struct {
	tokens     float64
	lastRefill time.Time
}

// RateLimiter อิมพลีเมนต์ Token Bucket In-Memory ป้องกันการยิงสแปม/Brute-force
type RateLimiter struct {
	mu          sync.Mutex
	rate        float64 // tokens per second
	capacity    float64 // max burst
	entries     map[string]*rateLimiterEntry
	cleanupTick time.Duration
}

// NewRateLimiter สร้าง RateLimiter ด้วยอัตราการสร้าง Token และขนาดบัคเก็ตสูงสุด
func NewRateLimiter(rate float64, capacity float64) *RateLimiter {
	rl := &RateLimiter{
		rate:        rate,
		capacity:    capacity,
		entries:     make(map[string]*rateLimiterEntry),
		cleanupTick: 5 * time.Minute,
	}
	go rl.cleanupLoop()
	return rl
}

func (rl *RateLimiter) cleanupLoop() {
	ticker := time.NewTicker(rl.cleanupTick)
	defer ticker.Stop()
	for range ticker.C {
		rl.mu.Lock()
		now := time.Now()
		for k, v := range rl.entries {
			if now.Sub(v.lastRefill) > 10*time.Minute {
				delete(rl.entries, k)
			}
		}
		rl.mu.Unlock()
	}
}

// Allow ตรวจสอบว่าคำขอสำหรับ key ที่ระบุ (เช่น Client IP) ได้รับอนุญาตหรือไม่
func (rl *RateLimiter) Allow(key string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	entry, exists := rl.entries[key]
	if !exists {
		rl.entries[key] = &rateLimiterEntry{
			tokens:     rl.capacity - 1,
			lastRefill: now,
		}
		return true
	}

	// เติม Token ตามเวลาที่ผ่านไป
	elapsed := now.Sub(entry.lastRefill).Seconds()
	entry.tokens += elapsed * rl.rate
	if entry.tokens > rl.capacity {
		entry.tokens = rl.capacity
	}
	entry.lastRefill = now

	if entry.tokens >= 1.0 {
		entry.tokens -= 1.0
		return true
	}

	return false
}

// RateLimitMiddleware สร้าง Gin Middleware สำหรับจำกัดจำนวนคำขอตาม IP Address
func RateLimitMiddleware(limiter *RateLimiter, errorMessage string) gin.HandlerFunc {
	return func(c *gin.Context) {
		clientIP := c.ClientIP()
		if !limiter.Allow(clientIP) {
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
				"status": http.StatusTooManyRequests,
				"error":  errorMessage,
			})
			return
		}
		c.Next()
	}
}
