package domain

import (
	"context"
	"errors"
	"time"
)

var (
	ErrNotificationNotFound  = errors.New("notification not found")
	ErrNotificationForbidden = errors.New("notification forbidden")
	ErrPushTokenUnregistered = errors.New("push token unregistered")
	ErrPushPermanent         = errors.New("push payload rejected")
	ErrPushExpired           = errors.New("push event expired")
)

type Notification struct {
	ID             string         `json:"id"`
	EventKey       string         `json:"event_key,omitempty"`
	Category       string         `json:"category"`
	Type           string         `json:"type"`
	Title          string         `json:"title"`
	Body           string         `json:"body"`
	ConversationID string         `json:"conversation_id,omitempty"`
	BookingID      *int64         `json:"booking_id,omitempty"`
	ItemID         *int64         `json:"item_id,omitempty"`
	Data           map[string]any `json:"data"`
	IsRead         bool           `json:"is_read"`
	UnreadCount    int            `json:"unread_count"`
	CreatedAt      time.Time      `json:"created_at"`
	UpdatedAt      time.Time      `json:"updated_at"`
	ReadAt         *time.Time     `json:"read_at,omitempty"`
}

type NotificationPage struct {
	Items       []Notification `json:"items"`
	UnreadCount int            `json:"unread_count"`
	ServerTime  time.Time      `json:"server_time"`
}

type NotificationFilter struct {
	Limit    int
	Offset   int
	Category string
}

type NotificationDevice struct {
	InstallationID string `json:"installation_id"`
	Token          string `json:"token"`
	Platform       string `json:"platform"`
}

type NotificationReadTarget struct {
	ID          string
	ReadThrough *time.Time
}

type NotificationRepository interface {
	ListNotifications(context.Context, string, NotificationFilter) (*NotificationPage, error)
	MarkNotificationsRead(context.Context, string, NotificationReadTarget) error
	RegisterNotificationDevice(context.Context, string, NotificationDevice) error
	UnregisterNotificationDevice(context.Context, string, string) error
}

// ข้อมูลอุปกรณ์และเหตุการณ์ถูกอ่านภายใต้ lease เดียวกันเพื่อไม่ส่งงานซ้ำจากหลาย worker
type NotificationDelivery struct {
	ID             string       `json:"id"`
	LeaseToken     string       `json:"lease_token"`
	DeviceID       string       `json:"device_id"`
	UserID         string       `json:"user_id"`
	Token          string       `json:"token"`
	NotificationID string       `json:"notification_id"`
	Payload        Notification `json:"payload"`
	ExpiresAt      time.Time    `json:"expires_at"`
}

type NotificationDeliveryResult struct {
	ID         string
	LeaseToken string
	Outcome    string
	ErrorCode  string
}

type NotificationDeliveryRepository interface {
	ScheduleNotificationReminders(context.Context, time.Time) error
	ClaimNotificationDeliveries(context.Context, int, time.Duration) ([]NotificationDelivery, error)
	CompleteNotificationDelivery(context.Context, NotificationDeliveryResult) error
}

type DevicePushSender interface {
	SendNotification(context.Context, NotificationDelivery) error
}
