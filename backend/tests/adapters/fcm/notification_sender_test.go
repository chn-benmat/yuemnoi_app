package fcm_test

import (
	"context"
	"testing"
	"time"

	"firebase.google.com/go/v4/messaging"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/fcm"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

type recordingMessageClient struct {
	message *messaging.Message
}

func (c *recordingMessageClient) Send(_ context.Context, message *messaging.Message) (string, error) {
	c.message = message
	return "message-id", nil
}

func TestReturnRemindersUseDistinctVibratingOSNotifications(t *testing.T) {
	client := &recordingMessageClient{}
	sender := fcm.NewFCMSenderWithClient(client)
	for _, kind := range []string{"rental_due_1h", "rental_due_30m"} {
		t.Run(kind, func(t *testing.T) {
			if err := sender.SendNotification(context.Background(), domain.NotificationDelivery{
				UserID: "renter", Token: "device", ExpiresAt: time.Now().Add(time.Minute),
				Payload: domain.Notification{ID: kind, Type: kind, Category: "rental", Title: "ใกล้ถึงเวลาคืนสินค้า"},
			}); err != nil {
				t.Fatal(err)
			}
			message := client.message
			if message.Notification == nil || message.Data["recipient_id"] != "renter" || message.Android.Priority != "high" {
				t.Fatal("expected an OS notification addressed to the renter")
			}
			android := message.Android.Notification
			if android.ChannelID != "yuemnoi_return_reminders_v1" || !android.DefaultVibrateTimings || android.Tag != kind {
				t.Fatalf("return reminder settings: %#v", android)
			}
			if message.Android.TTL == nil || *message.Android.TTL > time.Minute || message.APNS.Payload.Aps.Sound != "default" {
				t.Fatal("expected a deadline and the system sound")
			}
		})
	}
}
