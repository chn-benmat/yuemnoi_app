package ports

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
)

const dashboardOnlyMessage = "บัญชีนี้ใช้ได้เฉพาะ Dashboard สำหรับเจ้าหน้าที่ กรุณาใช้บัญชีผู้ใช้ทั่วไปในแอป"

// แยกตัวตรวจสิทธิ์ของแอปจาก dashboard แม้ใช้ผู้ให้บริการ Auth เดียวกัน
type appTokenVerifier struct {
	domain.AuthGateway
}

func (v appTokenVerifier) UserIDFromToken(ctx context.Context, token string) (string, error) {
	return v.AppUserIDFromToken(ctx, token)
}

func appTokenError(c fiber.Ctx, err error) error {
	if errors.Is(err, domain.ErrDashboardOnly) {
		return c.Status(http.StatusForbidden).JSON(fiber.Map{"error": dashboardOnlyMessage, "code": "dashboard_only"})
	}
	var pending *domain.PendingAccountDeletion
	if errors.As(err, &pending) {
		c.Set("Cache-Control", "private, no-store")
		if !pending.DeleteAfter.After(time.Now()) {
			return accountDeletionError(c, "account_deletion_expired")
		}
		return c.Status(http.StatusConflict).JSON(fiber.Map{
			"error": "บัญชีนี้กำลังรอลบ กรุณายืนยันเพื่อกู้คืนบัญชี",
			"code":  "account_deletion_pending", "delete_after": pending.DeleteAfter,
		})
	}
	return c.Status(http.StatusUnauthorized).JSON(fiber.Map{"error": "Access Token ไม่ถูกต้องหรือหมดอายุ"})
}

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
		_ = appTokenError(c, err)
		return "", false
	}

	return userID, true
}
