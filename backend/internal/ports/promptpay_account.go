package ports

import (
	"log/slog"
	"net/http"
	"strings"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
)

type promptPayAccountRequest struct {
	Phone      string `json:"promptpay_phone" validate:"max=32"`
	NationalID string `json:"promptpay_national_id" validate:"max=32"`
}

func bindPromptPayAccount(c fiber.Ctx) (promptPayAccountRequest, string) {
	var req promptPayAccountRequest
	if err := c.Bind().JSON(&req); err != nil {
		return req, "ข้อมูลพร้อมเพย์ไม่ถูกต้อง"
	}
	req.Phone = strings.TrimSpace(req.Phone)
	req.NationalID = strings.TrimSpace(req.NationalID)
	switch {
	case (req.Phone == "") == (req.NationalID == ""):
		return req, "กรุณาเลือกเบอร์มือถือหรือเลขบัตรประชาชนอย่างใดอย่างหนึ่ง"
	case req.Phone != "" && !domain.IsPromptPayMobile(req.Phone):
		return req, "กรุณากรอกเบอร์มือถือพร้อมเพย์ 10 หลัก"
	case req.NationalID != "" && !domain.IsPromptPayNationalID(req.NationalID):
		return req, "เลขบัตรประชาชนไม่ถูกต้อง กรุณาตรวจสอบทั้ง 13 หลัก"
	}
	return req, ""
}

func (h *RentalHandler) PromptPaySettings(c fiber.Ctx) error {
	c.Set("Cache-Control", "private, no-store")
	userID, ok := authenticatedUserID(c, h.tokenVerifier)
	if !ok {
		return nil
	}
	repo, ok := h.rentalRepository.(domain.PromptPayAccountRepository)
	if !ok {
		return c.Status(http.StatusServiceUnavailable).JSON(fiber.Map{"error": "ระบบจัดการพร้อมเพย์ยังไม่พร้อมใช้งาน"})
	}
	var account domain.PromptPayAccount
	var err error
	if c.Method() == http.MethodPut {
		req, message := bindPromptPayAccount(c)
		if message != "" {
			return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": message})
		}
		account, err = repo.UpdatePromptPayAccount(c.Context(), userID, req.Phone, req.NationalID)
	} else {
		account, err = repo.GetPromptPayAccount(c.Context(), userID)
	}
	if err != nil {
		// ข้อผิดพลาดจากฐานข้อมูลอาจมีข้อมูลพร้อมเพย์ของผู้ใช้
		slog.ErrorContext(c.Context(), "PromptPay settings request failed", "method", c.Method())
		return c.Status(http.StatusInternalServerError).JSON(fiber.Map{"error": "จัดการข้อมูลพร้อมเพย์ไม่สำเร็จ กรุณาลองใหม่"})
	}
	return c.JSON(account)
}
