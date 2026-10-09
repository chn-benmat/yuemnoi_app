package tests

import (
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	"github.com/stretchr/testify/require"
)

func TestRateLimiterPreservesBurstAndSeparateIPs(t *testing.T) {
	limiter := ports.NewRateLimiter(0, 5)
	for _, ip := range []string{"192.0.2.1", "192.0.2.2"} {
		for index := 0; index < 5; index++ {
			require.True(t, limiter.Allow(ip))
		}
		require.False(t, limiter.Allow(ip))
	}
}

func TestRateLimiterRefillsTokens(t *testing.T) {
	limiter := ports.NewRateLimiter(20, 1)
	require.True(t, limiter.Allow("192.0.2.1"))
	require.False(t, limiter.Allow("192.0.2.1"))
	require.Eventually(t, func() bool { return limiter.Allow("192.0.2.1") }, time.Second, time.Millisecond)
}

func TestRateLimiterConcurrentRequestsCannotExceedBurst(t *testing.T) {
	limiter := ports.NewRateLimiter(0, 5)
	var accepted atomic.Int32
	var workers sync.WaitGroup
	for index := 0; index < 100; index++ {
		workers.Go(func() {
			if limiter.Allow("192.0.2.1") {
				accepted.Add(1)
			}
		})
	}
	workers.Wait()
	require.EqualValues(t, 5, accepted.Load())
}
