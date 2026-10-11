package ports

import (
	"encoding/json"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
)

// ตรวจรายการใหม่เท่านั้น เพื่อให้ผู้ใช้ดำเนินภาระการส่งคืนเดิมได้
func operationsBusinessGuard(o domain.OperationsOptions, v domain.TokenVerifier) fiber.Handler {
	return func(c fiber.Ctx) error {
		if o.Store == nil || c.Method() != "POST" || (c.Path() != "/api/items" && c.Path() != "/api/rentals") {
			return c.Next()
		}
		u, ok := authenticatedUserID(c, v)
		if !ok {
			return nil
		}
		raw, err := o.Store.RPC(c.Context(), "identity_status", map[string]any{"p_actor": u})
		if err != nil {
			return operationError(c, err)
		}
		var state struct {
			CanList     bool `json:"can_list"`
			Enforcement bool `json:"enforcement"`
			Control     *struct {
				Suspended bool `json:"suspended"`
			} `json:"control"`
		}
		if json.Unmarshal(raw, &state) != nil {
			return c.SendStatus(503)
		}
		if state.Control != nil && state.Control.Suspended {
			return c.Status(403).JSON(fiber.Map{"error": "บัญชีนี้ถูกจำกัดการทำธุรกรรมใหม่", "code": "transaction_restricted"})
		}
		if c.Path() == "/api/items" && state.Enforcement && !state.CanList {
			return c.Status(403).JSON(fiber.Map{"error": "กรุณายืนยันตัวตนก่อนปล่อยเช่าสินค้า", "code": "identity_required"})
		}
		return c.Next()
	}
}
