package ports

import (
	"net/http"
	"strings"
	"unicode/utf8"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
)

func (h *ItemHandler) GetAutoReply(c fiber.Ctx) error {
	userID, ok := authenticatedUserID(c, h.tokenVerifier)
	if !ok {
		return nil
	}
	id, ok := parseItemID(c)
	if !ok {
		return nil
	}
	settings, err := h.repo.GetAutoReply(c.Context(), id, userID)
	if err != nil {
		return writeItemError(c, err)
	}
	return c.JSON(settings)
}

func (h *ItemHandler) SaveAutoReply(c fiber.Ctx) error {
	userID, ok := authenticatedUserID(c, h.tokenVerifier)
	if !ok {
		return nil
	}
	id, ok := parseItemID(c)
	if !ok {
		return nil
	}
	var request struct {
		Enabled *bool   `json:"enabled"`
		Message *string `json:"message"`
	}
	if err := c.Bind().JSON(&request); err != nil || request.Enabled == nil || request.Message == nil {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "กรุณาระบุสถานะและข้อความตอบกลับ"})
	}
	message := strings.TrimSpace(*request.Message)
	if utf8.RuneCountInString(message) > 500 {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "ข้อความตอบกลับต้องไม่เกิน 500 ตัวอักษร"})
	}
	if *request.Enabled && message == "" {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "กรุณาพิมพ์ข้อความก่อนเปิดการตอบกลับอัตโนมัติ"})
	}
	settings, err := h.repo.SaveAutoReply(c.Context(), id, userID, domain.ItemAutoReply{Enabled: *request.Enabled, Message: message})
	if err != nil {
		return writeItemError(c, err)
	}
	return c.JSON(settings)
}
