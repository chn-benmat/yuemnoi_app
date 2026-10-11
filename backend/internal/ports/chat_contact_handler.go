package ports

import (
	"errors"
	"log"
	"net/http"
	"strings"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
)

type ChatContactHandler struct {
	repository    domain.ConversationContactRepository
	tokenVerifier domain.TokenVerifier
}

type chatContactRequest struct {
	ConversationID string `json:"conversation_id" validate:"required"`
}

func NewChatContactHandler(
	repository domain.ConversationContactRepository,
	tokenVerifier domain.TokenVerifier,
) *ChatContactHandler {
	return &ChatContactHandler{
		repository:    repository,
		tokenVerifier: tokenVerifier,
	}
}

// GetConversationContact คืนเบอร์ของคู่สนทนาเฉพาะผู้ที่อยู่ในห้องแชทเท่านั้น
func (h *ChatContactHandler) GetConversationContact(c fiber.Ctx) error {
	requesterID, ok := authenticatedUserID(c, h.tokenVerifier)
	if !ok {
		return nil
	}

	var request chatContactRequest
	if err := c.Bind().JSON(&request); err != nil || strings.TrimSpace(request.ConversationID) == "" {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "กรุณาระบุห้องสนทนา"})
	}

	phone, err := h.repository.PhoneForConversation(
		c.Context(),
		requesterID,
		strings.TrimSpace(request.ConversationID),
	)
	if err != nil {
		switch {
		case errors.Is(err, domain.ErrConversationNotFound):
			return c.Status(http.StatusNotFound).JSON(fiber.Map{"error": "ไม่พบห้องสนทนา"})
		case errors.Is(err, domain.ErrContactForbidden):
			return c.Status(http.StatusForbidden).JSON(fiber.Map{"error": "คุณไม่มีสิทธิ์ดูข้อมูลติดต่อของห้องนี้"})
		case errors.Is(err, domain.ErrContactPhoneNotFound):
			return c.Status(http.StatusNotFound).JSON(fiber.Map{"error": "ผู้ใช้นี้ยังไม่ได้เพิ่มเบอร์โทรศัพท์"})
		default:
			log.Printf("load conversation contact failed: %v", err)
			return c.Status(http.StatusInternalServerError).JSON(fiber.Map{"error": "ไม่สามารถโหลดข้อมูลติดต่อได้"})
		}
	}

	return c.Status(http.StatusOK).JSON(fiber.Map{"phone": phone})
}
