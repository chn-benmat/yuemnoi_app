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
}

const (
	notificationBatchSize        = 20
	notificationRecoveryInterval = 30 * time.Second
	notificationReminderInterval = 10 * time.Second
)

func NewNotificationWorker(repository NotificationDeliveryRepository, sender DevicePushSender) *NotificationWorker {
	return &NotificationWorker{repository: repository, sender: sender}
}

func (w *NotificationWorker) Run(ctx context.Context, wakeups <-chan struct{}) {
	if w.repository == nil {
		return
	}
	if w.sender == nil {
		w.runReminderSchedule(ctx)
		return
	}
	var reminders sync.WaitGroup
	reminders.Go(func() { w.runReminderSchedule(ctx) })
	defer reminders.Wait()

	// เช็กงานค้างเมื่อเริ่มและเป็นระยะเผื่อ WebSocket พลาดสัญญาณหรืองานถึงรอบ retry
	ticker := time.NewTicker(notificationRecoveryInterval)
	defer ticker.Stop()
	for {
		for ctx.Err() == nil {
			count, err := w.deliverOnce(ctx)
			if err != nil {
				if ctx.Err() == nil {
					slog.Warn("ประมวลผลงานแจ้งเตือนไม่สำเร็จ", slog.Any("error", err))
				}
				break
			}
			if count < notificationBatchSize {
				break
			}
		}
		select {
		case <-ctx.Done():
			return
		case _, ok := <-wakeups:
			if !ok {
				wakeups = nil
			}
		case <-ticker.C:
		}
	}
}

func (w *NotificationWorker) runReminderSchedule(ctx context.Context) {
	ticker := time.NewTicker(notificationReminderInterval)
	defer ticker.Stop()
	for ctx.Err() == nil {
		if err := w.scheduleReminders(ctx); err != nil && ctx.Err() == nil {
			slog.Warn("ตั้งเวลาเตือนคืนสินค้าไม่สำเร็จ", slog.Any("error", err))
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
	reminderErr := w.scheduleReminders(ctx)
	if ctx.Err() != nil {
		return ctx.Err()
	}
	if w.sender == nil {
		return reminderErr
	}
	_, err := w.deliverOnce(ctx)
	return errors.Join(reminderErr, err)
}

func (w *NotificationWorker) scheduleReminders(ctx context.Context) error {
	scheduleCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	return w.repository.ScheduleNotificationReminders(scheduleCtx, time.Now().UTC())
}

func (w *NotificationWorker) deliverOnce(ctx context.Context) (int, error) {
	claimCtx, cancelClaim := context.WithTimeout(ctx, 10*time.Second)
	deliveries, err := w.repository.ClaimNotificationDeliveries(claimCtx, notificationBatchSize, 120*time.Second)
	cancelClaim()
	if err != nil {
		return 0, err
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
			return len(deliveries), ctx.Err()
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
	return len(deliveries), errors.Join(completionErrors...)
}
