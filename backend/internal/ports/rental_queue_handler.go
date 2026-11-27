package ports

import (
	"net/http"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
)

type rentalQueuePayload struct {
	Action         string `json:"action" validate:"required,oneof=list request join accept leave"`
	ConversationID string `json:"conversation_id" validate:"required,uuid"`
	ItemID         int64  `json:"item_id" validate:"omitempty,gt=0"`
	MessageID      int64  `json:"message_id" validate:"omitempty,gt=0"`
}

func (h *RentalHandler) RentalQueue(c fiber.Ctx) error {
	actor, ok := authenticatedUserID(c, h.tokenVerifier)
	if !ok {
		return nil
	}
	var body rentalQueuePayload
	if err := c.Bind().JSON(&body); err != nil {
		return writeRentalError(c, domain.ErrInvalidRental)
	}
	switch body.Action {
	case "list":
		if body.ItemID != 0 || body.MessageID != 0 {
			return writeRentalError(c, domain.ErrInvalidRental)
		}
	case "request":
		if body.ItemID <= 0 || body.MessageID != 0 {
			return writeRentalError(c, domain.ErrInvalidRental)
		}
	case "join", "accept", "leave":
		if body.MessageID <= 0 || body.ItemID != 0 {
			return writeRentalError(c, domain.ErrInvalidRental)
		}
	default:
		return writeRentalError(c, domain.ErrInvalidRental)
	}

	repo, ok := h.rentalRepository.(domain.RentalQueueRepository)
	if !ok {
		return c.Status(http.StatusServiceUnavailable).JSON(fiber.Map{"error": "ระบบคิวเช่าต่อยังไม่พร้อมใช้งาน"})
	}
	result, err := repo.RentalQueue(c.Context(), actor, domain.RentalQueueRequest{
		Action: body.Action, ConversationID: body.ConversationID, ItemID: body.ItemID, MessageID: body.MessageID,
	})
	if err != nil {
		return writeRentalError(c, err)
	}
	c.Set("Cache-Control", "private, no-store")
	return c.JSON(result)
}
