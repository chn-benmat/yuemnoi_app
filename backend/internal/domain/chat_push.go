package domain

import "context"

// ตรวจข้อความจริงและคู่สนทนา ไม่เชื่อข้อมูลผู้รับ/เนื้อหาที่ส่งจาก client
type ChatPushValidator interface {
	ValidateChatPush(context.Context, string, ChatPushNotification) error
}
