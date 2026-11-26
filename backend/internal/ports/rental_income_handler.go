package ports

import (
	"log/slog"
	"net/http"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
)

func (h *RentalHandler) RentalIncome(c fiber.Ctx) error {
	userID, ok := authenticatedUserID(c, h.tokenVerifier)
	if !ok {
		return nil
	}
	c.Set("Cache-Control", "private, no-store")

	repo, ok := h.rentalRepository.(domain.RentalIncomeRepository)
	if !ok {
		return c.Status(http.StatusServiceUnavailable).JSON(fiber.Map{"error": "ระบบรายได้การปล่อยเช่ายังไม่พร้อมใช้งาน"})
	}
	summary, err := repo.GetRentalIncome(c.Context(), userID)
	if err != nil {
		slog.ErrorContext(c.Context(), "read rental income", "error", err)
		return c.Status(http.StatusInternalServerError).JSON(fiber.Map{"error": "โหลดข้อมูลรายได้ไม่สำเร็จ"})
	}
	return c.JSON(summary)
}
