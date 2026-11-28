package fcm

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"cloud.google.com/go/auth/credentials"
	"cloud.google.com/go/auth/httptransport"
	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"google.golang.org/api/option"
)

const pushTimeout = 10 * time.Second

type FCMSender struct {
	client MessageClient
}

// MessageClient เป็นขอบเขตสำหรับส่งข้อความผ่าน Firebase SDK หรือ client ที่ฉีดเข้ามา
type MessageClient interface {
	Send(context.Context, *messaging.Message) (string, error)
}

// เส้นทางใหม่ส่งไปยัง token ของงานที่ถูก claim โดยไม่อ่านหรือแก้ token ของบัญชีอื่น
func (s *FCMSender) SendNotification(ctx context.Context, delivery domain.NotificationDelivery) error {
	if s == nil || s.client == nil {
		return errors.New("Firebase messaging is not configured")
	}
	if strings.TrimSpace(delivery.Token) == "" {
		return domain.ErrPushTokenUnregistered
	}
	if !delivery.ExpiresAt.IsZero() && !delivery.ExpiresAt.After(time.Now()) {
		return domain.ErrPushExpired
	}
	ctx, cancel := context.WithTimeout(ctx, pushTimeout)
	defer cancel()
	_, err := s.client.Send(ctx, buildNotificationMessage(delivery))
	if messaging.IsUnregistered(err) {
		return domain.ErrPushTokenUnregistered
	}
	if messaging.IsInvalidArgument(err) {
		return domain.ErrPushPermanent
	}
	return err
}

func buildNotificationMessage(delivery domain.NotificationDelivery) *messaging.Message {
	n := delivery.Payload
	if n.ID == "" {
		n.ID = delivery.NotificationID
	}
	title, body := notificationText(n.Title, 180), notificationText(n.Body, 700)
	if title == "" {
		title = "Yuemnoi"
	}
	if body == "" {
		body = "คุณมีการแจ้งเตือนใหม่"
	}
	channelID := "yuemnoi_app_updates_v1"
	vibrate := n.Type == "rental_due_1h" || n.Type == "rental_due_30m"
	tag := n.ID
	if n.Category == "chat" {
		channelID = "yuemnoi_chat_messages_v3"
		if n.Type == "chat_message" && n.ConversationID != "" {
			tag = "chat_" + n.ConversationID
		}
	} else if n.Category == "rental" {
		channelID = "yuemnoi_rental_updates_v1"
		if vibrate {
			channelID = "yuemnoi_return_reminders_v1"
		}
	}
	data := map[string]string{
		"notification_id": n.ID, "recipient_id": delivery.UserID, "category": n.Category, "type": n.Type,
		"title": title, "body": body, "event_key": n.EventKey,
		"conversation_id": n.ConversationID, "unread_count": strconv.Itoa(n.UnreadCount),
	}
	if n.BookingID != nil {
		data["booking_id"] = strconv.FormatInt(*n.BookingID, 10)
	}
	if n.ItemID != nil {
		data["item_id"] = strconv.FormatInt(*n.ItemID, 10)
	}
	if !n.UpdatedAt.IsZero() {
		data["updated_at"] = n.UpdatedAt.UTC().Format(time.RFC3339Nano)
	}
	for _, key := range []string{"message_id", "sender_name", "sender_avatar"} {
		if value, ok := n.Data[key].(string); ok {
			data[key] = notificationText(value, 300)
		}
	}
	if data["event_key"] == "" {
		data["event_key"] = n.ID
	}
	for _, key := range []string{"event_key", "event_at", "destination", "message_id"} {
		if value := notificationScalar(n.Data[key]); value != "" {
			data[key] = notificationText(value, 200)
		}
	}
	if data["event_at"] == "" {
		data["event_at"] = data["updated_at"]
	}
	expiresAt := delivery.ExpiresAt
	if expiresAt.IsZero() {
		expiresAt = time.Now().UTC().Add(24 * time.Hour)
	}
	ttl := time.Until(expiresAt)
	if ttl < 0 {
		ttl = 0
	}
	if ttl > 28*24*time.Hour {
		ttl = 28 * 24 * time.Hour
	}
	data["expires_at"] = expiresAt.UTC().Format(time.RFC3339Nano)
	return &messaging.Message{
		Token:        delivery.Token,
		Notification: &messaging.Notification{Title: title, Body: body},
		Data:         data,
		Android: &messaging.AndroidConfig{
			Priority: "high",
			TTL:      &ttl,
			Notification: &messaging.AndroidNotification{
				ChannelID: channelID, Tag: tag, Icon: "ic_notification",
				DefaultSound: true, DefaultVibrateTimings: vibrate, Visibility: messaging.VisibilityPrivate,
			},
		},
		APNS: &messaging.APNSConfig{
			Headers: map[string]string{"apns-priority": "10", "apns-collapse-id": tag, "apns-expiration": strconv.FormatInt(expiresAt.Unix(), 10)},
			Payload: &messaging.APNSPayload{Aps: &messaging.Aps{Sound: "default", ThreadID: tag}},
		},
	}
}

func notificationScalar(value any) string {
	switch v := value.(type) {
	case string:
		return v
	case float64:
		return strconv.FormatFloat(v, 'f', -1, 64)
	case json.Number:
		return v.String()
	case int64:
		return strconv.FormatInt(v, 10)
	case int:
		return strconv.Itoa(v)
	default:
		return ""
	}
}

func notificationText(value string, maxBytes int) string {
	value = strings.TrimSpace(value)
	if len(value) <= maxBytes {
		return value
	}
	end := maxBytes - len("…")
	for end > 0 && !utf8.RuneStart(value[end]) {
		end--
	}
	return value[:end] + "…"
}

func NewFCMSender(saPath, saJSON string, httpClient *http.Client) (*FCMSender, error) {
	sender := NewFCMSenderWithClient(nil)
	data, err := loadServiceAccount(saPath, saJSON)
	if err != nil {
		return sender, err
	}
	var account struct {
		Type      string `json:"type"`
		ProjectID string `json:"project_id"`
	}
	if err := json.Unmarshal(data, &account); err != nil {
		return sender, fmt.Errorf("invalid Firebase service account JSON: %w", err)
	}
	if account.Type != "service_account" || strings.TrimSpace(account.ProjectID) == "" {
		return sender, fmt.Errorf("Firebase service account requires type service_account and project_id")
	}
	baseClient := http.Client{Timeout: pushTimeout}
	if httpClient != nil {
		baseClient = *httpClient
		if baseClient.Timeout <= 0 {
			baseClient.Timeout = pushTimeout
		}
	}
	baseTransport := baseClient.Transport
	if baseTransport == nil {
		baseTransport = http.DefaultTransport
		if standard, ok := baseTransport.(*http.Transport); ok && httpClient == nil {
			pool := standard.Clone()
			pool.MaxIdleConns = 100
			pool.MaxIdleConnsPerHost = 20
			baseTransport = pool
		}
	}
	baseClient.Transport = baseTransport
	// ใช้ request context ทั้งตอนแลก OAuth token และตอนส่ง FCM เพื่อยกเลิกได้ทันที
	authClient, err := httptransport.NewClient(&httptransport.Options{
		BaseRoundTripper: baseTransport,
		DetectOpts: &credentials.DetectOptions{
			CredentialsJSON:     data,
			Scopes:              []string{"https://www.googleapis.com/auth/firebase.messaging"},
			Client:              &baseClient,
			DisableAsyncRefresh: true,
		},
	})
	if err != nil {
		return sender, fmt.Errorf("initialize Firebase credentials: %w", err)
	}
	// แยก client สำหรับ FCM ออกจาก client แลก token เพื่อไม่ให้ transport เรียกตัวเอง
	messagingHTTPClient := baseClient
	messagingHTTPClient.Transport = authClient.Transport
	app, err := firebase.NewApp(context.Background(), &firebase.Config{ProjectID: account.ProjectID}, option.WithHTTPClient(&messagingHTTPClient))
	if err != nil {
		return sender, fmt.Errorf("initialize Firebase app: %w", err)
	}
	sender.client, err = app.Messaging(context.Background())
	if err != nil {
		return sender, fmt.Errorf("initialize Firebase messaging: %w", err)
	}
	return sender, nil
}

func NewFCMSenderWithClient(client MessageClient) *FCMSender {
	return &FCMSender{client: client}
}

func loadServiceAccount(path, inline string) ([]byte, error) {
	if inline != "" {
		return []byte(inline), nil
	}
	if path == "" {
		return nil, errors.New("Firebase service account is not configured")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, errors.New("cannot read Firebase service account file")
	}
	return data, nil
}
