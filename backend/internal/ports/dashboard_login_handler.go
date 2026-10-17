package ports

import (
	"errors"
	"net/http"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
)

// ออก token สำหรับ dashboard หลังตรวจสิทธิ์เจ้าหน้าที่จากฐานข้อมูลแล้วเท่านั้น
func dashboardLogin(gateway domain.AuthGateway, store domain.OperationsStore) fiber.Handler {
	return func(c fiber.Ctx) error {
		c.Set("Cache-Control", "private, no-store")
		var req userLoginRequest
		if err := c.Bind().JSON(&req); err != nil {
			return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "กรุณากรอกอีเมลและรหัสผ่านให้ถูกต้อง"})
		}
		if store == nil {
			return operationError(c, errors.New("operations_unavailable"))
		}
		tokens, err := gateway.Login(c.Context(), req.Email, req.Password)
		if err != nil {
			return c.Status(http.StatusUnauthorized).JSON(fiber.Map{"error": "อีเมลหรือรหัสผ่านไม่ถูกต้อง"})
		}
		userID, err := gateway.UserIDFromToken(c.Context(), tokens.AccessToken)
		if err != nil || userID == "" {
			return appTokenError(c, err)
		}
		if _, err := store.RPC(c.Context(), "admin_read", map[string]any{"p_actor": userID, "p_module": "me"}); err != nil {
			return operationError(c, err)
		}
		return c.JSON(fiber.Map{"access_token": tokens.AccessToken, "refresh_token": tokens.RefreshToken})
	}
}
