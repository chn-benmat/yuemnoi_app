package ports

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
)

func operationsBusinessGuard(o domain.OperationsOptions, v domain.TokenVerifier, creatingListing bool) fiber.Handler {
	return func(c fiber.Ctx) error {
		u, ok := authenticatedUserID(c, v)
		if !ok {
			return nil
		}
		if o.Store == nil {
			return operationError(c, errors.New("operations_unavailable"))
		}
		raw, err := o.Store.RPC(c.Context(), "identity_status", map[string]any{"p_actor": u})
		if err != nil {
			return operationError(c, err)
		}
		var state struct {
			Verification *domain.RentalVerification `json:"rental_verification"`
			Control      *struct {
				Suspended bool `json:"suspended"`
			} `json:"control"`
		}
		if json.Unmarshal(raw, &state) != nil {
			return operationError(c, errors.New("operations_unavailable"))
		}
		if state.Control != nil && state.Control.Suspended {
			return c.Status(403).JSON(fiber.Map{"error": "บัญชีนี้ถูกจำกัดการทำธุรกรรมใหม่", "code": "transaction_restricted"})
		}
		if state.Verification == nil {
			return operationError(c, errors.New("operations_unavailable"))
		}
		// คำขอเช่าจากแชทอาจเปิดรายการเดิม ฐานข้อมูลตรวจเมื่อมีการเพิ่มแถวการจองจริง
		if creatingListing && !state.Verification.Complete() {
			return writeRentalVerificationRequired(c, *state.Verification)
		}
		return c.Next()
	}
}

func writeRentalVerificationRequired(c fiber.Ctx, verification domain.RentalVerification) error {
	c.Set("Cache-Control", "private, no-store")
	return c.Status(http.StatusForbidden).JSON(fiber.Map{
		"error":               "กรุณายืนยันบัตรประชาชนและบันทึกเบอร์โทรศัพท์ก่อนทำรายการ",
		"code":                "rental_verification_required",
		"rental_verification": verification,
	})
}
