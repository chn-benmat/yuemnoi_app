package fcm_test

import (
	"context"
	"errors"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/fcm"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/jellydator/ttlcache/v3"
	"google.golang.org/api/option"
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
func (m *cacheTokenManager) DeleteFCMToken(context.Context, string) error { m.deletes++; return nil }

// จำลอง HTTP ของ Firebase เพื่อให้ SDK สร้าง error ชนิดจริง โดยไม่เชื่อมต่อบริการภายนอก
type unregisteredTransport struct{}

func (unregisteredTransport) RoundTrip(*http.Request) (*http.Response, error) {
	return &http.Response{StatusCode: http.StatusNotFound, Header: http.Header{"Content-Type": []string{"application/json"}}, Body: io.NopCloser(strings.NewReader(`{"error":{"code":404,"message":"registration token not registered","status":"NOT_FOUND","details":[{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError","errorCode":"UNREGISTERED"}]}}`))}, nil
}
func unregisteredMessageError(t *testing.T) error {
	t.Helper()
	app, err := firebase.NewApp(context.Background(), &firebase.Config{ProjectID: "test-project"}, option.WithHTTPClient(&http.Client{Transport: unregisteredTransport{}}))
	if err != nil {
		t.Fatal(err)
	}
	client, err := app.Messaging(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	_, err = client.Send(context.Background(), &messaging.Message{Token: "test-device"})
	if !messaging.IsUnregistered(err) {
		t.Fatalf("SDK did not classify UNREGISTERED: %v", err)
	}
	return err
}

func TestReceiverTokenCacheUsesDatabaseForMissesAndInvalidation(t *testing.T) {
	m := &cacheTokenManager{token: "first"}
	cache := fcm.NewReceiverTokenCache()
	client := &recordingMessageClient{}
	sender := fcm.NewFCMSenderWithClient(m, client, cache)
	ctx := context.Background()
	request := domain.ChatPushNotification{ReceiverID: "user"}
	for range 2 {
		if err := sender.SendChatPush(ctx, request); err != nil || client.message.Token != "first" {
			t.Fatalf("cached token=%q err=%v", client.message.Token, err)
		}
	}
	if m.reads != 1 {
		t.Fatalf("cache hit read database: %d", m.reads)
	}
	client.err = unregisteredMessageError(t)
	if err := sender.SendChatPush(ctx, request); err == nil {
		t.Fatal("unregistered delivery succeeded")
	}
	client.err = nil
	m.token = "second"
	err := sender.SendChatPush(ctx, request)
	if err != nil || client.message.Token != "second" || m.reads != 2 || m.deletes != 1 {
		t.Fatalf("invalidation: token=%q reads=%d deletes=%d err=%v", client.message.Token, m.reads, m.deletes, err)
	}
}

func TestReceiverTokenCacheDoesNotCacheEmptyOrErrors(t *testing.T) {
	m := &cacheTokenManager{}
	sender := fcm.NewFCMSenderWithClient(m, &recordingMessageClient{}, nil)
	ctx := context.Background()
	for range 2 {
		_ = sender.SendChatPush(ctx, domain.ChatPushNotification{ReceiverID: "empty"})
	}
	m.err = errors.New("database unavailable")
	for range 2 {
		if err := sender.SendChatPush(ctx, domain.ChatPushNotification{ReceiverID: "error"}); err == nil {
			t.Fatal("database error was hidden")
		}
	}
	if m.reads != 4 {
		t.Fatalf("empty/error result was cached: reads=%d", m.reads)
	}
}

func TestReceiverTokenCacheExpiredEntryReloadsFromDatabase(t *testing.T) {
	m := &cacheTokenManager{token: "current"}
	cache := fcm.NewReceiverTokenCache()
	client := &recordingMessageClient{}
	sender := fcm.NewFCMSenderWithClient(m, client, cache)
	item := cache.Set("user", "old", time.Millisecond)
	time.Sleep(time.Until(item.ExpiresAt()) + time.Millisecond)
	err := sender.SendChatPush(context.Background(), domain.ChatPushNotification{ReceiverID: "user"})
	if err != nil || client.message.Token != "current" || m.reads != 1 {
		t.Fatalf("expired token=%q reads=%d err=%v", client.message.Token, m.reads, err)
	}
}

func TestReceiverTokenCacheHitsDoNotExtendFixedTTL(t *testing.T) {
	m := &cacheTokenManager{token: "current"}
	cache := fcm.NewReceiverTokenCache()
	sender := fcm.NewFCMSenderWithClient(m, &recordingMessageClient{}, cache)
	ctx := context.Background()
	request := domain.ChatPushNotification{ReceiverID: "user"}
	if err := sender.SendChatPush(ctx, request); err != nil {
		t.Fatal(err)
	}
	item := cache.Get("user")
	expiresAt := item.ExpiresAt()
	if remaining := time.Until(expiresAt); remaining < 5*time.Minute-time.Second || remaining > 5*time.Minute {
		t.Fatalf("cache TTL=%v, want 5 minutes", remaining)
	}
	time.Sleep(time.Millisecond)
	for range 3 {
		if err := sender.SendChatPush(ctx, request); err != nil {
			t.Fatal(err)
		}
	}
	if !item.ExpiresAt().Equal(expiresAt) || m.reads != 1 {
		t.Fatalf("cache hit extended expiry or read database: expiry=%v want=%v reads=%d", item.ExpiresAt(), expiresAt, m.reads)
	}
	// ข้อมูลหมดอายุที่ไม่มีผู้เรียกใช้ซ้ำต้องถูกกวาดเมื่อรับงานครั้งถัดไปด้วย
	stale := cache.Set("inactive", "old", time.Millisecond)
	time.Sleep(time.Until(stale.ExpiresAt()) + time.Millisecond)
	_ = sender.SendChatPush(ctx, request)
	if cache.Len() != 1 || cache.Get("user", ttlcache.WithDisableTouchOnHit[string, string]()) == nil {
		t.Fatal("inactive expired token was not evicted")
	}
}
