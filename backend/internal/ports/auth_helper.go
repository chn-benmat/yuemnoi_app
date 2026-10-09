package ports

import (
	"net/http"
	"strings"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
)

// extractToken สกัดเอา JWT Token ออกจาก Authorization Header (Bearer <token>)
func extractToken(c fiber.Ctx) (string, bool) {
	authHeader := c.Get("Authorization")
	if authHeader == "" {
		_ = c.Status(http.StatusUnauthorized).JSON(fiber.Map{"error": "กรุณาแนบ Access Token ใน Header"})
		return "", false
	}

	tokenParts := strings.Split(authHeader, " ")
	if len(tokenParts) != 2 || strings.ToLower(tokenParts[0]) != "bearer" || strings.TrimSpace(tokenParts[1]) == "" {
		_ = c.Status(http.StatusUnauthorized).JSON(fiber.Map{"error": "รูปแบบ Authorization Header ไม่ถูกต้อง (ต้องเป็น Bearer <token>)"})
		return "", false
	}
	return tokenParts[1], true
}

// authenticatedUserID ดึงและตรวจสอบความถูกต้องของ Token พร้อมคืน User ID ของผู้ใช้
func authenticatedUserID(c fiber.Ctx, verifier domain.TokenVerifier) (string, bool) {
	token, ok := extractToken(c)
	if !ok {
		return "", false
	}

	if verifier == nil {
		_ = c.Status(http.StatusInternalServerError).JSON(fiber.Map{"error": "ระบบตรวจสอบสิทธิ์ไม่พร้อมใช้งาน"})
		return "", false
	}

	userID, err := verifier.UserIDFromToken(c.Context(), token)
	if err != nil || strings.TrimSpace(userID) == "" {
		_ = c.Status(http.StatusUnauthorized).JSON(fiber.Map{"error": "Access Token ไม่ถูกต้องหรือหมดอายุ"})
		return "", false
	}

	return userID, true
}
