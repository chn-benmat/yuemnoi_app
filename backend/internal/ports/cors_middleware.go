package ports

import (
	"strings"

	"github.com/gofiber/fiber/v3"
	"github.com/gofiber/fiber/v3/middleware/cors"
)

func corsMiddleware() fiber.Handler {
	methods := []string{"POST", "GET", "OPTIONS", "PUT", "DELETE", "PATCH"}
	headers := []string{"Origin", "Content-Type", "Accept", "Authorization", "X-Requested-With", "X-App-Secret"}
	handler := cors.New(cors.Config{
		AllowOriginsFunc: isAllowedOrigin,
		AllowCredentials: true,
		AllowMethods:     methods,
		AllowHeaders:     headers,
	})
	return func(c fiber.Ctx) error {
		// คง headers ของ mobile client และ OPTIONS แบบเดิม ขณะให้ Fiber จัดการ CORS preflight ปกติ
		c.Set(fiber.HeaderAccessControlAllowMethods, strings.Join(methods, ", "))
		c.Set(fiber.HeaderAccessControlAllowHeaders, strings.Join(headers, ", "))
		origin := c.Get(fiber.HeaderOrigin)
		if origin == "" {
			c.Set(fiber.HeaderAccessControlAllowOrigin, "*")
		}
		if c.Method() == fiber.MethodOptions && (origin == "" || c.Get(fiber.HeaderAccessControlRequestMethod) == "") {
			c.Vary(fiber.HeaderOrigin)
			if isAllowedOrigin(origin) {
				c.Set(fiber.HeaderAccessControlAllowOrigin, origin)
				c.Set(fiber.HeaderAccessControlAllowCredentials, "true")
			}
			return c.SendStatus(fiber.StatusNoContent)
		}
		return handler(c)
	}
}
