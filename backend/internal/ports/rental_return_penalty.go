package ports

import (
	"errors"
	"net/http"
	"strings"
	"unicode/utf8"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
)

func (h *RentalHandler) SaveRentalReturnPenalty(c fiber.Ctx) error {
	user, ok := authenticatedUserID(c, h.tokenVerifier)
	if !ok {
		return nil
	}
	id, ok := parseRentalID(c)
	if !ok {
		return nil
	}
	repo, ok := h.rentalRepository.(domain.RentalReturnPenaltyRepository)
	if !ok {
		return c.Status(http.StatusServiceUnavailable).JSON(fiber.Map{"error": "ระบบบันทึกรายงานการคืนยังไม่พร้อมใช้งาน"})
	}
	var req struct {
		Damaged bool   `json:"damaged"`
		Late    bool   `json:"late"`
		Details string `json:"details" validate:"max=2000"`
	}
	if c.Bind().JSON(&req) != nil {
		return writeRentalStatusError(c, domain.ErrInvalidRental)
	}
	details := strings.TrimSpace(req.Details)
	if (!req.Damaged && !req.Late) || (req.Damaged && details == "") || utf8.RuneCountInString(details) > 2000 {
		return writeRentalStatusError(c, domain.ErrInvalidRental)
	}
	report, err := repo.SaveRentalReturnPenalty(c.Context(), user, id, domain.RentalReturnPenaltyReport{
		Damaged: req.Damaged, Late: req.Late, Details: details,
	})
	if err != nil {
		return writeRentalStatusError(c, err)
	}
	c.Set("Cache-Control", "private, no-store")
	return c.JSON(report)
}

func (h *RentalHandler) GetRentalReturnPenaltyQR(c fiber.Ctx) error {
	user, ok := authenticatedUserID(c, h.tokenVerifier)
	if !ok {
		return nil
	}
	id, ok := parseRentalID(c)
	if !ok {
		return nil
	}
	c.Set("Cache-Control", "private, no-store")
	repo, ok := h.rentalRepository.(domain.RentalReturnPenaltyRepository)
	if !ok {
		return c.Status(http.StatusServiceUnavailable).JSON(fiber.Map{"error": "ระบบรับค่าปรับยังไม่พร้อมใช้งาน"})
	}
	qr, err := repo.RentalReturnPenaltyQR(c.Context(), user, id)
	switch {
	case errors.Is(err, domain.ErrReturnPenaltyNoAmount):
		return c.Status(http.StatusConflict).JSON(fiber.Map{"error": "ยังไม่มีค่าปรับสำหรับรายการนี้"})
	case errors.Is(err, domain.ErrReturnPenaltyNoAccount):
		return c.Status(http.StatusConflict).JSON(fiber.Map{
			"code":  "promptpay_account_required",
			"error": "กรุณาตั้งค่าบัญชีพร้อมเพย์สำหรับรับเงิน แล้วลองอีกครั้ง",
		})
	case err != nil:
		return writeRentalStatusError(c, err)
	default:
		return c.JSON(fiber.Map{"promptpay_qr": qr})
	}
}
