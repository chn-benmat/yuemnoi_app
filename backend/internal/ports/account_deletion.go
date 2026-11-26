package ports

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
)

type accountDeletionHandler struct {
	repository domain.AccountDeletionRepository
	verifier   domain.TokenVerifier
}

func (h accountDeletionHandler) actor(c fiber.Ctx) (userID, token string, ok bool) {
	c.Set("Cache-Control", "private, no-store")
	token, ok = extractToken(c)
	if !ok {
		return "", "", false
	}
	if h.repository == nil || h.verifier == nil {
		_ = accountDeletionError(c, "operations_unavailable")
		return "", "", false
	}
	userID, err := h.verifier.UserIDFromToken(c.Context(), token)
	var pending *domain.PendingAccountDeletion
	if errors.As(err, &pending) && pending.DeleteAfter.After(time.Now()) {
		// โทเคนที่ตรวจแล้วของบัญชีรอลบใช้ได้เฉพาะเส้นทางการลบและกู้คืน
		return pending.UserID, token, true
	}
	if err != nil || userID == "" {
		_ = appTokenError(c, err)
		return "", "", false
	}
	return userID, token, true
}

func (h accountDeletionHandler) schedule(c fiber.Ctx) error {
	userID, _, ok := h.actor(c)
	if !ok {
		return nil
	}
	deleteAfter, err := h.repository.Schedule(c.Context(), userID)
	if err != nil {
		return accountDeletionError(c, err.Error())
	}
	return c.JSON(fiber.Map{"delete_after": deleteAfter})
}

func (h accountDeletionHandler) restore(c fiber.Ctx) error {
	userID, token, ok := h.actor(c)
	if !ok {
		return nil
	}
	sessionID := authenticatedSessionID(token)
	if sessionID == "" {
		return accountDeletionError(c, "account_reauth_required")
	}
	if err := h.repository.Restore(c.Context(), userID, sessionID); err != nil {
		return accountDeletionError(c, err.Error())
	}
	return c.JSON(fiber.Map{"user_id": userID})
}

// อ่าน session_id เฉพาะจากโทเคนที่ Auth ตรวจลายเซ็นและเจ้าของแล้ว
func authenticatedSessionID(token string) string {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return ""
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return ""
	}
	var claims struct {
		SessionID string `json:"session_id"`
	}
	if json.Unmarshal(payload, &claims) != nil || !validUUID(claims.SessionID) {
		return ""
	}
	return claims.SessionID
}

func accountDeletionError(c fiber.Ctx, code string) error {
	status := http.StatusServiceUnavailable
	message := "จัดการบัญชีไม่สำเร็จ กรุณาลองใหม่"
	switch code {
	case "active_rentals":
		status = http.StatusConflict
		message = "กรุณาจัดการรายการเช่าที่ยังค้างให้เรียบร้อยก่อนลบบัญชี"
	case "account_staff_protected":
		status = http.StatusConflict
		message = "บัญชีนี้ยังเป็นเจ้าหน้าที่คนสุดท้าย กรุณาจัดการสิทธิ์เจ้าหน้าที่ก่อนลบบัญชี"
	case "account_reauth_required":
		status = http.StatusUnauthorized
		message = "กรุณาเข้าสู่ระบบใหม่เพื่อยืนยันการกู้คืนบัญชี"
	case "account_deletion_expired":
		status = http.StatusGone
		message = "บัญชีนี้พ้นระยะเวลากู้คืนแล้ว"
	default:
		code = "operations_unavailable"
	}
	return c.Status(status).JSON(fiber.Map{"error": message, "code": code})
}
