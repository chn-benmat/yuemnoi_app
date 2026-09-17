package domain

import "context"

// ChatPushNotification ข้อมูลสำหรับส่งการแจ้งเตือนข้อความแชท
type ChatPushNotification struct {
	ReceiverID     string
	ConversationID string
	MessageID      string
	SenderName     string
	SenderAvatar   string
	Message        string
}

// PushNotificationSender พอร์ต (Outbound Port) สำหรับการส่ง Push Notification ไปยังผู้ใช้งาน
type PushNotificationSender interface {
	SendChatPush(ctx context.Context, notification ChatPushNotification) error
}
