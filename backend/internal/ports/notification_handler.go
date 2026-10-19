package ports

import (
	"errors"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
)

type NotificationHandler struct {
	repository domain.NotificationRepository
	verifier   domain.TokenVerifier
}

func NewNotificationHandler(repository domain.NotificationRepository, verifier domain.TokenVerifier) *NotificationHandler {
	return &NotificationHandler{repository: repository, verifier: verifier}
}

func (h *NotificationHandler) ListNotifications(c fiber.Ctx) error {
	c.Set("Cache-Control", "private, no-store")
	userID, ok := authenticatedUserID(c, h.verifier)
	if !ok {
		return nil
	}
	if h.repository == nil {
		return notificationUnavailable(c)
	}
	limit, err := notificationQueryInt(c.Query("limit"), 40, 1, 100)
	if err != nil {
		return notificationBadRequest(c)
	}
	offset, err := notificationQueryInt(c.Query("offset"), 0, 0, 1000000)
	if err != nil {
		return notificationBadRequest(c)
	}
	category := strings.TrimSpace(c.Query("category"))
	if category != "" && category != "chat" && category != "rental" && category != "app" {
		return notificationBadRequest(c)
	}
	page, err := h.repository.ListNotifications(c.Context(), userID, domain.NotificationFilter{Limit: limit, Offset: offset, Category: category})
	if err != nil {
		return notificationRepositoryError(c, err)
	}
	return c.JSON(page)
}

func (h *NotificationHandler) MarkNotificationRead(c fiber.Ctx) error {
	id := strings.TrimSpace(c.Params("id"))
	return h.markRead(c, domain.NotificationReadTarget{ID: id}, false)
}

func (h *NotificationHandler) MarkAllNotificationsRead(c fiber.Ctx) error {
	return h.markRead(c, domain.NotificationReadTarget{}, false)
}

func (h *NotificationHandler) MarkConversationRead(c fiber.Ctx) error {
	return h.markRead(c, domain.NotificationReadTarget{}, true)
}

func (h *NotificationHandler) markRead(c fiber.Ctx, target domain.NotificationReadTarget, conversation bool) error {
	userID, ok := authenticatedUserID(c, h.verifier)
	if !ok {
		return nil
	}
	if h.repository == nil {
		return notificationUnavailable(c)
	}
	if target.ID != "" && !notificationUUID.MatchString(target.ID) {
		return notificationBadRequest(c)
	}
	var body struct {
		ConversationID string     `json:"conversation_id"`
		ReadThrough    *time.Time `json:"read_through"`
	}
	if len(c.Body()) > 0 {
		if err := c.Bind().JSON(&body); err != nil {
			return notificationBadRequest(c)
		}
	}
	if conversation {
		target.ConversationID = strings.TrimSpace(body.ConversationID)
		if !notificationUUID.MatchString(target.ConversationID) {
			return notificationBadRequest(c)
		}
	}
	target.ReadThrough = body.ReadThrough
	if err := h.repository.MarkNotificationsRead(c.Context(), userID, target); err != nil {
		return notificationRepositoryError(c, err)
	}
	return c.JSON(fiber.Map{"status": "ok"})
}

func (h *NotificationHandler) RegisterDevice(c fiber.Ctx) error {
	userID, ok := authenticatedUserID(c, h.verifier)
	if !ok {
		return nil
	}
	if h.repository == nil {
		return notificationUnavailable(c)
	}
	var device domain.NotificationDevice
	if err := c.Bind().JSON(&device); err != nil {
		return notificationBadRequest(c)
	}
	device.InstallationID = strings.TrimSpace(device.InstallationID)
	device.Token = strings.TrimSpace(device.Token)
	device.Platform = strings.ToLower(strings.TrimSpace(device.Platform))
	if !notificationInstallationID.MatchString(device.InstallationID) || len(device.Token) < 16 || len(device.Token) > 4096 || strings.IndexFunc(device.Token, func(r rune) bool { return unicode.IsSpace(r) || unicode.IsControl(r) }) >= 0 {
		return notificationBadRequest(c)
	}
	if device.Platform != "android" && device.Platform != "ios" {
		return notificationBadRequest(c)
	}
	if err := h.repository.RegisterNotificationDevice(c.Context(), userID, device); err != nil {
		return notificationRepositoryError(c, err)
	}
	return c.JSON(fiber.Map{"status": "ok"})
}

func (h *NotificationHandler) UnregisterDevice(c fiber.Ctx) error {
	userID, ok := authenticatedUserID(c, h.verifier)
	if !ok {
		return nil
	}
	if h.repository == nil {
		return notificationUnavailable(c)
	}
	installationID := strings.TrimSpace(c.Params("installation_id"))
	if !notificationInstallationID.MatchString(installationID) {
		return notificationBadRequest(c)
	}
	if err := h.repository.UnregisterNotificationDevice(c.Context(), userID, installationID); err != nil {
		return notificationRepositoryError(c, err)
	}
	return c.JSON(fiber.Map{"status": "ok"})
}

var notificationUUID = regexp.MustCompile(`^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$`)
var notificationInstallationID = regexp.MustCompile(`^[a-zA-Z0-9._:-]{16,200}$`)

func notificationQueryInt(raw string, fallback, min, max int) (int, error) {
	if raw == "" {
		return fallback, nil
	}
	value, err := strconv.Atoi(raw)
	if err != nil || value < min || value > max {
		return 0, errors.New("invalid pagination")
	}
	return value, nil
}

func notificationBadRequest(c fiber.Ctx) error {
	return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "ข้อมูลแจ้งเตือนไม่ถูกต้อง"})
}

func notificationUnavailable(c fiber.Ctx) error {
	return c.Status(http.StatusServiceUnavailable).JSON(fiber.Map{"error": "ระบบแจ้งเตือนยังไม่พร้อมใช้งาน"})
}

func notificationRepositoryError(c fiber.Ctx, err error) error {
	if errors.Is(err, domain.ErrNotificationNotFound) {
		return c.Status(http.StatusNotFound).JSON(fiber.Map{"error": "ไม่พบแจ้งเตือน"})
	}
	if errors.Is(err, domain.ErrNotificationForbidden) {
		return c.Status(http.StatusForbidden).JSON(fiber.Map{"error": "ไม่มีสิทธิ์เข้าถึงแจ้งเตือนนี้"})
	}
	return c.Status(http.StatusInternalServerError).JSON(fiber.Map{"error": "ไม่สามารถดำเนินการแจ้งเตือนได้ กรุณาลองใหม่"})
}
