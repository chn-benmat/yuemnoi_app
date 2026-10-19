package fcm_test

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	"firebase.google.com/go/v4/messaging"
	fcm "github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/fcm"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

type recordingMessageClient struct {
	message *messaging.Message
	err     error
}

func (c *recordingMessageClient) Send(_ context.Context, message *messaging.Message) (string, error) {
	c.message = message
	return "message-id", c.err
}

func notificationMessage(t *testing.T, delivery domain.NotificationDelivery) *messaging.Message {
	t.Helper()
	if delivery.Token == "" {
		delivery.Token = "device"
	}
	client := &recordingMessageClient{}
	if err := fcm.NewFCMSenderWithClient(nil, client, nil).SendNotification(context.Background(), delivery); err != nil {
		t.Fatal(err)
	}
	return client.message
}

func TestGroupedChatUsesUniqueMessageEventAndOutboxExpiry(t *testing.T) {
	expires := time.Now().UTC().Add(2 * time.Minute)
	m := notificationMessage(t, domain.NotificationDelivery{
		ExpiresAt: expires,
		Payload: domain.Notification{ID: "inbox", EventKey: "chat:group", Category: "chat", Type: "chat_message", Data: map[string]any{
			"event_key": "chat-message:123:user", "message_id": float64(123), "event_at": "2026-10-19T00:00:00Z", "destination": "/chat/detail",
		}},
	})
	if m.Data["event_key"] != "chat-message:123:user" || m.Data["message_id"] != "123" || m.Data["event_at"] == "" || m.Data["destination"] != "/chat/detail" {
		t.Fatalf("event payload=%#v", m.Data)
	}
	if m.Android.TTL == nil || *m.Android.TTL > 2*time.Minute || *m.Android.TTL < time.Minute || m.APNS.Headers["apns-expiration"] == "" || m.Data["expires_at"] == "" {
		t.Fatalf("expiry not applied: %#v", m)
	}
	client := &recordingMessageClient{}
	sender := fcm.NewFCMSenderWithClient(nil, client, nil)
	err := sender.SendNotification(context.Background(), domain.NotificationDelivery{Token: "device", ExpiresAt: time.Now().Add(-time.Minute)})
	if err != domain.ErrPushExpired || client.message != nil {
		t.Fatalf("expired job sent: err=%v", err)
	}
}

func TestNotificationSendUsesClaimedDeviceAndStableConversationTag(t *testing.T) {
	client := &recordingMessageClient{}
	legacy := &cacheTokenManager{token: "wrong-legacy-device"}
	sender := fcm.NewFCMSenderWithClient(legacy, client, nil)
	delivery := domain.NotificationDelivery{
		Token: "claimed-device", UserID: "recipient", NotificationID: "inbox-id",
		Payload: domain.Notification{Category: "chat", Type: "chat_message", Title: "ผู้ส่ง", Body: "สวัสดี", ConversationID: "room", EventKey: "chat:123"},
	}
	if err := sender.SendNotification(context.Background(), delivery); err != nil {
		t.Fatal(err)
	}
	m := client.message
	if m.Token != "claimed-device" || legacy.reads != 0 || legacy.deletes != 0 {
		t.Fatal("new delivery used legacy account token")
	}
	if m.Notification == nil || m.Data["notification_id"] != "inbox-id" || m.Data["recipient_id"] != "recipient" || m.Data["event_key"] != "chat:123" {
		t.Fatalf("routing payload=%#v", m.Data)
	}
	if m.Android.Notification.Tag != "chat_room" || m.Android.Notification.ChannelID != "yuemnoi_chat_messages_v3" {
		t.Fatalf("Android config=%#v", m.Android.Notification)
	}
	if m.Android.Notification.ClickAction != "" {
		t.Fatal("custom click action without a manifest handler")
	}
}

func TestNotificationPayloadBoundsUTF8AndSelectsRentalChannel(t *testing.T) {
	bookingID, itemID := int64(12), int64(9)
	delivery := domain.NotificationDelivery{Token: "device", Payload: domain.Notification{
		ID: "event", Category: "rental", Type: "rental_confirmed", Title: strings.Repeat("ก", 1000), Body: strings.Repeat("สวัสดี", 1000), BookingID: &bookingID, ItemID: &itemID,
		Data: map[string]any{"private_unrelated_field": strings.Repeat("secret", 2000)},
	}}
	m := notificationMessage(t, delivery)
	if m.Android.Notification.ChannelID != "yuemnoi_rental_updates_v1" || m.Data["booking_id"] != "12" || m.Data["item_id"] != "9" {
		t.Fatalf("rental payload=%#v", m.Data)
	}
	if !utf8.ValidString(m.Notification.Title) || !utf8.ValidString(m.Notification.Body) {
		t.Fatal("truncated payload corrupts Thai UTF-8")
	}
	if len(m.Notification.Title) > 180 || len(m.Notification.Body) > 700 {
		t.Fatal("unbounded notification text")
	}
	if _, ok := m.Data["private_unrelated_field"]; ok {
		t.Fatal("arbitrary private data was included in OS payload")
	}
	encoded, err := json.Marshal(m)
	if err != nil || len(encoded) > 4096 {
		t.Fatalf("payload bytes=%d err=%v", len(encoded), err)
	}
}
