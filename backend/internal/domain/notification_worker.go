package domain

import (
	"context"
	"errors"
	"log/slog"
	"sync"
	"time"
)

type NotificationWorker struct {
	repository NotificationDeliveryRepository
	sender     DevicePushSender
	interval   time.Duration
}

func NewNotificationWorker(repository NotificationDeliveryRepository, sender DevicePushSender) *NotificationWorker {
	return &NotificationWorker{repository: repository, sender: sender, interval: 10 * time.Second}
}

func (w *NotificationWorker) Run(ctx context.Context) {
	if w.repository == nil {
		return
	}
	ticker := time.NewTicker(w.interval)
	defer ticker.Stop()
	for {
		if err := w.RunOnce(ctx); err != nil && ctx.Err() == nil {
			slog.Warn("ประมวลผลงานแจ้งเตือนไม่สำเร็จ", slog.Any("error", err))
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func (w *NotificationWorker) RunOnce(ctx context.Context) error {
	if w.repository == nil {
		return nil
	}
	scheduleCtx, cancelSchedule := context.WithTimeout(ctx, 10*time.Second)
	reminderErr := w.repository.ScheduleNotificationReminders(scheduleCtx, time.Now().UTC())
	cancelSchedule()
	if ctx.Err() != nil {
		return ctx.Err()
	}
	if w.sender == nil {
		return reminderErr
	}
	claimCtx, cancelClaim := context.WithTimeout(ctx, 10*time.Second)
	deliveries, err := w.repository.ClaimNotificationDeliveries(claimCtx, 20, 120*time.Second)
	cancelClaim()
	if err != nil {
		return errors.Join(reminderErr, err)
	}
	var wg sync.WaitGroup
	semaphore := make(chan struct{}, 4)
	var mu sync.Mutex
	var completionErrors []error
	for _, delivery := range deliveries {
		select {
		case semaphore <- struct{}{}:
		case <-ctx.Done():
			wg.Wait()
			return errors.Join(reminderErr, ctx.Err())
		}
		wg.Add(1)
		go func(delivery NotificationDelivery) {
			defer wg.Done()
			defer func() { <-semaphore }()
			sendErr := w.sender.SendNotification(ctx, delivery)
			result := NotificationDeliveryResult{ID: delivery.ID, LeaseToken: delivery.LeaseToken, Outcome: "sent"}
			switch {
			case errors.Is(sendErr, ErrPushExpired):
				result.Outcome, result.ErrorCode = "failed", "expired"
			case errors.Is(sendErr, ErrPushTokenUnregistered):
				result.Outcome, result.ErrorCode = "invalid_token", "unregistered"
			case errors.Is(sendErr, ErrPushPermanent):
				result.Outcome, result.ErrorCode = "failed", "invalid_payload"
			case sendErr != nil:
				result.Outcome, result.ErrorCode = "retry", "delivery_unavailable"
			}
			// เก็บเฉพาะรหัสข้อผิดพลาดที่ไม่เปิดเผย token หรือข้อมูลส่วนตัวของผู้รับ
			completionCtx, cancelCompletion := context.WithTimeout(ctx, 5*time.Second)
			defer cancelCompletion()
			if err := w.repository.CompleteNotificationDelivery(completionCtx, result); err != nil {
				mu.Lock()
				completionErrors = append(completionErrors, err)
				mu.Unlock()
			}
		}(delivery)
	}
	wg.Wait()
	return errors.Join(append(completionErrors, reminderErr)...)
}
