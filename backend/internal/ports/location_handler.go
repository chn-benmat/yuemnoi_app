package ports

import (
	"context"
	"errors"
	"math"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
)

type LocationHandler struct {
	geocoder  domain.Geocoder
	suggester domain.PlaceSuggester
}

func NewLocationHandler(geocoder domain.Geocoder, suggesters ...domain.PlaceSuggester) *LocationHandler {
	h := &LocationHandler{geocoder: geocoder}
	if len(suggesters) > 0 {
		h.suggester = suggesters[0]
	}
	return h
}

func locationError(c fiber.Ctx, err error) error {
	if errors.Is(err, domain.ErrGeocodingBusy) {
		c.Set("Retry-After", "1")
		return c.Status(429).JSON(fiber.Map{"error": "กรุณารอสักครู่แล้วค้นหาอีกครั้ง"})
	}
	return c.Status(502).JSON(fiber.Map{"error": "ไม่สามารถค้นหาสถานที่ได้ กรุณาลองใหม่"})
}

func (h *LocationHandler) Search(c fiber.Ctx) error {
	query := strings.TrimSpace(c.Query("q"))
	if utf8.RuneCountInString(query) < 2 || utf8.RuneCountInString(query) > 200 {
		return c.Status(400).JSON(fiber.Map{"error": "กรุณาระบุคำค้นหา 2–200 ตัวอักษร"})
	}
	ctx, cancel := context.WithTimeout(c.Context(), 14*time.Second)
	defer cancel()
	places, err := h.geocoder.Search(ctx, query)
	if h.suggester != nil {
		extra, suggestErr := h.suggester.Suggest(ctx, query)
		if suggestErr == nil {
			if err != nil {
				places = []domain.Place{}
			}
			for _, p := range extra {
				duplicate := false
				for _, existing := range places {
					if strings.EqualFold(existing.Name, p.Name) && math.Abs(existing.Latitude-p.Latitude) < 0.0001 && math.Abs(existing.Longitude-p.Longitude) < 0.0001 {
						duplicate = true
						break
					}
				}
				if !duplicate {
					places = append(places, p)
				}
			}
			err = nil
		}
	}
	if err != nil {
		return locationError(c, err)
	}
	return c.JSON(places)
}

func (h *LocationHandler) Reverse(c fiber.Ctx) error {
	lat, latErr := strconv.ParseFloat(c.Query("lat"), 64)
	lon, lonErr := strconv.ParseFloat(c.Query("lon"), 64)
	if latErr != nil || lonErr != nil || math.IsNaN(lat) || math.IsNaN(lon) || math.IsInf(lat, 0) || math.IsInf(lon, 0) || math.Abs(lat) > 90 || math.Abs(lon) > 180 {
		return c.Status(400).JSON(fiber.Map{"error": "พิกัดไม่ถูกต้อง"})
	}
	place, err := h.geocoder.Reverse(c.Context(), lat, lon)
	if err != nil {
		return locationError(c, err)
	}
	return c.JSON(place)
}

func NewLocationSuggestionHandler(suggester domain.PlaceSuggester) fiber.Handler {
	return func(c fiber.Ctx) error {
		query := strings.TrimSpace(c.Query("q"))
		if utf8.RuneCountInString(query) < 2 || utf8.RuneCountInString(query) > 200 {
			return c.Status(400).JSON(fiber.Map{"error": "กรุณาระบุคำค้นหา 2–200 ตัวอักษร"})
		}
		places, err := suggester.Suggest(c.Context(), query)
		if err != nil {
			return locationError(c, err)
		}
		return c.JSON(places)
	}
}
