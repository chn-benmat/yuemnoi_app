package fcm

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/jellydator/ttlcache/v3"
)

type cacheTokenManager struct {
	token   string
	err     error
	reads   int
	deletes int
}

func (m *cacheTokenManager) GetFCMToken(context.Context, string) (string, error) {
	m.reads++
	return m.token, m.err
}

func (m *cacheTokenManager) DeleteFCMToken(context.Context, string) error {
	m.deletes++
	return nil
}

func TestReceiverTokenCacheUsesDatabaseForMissesAndInvalidation(t *testing.T) {
	m := &cacheTokenManager{token: "first"}
	sender := &FCMSender{tokenManager: m, fcmTokenCache: newReceiverTokenCache()}
	ctx := context.Background()
	for range 2 {
		token, err := sender.getReceiverToken(ctx, "user")
		if err != nil || token != "first" {
			t.Fatalf("cached token=%q, err=%v", token, err)
		}
	}
	if m.reads != 1 {
		t.Fatalf("cache hit read database: %d", m.reads)
	}
	sender.invalidateReceiverToken(ctx, "user")
	m.token = "second"
	token, err := sender.getReceiverToken(ctx, "user")
	if err != nil || token != "second" || m.reads != 2 || m.deletes != 1 {
		t.Fatalf("invalidation: token=%q reads=%d deletes=%d err=%v", token, m.reads, m.deletes, err)
	}
}

func TestReceiverTokenCacheDoesNotCacheEmptyOrErrors(t *testing.T) {
	m := &cacheTokenManager{}
	sender := &FCMSender{tokenManager: m, fcmTokenCache: newReceiverTokenCache()}
	ctx := context.Background()
	for range 2 {
		_, _ = sender.getReceiverToken(ctx, "empty")
	}
	m.err = errors.New("database unavailable")
	for range 2 {
		if _, err := sender.getReceiverToken(ctx, "error"); err == nil {
			t.Fatal("database error was hidden")
		}
	}
	if m.reads != 4 {
		t.Fatalf("empty/error result was cached: reads=%d", m.reads)
	}
}

func TestReceiverTokenCacheExpiredEntryReloadsFromDatabase(t *testing.T) {
	m := &cacheTokenManager{token: "current"}
	sender := &FCMSender{tokenManager: m, fcmTokenCache: newReceiverTokenCache()}
	item := sender.fcmTokenCache.Set("user", "old", time.Millisecond)
	time.Sleep(time.Until(item.ExpiresAt()) + time.Millisecond)
	token, err := sender.getReceiverToken(context.Background(), "user")
	if err != nil || token != "current" || m.reads != 1 {
		t.Fatalf("expired token=%q reads=%d err=%v", token, m.reads, err)
	}
}

func TestReceiverTokenCacheHitsDoNotExtendFixedTTL(t *testing.T) {
	m := &cacheTokenManager{token: "current"}
	sender := &FCMSender{tokenManager: m, fcmTokenCache: newReceiverTokenCache()}
	ctx := context.Background()
	if _, err := sender.getReceiverToken(ctx, "user"); err != nil {
		t.Fatal(err)
	}
	item := sender.fcmTokenCache.Get("user")
	expiresAt := item.ExpiresAt()
	if remaining := time.Until(expiresAt); remaining < receiverTokenTTL-time.Second || remaining > receiverTokenTTL {
		t.Fatalf("cache TTL=%v, want 5 minutes", remaining)
	}
	time.Sleep(time.Millisecond)
	for range 3 {
		if _, err := sender.getReceiverToken(ctx, "user"); err != nil {
			t.Fatal(err)
		}
	}
	if !item.ExpiresAt().Equal(expiresAt) || m.reads != 1 {
		t.Fatalf("cache hit extended expiry or read database: expiry=%v want=%v reads=%d", item.ExpiresAt(), expiresAt, m.reads)
	}
	// ข้อมูลหมดอายุที่ไม่มีผู้เรียกใช้ซ้ำต้องถูกกวาดเมื่อรับงานครั้งถัดไปด้วย
	stale := sender.fcmTokenCache.Set("inactive", "old", time.Millisecond)
	time.Sleep(time.Until(stale.ExpiresAt()) + time.Millisecond)
	_, _ = sender.getReceiverToken(ctx, "user")
	if sender.fcmTokenCache.Len() != 1 || sender.fcmTokenCache.Get("user", ttlcache.WithDisableTouchOnHit[string, string]()) == nil {
		t.Fatal("inactive expired token was not evicted")
	}
}
