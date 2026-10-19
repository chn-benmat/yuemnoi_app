package domain_test

import (
	"context"
	"errors"
	domain "github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"sync"
	"testing"
	"time"
)

type workerNotificationStore struct {
	mu          sync.Mutex
	deliveries  []domain.NotificationDelivery
	completed   map[string]domain.NotificationDeliveryResult
	scheduleErr error
	scheduled   int
	claimed     int
}

func (s *workerNotificationStore) ScheduleNotificationReminders(context.Context, time.Time) error {
	s.scheduled++
	return s.scheduleErr
}
func (s *workerNotificationStore) ClaimNotificationDeliveries(_ context.Context, limit int, lease time.Duration) ([]domain.NotificationDelivery, error) {
	s.claimed++
	if limit != 20 || lease != 120*time.Second {
		return nil, errors.New("unexpected lease")
	}
	return s.deliveries, nil
}
func (s *workerNotificationStore) CompleteNotificationDelivery(_ context.Context, result domain.NotificationDeliveryResult) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.completed == nil {
		s.completed = map[string]domain.NotificationDeliveryResult{}
	}
	s.completed[result.ID] = result
	return nil
}

type workerPushSender struct{}

func (workerPushSender) SendNotification(_ context.Context, d domain.NotificationDelivery) error {
	switch d.Token {
	case "expired":
		return domain.ErrPushTokenUnregistered
	case "invalid":
		return domain.ErrPushPermanent
	case "temporary":
		return errors.New("upstream unavailable with sensitive details")
	default:
		return nil
	}
}

func TestNotificationWorkerFinishesEachDeviceWithLeaseAndSafeRetryOutcome(t *testing.T) {
	store := &workerNotificationStore{}
	for _, token := range []string{"ok", "expired", "invalid", "temporary"} {
		store.deliveries = append(store.deliveries, domain.NotificationDelivery{ID: token, Token: token, LeaseToken: "lease-" + token})
	}
	if err := domain.NewNotificationWorker(store, workerPushSender{}).RunOnce(context.Background()); err != nil {
		t.Fatal(err)
	}
	for id, outcome := range map[string]string{"ok": "sent", "expired": "invalid_token", "invalid": "failed", "temporary": "retry"} {
		result, ok := store.completed[id]
		if !ok || result.Outcome != outcome || result.LeaseToken != "lease-"+id {
			t.Fatalf("result for %q = %#v", id, result)
		}
		if id == "temporary" && result.ErrorCode != "delivery_unavailable" {
			t.Fatalf("unsafe/unusable retry error: %q", result.ErrorCode)
		}
	}
	if store.scheduled != 1 || store.claimed != 1 {
		t.Fatalf("scheduler=%d claim=%d", store.scheduled, store.claimed)
	}
}

func TestReminderFailureDoesNotBlockExistingOutbox(t *testing.T) {
	scheduleErr := errors.New("scheduler unavailable")
	store := &workerNotificationStore{scheduleErr: scheduleErr, deliveries: []domain.NotificationDelivery{{ID: "existing", Token: "ok"}}}
	err := domain.NewNotificationWorker(store, workerPushSender{}).RunOnce(context.Background())
	if !errors.Is(err, scheduleErr) || store.completed["existing"].Outcome != "sent" {
		t.Fatalf("outbox stopped with scheduler failure: %v", err)
	}
}

func TestCancelledWorkerDoesNotClaimNewDeliveries(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	store := &workerNotificationStore{}
	if err := domain.NewNotificationWorker(store, workerPushSender{}).RunOnce(ctx); !errors.Is(err, context.Canceled) {
		t.Fatalf("error=%v", err)
	}
	if store.claimed != 0 {
		t.Fatal("claimed work after cancellation")
	}
}

func TestWorkerStillSchedulesInboxRemindersWithoutFirebaseConfiguration(t *testing.T) {
	store := &workerNotificationStore{}
	if err := domain.NewNotificationWorker(store, nil).RunOnce(context.Background()); err != nil {
		t.Fatal(err)
	}
	if store.scheduled != 1 || store.claimed != 0 {
		t.Fatalf("scheduler=%d claims=%d", store.scheduled, store.claimed)
	}
}
