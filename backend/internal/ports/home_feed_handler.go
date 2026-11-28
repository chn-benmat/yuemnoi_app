package ports

import (
	"errors"
	"log/slog"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
)

type homeFeedRequest struct {
	Latitude         *float64  `json:"latitude" validate:"omitempty,gte=-90,lte=90"`
	Longitude        *float64  `json:"longitude" validate:"omitempty,gte=-180,lte=180"`
	RecentCategories []*string `json:"recent_categories" validate:"omitempty,max=10,dive,required"`
	Cursor           *string   `json:"cursor"`
	Limit            *int      `json:"limit" validate:"omitempty,gte=1,lte=48"`
}

var homeFeedCursorPattern = regexp.MustCompile(`^v2:[01]:([0-9]{1,6}):([1-9][0-9]{0,18}):[1-9][0-9]{0,11}:[0-9a-f]{32}$`)

func validHomeFeedCursor(cursor string) bool {
	parts := homeFeedCursorPattern.FindStringSubmatch(cursor)
	if parts == nil {
		return false
	}
	score, _ := strconv.Atoi(parts[1])
	_, itemErr := strconv.ParseInt(parts[2], 10, 64)
	return score <= 100000 && itemErr == nil
}

func homeFeedHandler(repository domain.HomeFeedRepository, verifier domain.TokenVerifier) fiber.Handler {
	return func(c fiber.Ctx) error {
		c.Set("Cache-Control", "private, no-store")
		var viewerID *string
		if c.Get("Authorization") != "" {
			id, ok := authenticatedUserID(c, verifier)
			if !ok {
				return nil
			}
			viewerID = &id
		}

		var request homeFeedRequest
		if len(c.Body()) > 0 {
			if err := c.Bind().JSON(&request); err != nil {
				return invalidHomeFeedRequest(c, false)
			}
		}
		if (request.Latitude == nil) != (request.Longitude == nil) {
			return invalidHomeFeedRequest(c, false)
		}
		if request.Cursor != nil && !validHomeFeedCursor(*request.Cursor) {
			return invalidHomeFeedRequest(c, true)
		}

		categories := make([]string, 0, len(request.RecentCategories))
		for _, value := range request.RecentCategories {
			category := strings.TrimSpace(*value)
			if utf8.RuneCountInString(category) > 100 {
				return invalidHomeFeedRequest(c, false)
			}
			categories = append(categories, category)
		}
		limit := 24
		if request.Limit != nil {
			limit = *request.Limit
		}
		page, err := repository.GetHomeFeed(c.Context(), domain.HomeFeedQuery{
			ViewerID: viewerID, Latitude: request.Latitude, Longitude: request.Longitude,
			RecentCategories: categories, Cursor: request.Cursor, Limit: limit,
		})
		if errors.Is(err, domain.ErrInvalidHomeFeedRequest) {
			return invalidHomeFeedRequest(c, request.Cursor != nil)
		}
		if err != nil {
			// ข้อผิดพลาดจากฐานข้อมูลอาจมีพิกัดหรือข้อมูลของผู้ใช้
			slog.ErrorContext(c.Context(), "โหลดฟีดหน้าแรกจากฐานข้อมูลไม่สำเร็จ")
			return c.Status(http.StatusInternalServerError).JSON(fiber.Map{"error": "โหลดฟีดหน้าแรกไม่สำเร็จ"})
		}
		return c.JSON(page)
	}
}

func invalidHomeFeedRequest(c fiber.Ctx, cursor bool) error {
	if cursor {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{
			"error": "ข้อมูลสำหรับโหลดหน้าถัดไปไม่ถูกต้องหรือหมดอายุ", "code": "invalid_home_feed_cursor",
		})
	}
	return c.Status(http.StatusBadRequest).JSON(fiber.Map{
		"error": "ข้อมูลสำหรับโหลดฟีดหน้าแรกไม่ถูกต้อง", "code": "invalid_home_feed_request",
	})
}
