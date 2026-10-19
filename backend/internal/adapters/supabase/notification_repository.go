package supabase

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	supabaseclient "github.com/nedpals/supabase-go"
)

type SupabaseNotificationRepository struct {
	client *supabaseclient.Client
}

func NewSupabaseNotificationRepository(client *supabaseclient.Client) *SupabaseNotificationRepository {
	return &SupabaseNotificationRepository{client: client}
}

func (r *SupabaseNotificationRepository) ListNotifications(ctx context.Context, userID string, filter domain.NotificationFilter) (*domain.NotificationPage, error) {
	page := domain.NotificationPage{Items: []domain.Notification{}}
	err := r.rpc(ctx, "notification_list", map[string]any{
		"p_user_id": userID, "p_limit": filter.Limit, "p_offset": filter.Offset, "p_category": nullableNotificationString(filter.Category),
	}, &page)
	if page.Items == nil {
		page.Items = []domain.Notification{}
	}
	return &page, err
}

func (r *SupabaseNotificationRepository) MarkNotificationsRead(ctx context.Context, userID string, target domain.NotificationReadTarget) error {
	var result any
	return r.rpc(ctx, "notification_mark_read", map[string]any{
		"p_user_id": userID, "p_id": nullableNotificationString(target.ID), "p_conversation_id": nullableNotificationString(target.ConversationID), "p_read_through": target.ReadThrough,
	}, &result)
}

func (r *SupabaseNotificationRepository) RegisterNotificationDevice(ctx context.Context, userID string, device domain.NotificationDevice) error {
	var result any
	return r.rpc(ctx, "notification_register_device", map[string]any{
		"p_user_id": userID, "p_installation_id": device.InstallationID, "p_token": device.Token, "p_platform": device.Platform,
	}, &result)
}

func (r *SupabaseNotificationRepository) UnregisterNotificationDevice(ctx context.Context, userID, installationID string) error {
	var result any
	return r.rpc(ctx, "notification_unregister_device", map[string]any{"p_user_id": userID, "p_installation_id": installationID}, &result)
}

func (r *SupabaseNotificationRepository) ScheduleNotificationReminders(ctx context.Context, now time.Time) error {
	var result any
	return r.rpc(ctx, "notification_schedule_reminders", map[string]any{"p_now": now.UTC()}, &result)
}

func (r *SupabaseNotificationRepository) ClaimNotificationDeliveries(ctx context.Context, limit int, lease time.Duration) ([]domain.NotificationDelivery, error) {
	rows := []domain.NotificationDelivery{}
	err := r.rpc(ctx, "notification_claim_outbox", map[string]any{"p_limit": limit, "p_lease_seconds": int(lease.Seconds())}, &rows)
	return rows, err
}

func (r *SupabaseNotificationRepository) CompleteNotificationDelivery(ctx context.Context, result domain.NotificationDeliveryResult) error {
	var output any
	return r.rpc(ctx, "notification_complete_delivery", map[string]any{
		"p_id": result.ID, "p_lease_token": result.LeaseToken, "p_outcome": result.Outcome, "p_error": nullableNotificationString(result.ErrorCode),
	}, &output)
}

func (r *SupabaseNotificationRepository) rpc(ctx context.Context, name string, params map[string]any, result any) error {
	if r == nil || r.client == nil {
		return fmt.Errorf("notification repository is not configured")
	}
	if err := r.client.DB.Rpc(name, params).ExecuteWithContext(ctx, result); err != nil {
		if strings.Contains(err.Error(), "notification_not_found") {
			return domain.ErrNotificationNotFound
		}
		if strings.Contains(err.Error(), "notification_forbidden") {
			return domain.ErrNotificationForbidden
		}
		return fmt.Errorf("%s failed: %w", name, err)
	}
	return nil
}

func nullableNotificationString(value string) any {
	if value == "" {
		return nil
	}
	return value
}
