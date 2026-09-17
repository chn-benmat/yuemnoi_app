package ports

import (
	"context"
	"log/slog"
	"net/http"
	"strings"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gin-gonic/gin"
)

// PushHandler จัดการคำขอ HTTP สำหรับการส่ง Push Notification
type PushHandler struct {
	sender   domain.PushNotificationSender
	auth     domain.AuthGateway
	verifier domain.TokenVerifier
}

// NewPushHandler สร้าง PushHandler ใหม่โดยรับ PushNotificationSender และ AuthGateway เข้ามาผ่าน DI
func NewPushHandler(sender domain.PushNotificationSender, authGateway domain.AuthGateway) *PushHandler {
	return &PushHandler{
		sender:   sender,
		auth:     authGateway,
		verifier: authGateway,
	}
}

// SendChatPushRequest เป็น request body สำหรับส่ง push notification ของข้อความแชท
type SendChatPushRequest struct {
	ReceiverID     string `json:"receiver_id" binding:"required"`
	ConversationID string `json:"conversation_id" binding:"required"`
	MessageID      string `json:"message_id"`
	SenderName     string `json:"sender_name"`
	SenderAvatar   string `json:"sender_avatar"`
	Message        string `json:"message"`
}

// SendChatPush รับคำขอส่ง Push Notification ของข้อความแชทและประมวลผลใน Background (Non-blocking)
func (h *PushHandler) SendChatPush(c *gin.Context) {
	senderID, ok := authenticatedUserID(c, h.verifier)
	if !ok {
		return
	}

	var req SendChatPushRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลไม่ครบถ้วน: " + err.Error()})
		return
	}

	if senderID == req.ReceiverID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ไม่สามารถส่งแจ้งเตือนหาตนเองได้"})
		return
	}

	// ค้นหาชื่อและรูปของผู้ส่งตัวจริงจากฐานข้อมูลเพื่อป้องกันการปลอมแปลงชื่อผู้ส่ง (Sender Spoofing)
	senderName := "ผู้ใช้งาน Yuemnoi"
	senderAvatar := ""
	if h.auth != nil {
		if profile, err := h.auth.GetProfile(c.Request.Context(), senderID); err == nil && profile != nil {
			if profile.DisplayName != "" {
				senderName = profile.DisplayName
			} else if profile.Email != "" {
				if idx := strings.Index(profile.Email, "@"); idx != -1 {
					senderName = profile.Email[:idx]
				}
			}
			senderAvatar = profile.UserImageURL
		}
	}

	// ตอบกลับ 200 OK ให้ Client ทันทีแบบ Non-blocking Fast Response
	c.JSON(http.StatusOK, gin.H{"status": "queued"})

	if h.sender == nil {
		return
	}

	// ประมวลผลและยิง Push Notification ใน Background Goroutine โดยใช้ชื่อและรูปที่ตรวจสอบแล้ว
	go func(r SendChatPushRequest, sName, sAvatar string) {
		err := h.sender.SendChatPush(context.Background(), domain.ChatPushNotification{
			ReceiverID:     r.ReceiverID,
			ConversationID: r.ConversationID,
			MessageID:      r.MessageID,
			SenderName:     sName,
			SenderAvatar:   sAvatar,
			Message:        r.Message,
		})
		if err != nil {
			slog.Error("ส่ง FCM chat push ใน background ล้มเหลว",
				slog.String("receiver_id", r.ReceiverID),
				slog.String("conversation_id", r.ConversationID),
				slog.Any("error", err),
			)
		}
	}(req, senderName, senderAvatar)
}
