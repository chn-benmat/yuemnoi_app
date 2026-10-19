package ports

import (
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
	"net/http"
	"strconv"
	"strings"
)

type PushHandler struct {
	verifier  domain.TokenVerifier
	validator domain.ChatPushValidator
}

func NewPushHandler(_ domain.PushNotificationSender, gateway domain.AuthGateway) *PushHandler {
	return &PushHandler{verifier: gateway}
}

type SendChatPushRequest struct {
	ReceiverID     string `json:"receiver_id"`
	ConversationID string `json:"conversation_id"`
	MessageID      string `json:"message_id"`
	SenderName     string `json:"sender_name"`
	SenderAvatar   string `json:"sender_avatar"`
	Message        string `json:"message"`
}

// รองรับ client เดิมโดยตรวจข้อความจริง แต่ไม่ส่งซ้ำกับ outbox จาก database trigger
func (h *PushHandler) SendChatPush(c fiber.Ctx) error {
	senderID, ok := authenticatedUserID(c, h.verifier)
	if !ok {
		return nil
	}
	var req SendChatPushRequest
	if err := c.Bind().JSON(&req); err != nil {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "ข้อมูลแจ้งเตือนไม่ถูกต้อง"})
	}
	req.ReceiverID = strings.TrimSpace(req.ReceiverID)
	req.ConversationID = strings.TrimSpace(req.ConversationID)
	messageID, err := strconv.ParseInt(req.MessageID, 10, 64)
	if err != nil || messageID <= 0 || !notificationUUID.MatchString(req.ReceiverID) || !notificationUUID.MatchString(req.ConversationID) || req.ReceiverID == senderID {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "กรุณาระบุข้อความและคู่สนทนาที่ถูกต้อง"})
	}
	if h.validator == nil {
		return c.Status(http.StatusServiceUnavailable).JSON(fiber.Map{"error": "ระบบแจ้งเตือนยังไม่พร้อม"})
	}
	if err := h.validator.ValidateChatPush(c.Context(), senderID, domain.ChatPushNotification{ReceiverID: req.ReceiverID, ConversationID: req.ConversationID, MessageID: req.MessageID}); err != nil {
		return c.Status(http.StatusForbidden).JSON(fiber.Map{"error": "ไม่มีสิทธิ์ส่งแจ้งเตือนข้อความนี้"})
	}
	return c.JSON(fiber.Map{"status": "recorded"})
}
