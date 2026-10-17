package ports

import (
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
)

type RentalHandler struct {
	rentalRepository domain.RentalRepository
	tokenVerifier    domain.TokenVerifier
}

func NewRentalHandler(
	rentalRepository domain.RentalRepository,
	tokenVerifier domain.TokenVerifier,
) *RentalHandler {
	return &RentalHandler{
		rentalRepository: rentalRepository,
		tokenVerifier:    tokenVerifier,
	}
}

type createRentalRequest struct {
	ItemID         int64     `json:"item_id" validate:"required,gt=0"`
	StartAt        time.Time `json:"start_at" validate:"required"`
	EndAt          time.Time `json:"end_at" validate:"required"`
	RentalType     string    `json:"rental_type" validate:"required,oneof=daily hourly"`
	PickupLocation string    `json:"pickup_location" validate:"required,min=1,max=500"`
	OfferMessageID string    `json:"offer_message_id" validate:"omitempty,max=100"`
	BookingID      int64     `json:"booking_id" validate:"omitempty,gt=0"`
}

// CreateRentalOrder สร้างคำขอจองอุปกรณ์ใหม่ โดยระบบจะตรวจสอบความพร้อมและคำนวณราคา
func (h *RentalHandler) CreateRentalOrder(c fiber.Ctx) error {
	userID, ok := authenticatedUserID(c, h.tokenVerifier)
	if !ok {
		return nil
	}

	var req createRentalRequest
	if err := c.Bind().JSON(&req); err != nil {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "ข้อมูลคำขอเช่าไม่ถูกต้อง"})
	}
	req.PickupLocation = strings.TrimSpace(req.PickupLocation)
	if req.BookingID > 0 && strings.TrimSpace(req.OfferMessageID) == "" {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "กรุณาระบุข้อความข้อเสนอที่ต้องการยืนยัน"})
	}
	if req.PickupLocation == "" {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "กรุณาระบุสถานที่รับอุปกรณ์"})
	}
	if !req.EndAt.After(req.StartAt) {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "เวลาสิ้นสุดต้องอยู่หลังเวลาเริ่มต้น"})
	}

	rental, err := h.rentalRepository.CreateRental(c.Context(), userID, domain.CreateRentalRequest{
		ItemID:         req.ItemID,
		StartAt:        req.StartAt,
		EndAt:          req.EndAt,
		RentalType:     req.RentalType,
		PickupLocation: req.PickupLocation,
		OfferMessageID: strings.TrimSpace(req.OfferMessageID),
		BookingID:      req.BookingID,
	})
	if err != nil {
		return writeRentalError(c, err)
	}
	return c.Status(http.StatusCreated).JSON(rental)
}

func parseRentalID(c fiber.Ctx) (int64, bool) {
	id, err := strconv.ParseInt(c.Params("id"), 10, 64)
	if err != nil || id <= 0 {
		_ = c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "รหัสการเช่าต้องเป็นจำนวนเต็มที่มากกว่า 0"})
		return 0, false
	}
	return id, true
}

type confirmRentalRequest struct {
	OfferMessageID string `json:"offer_message_id" validate:"required,max=100"`
}

// ConfirmRentalOrder เปลี่ยนจาก pending หลังผู้เช่ากดปุ่มยืนยันขั้นสุดท้ายเท่านั้น
func (h *RentalHandler) ConfirmRentalOrder(c fiber.Ctx) error {
	userID, ok := authenticatedUserID(c, h.tokenVerifier)
	if !ok {
		return nil
	}
	id, ok := parseRentalID(c)
	if !ok {
		return nil
	}
	var req confirmRentalRequest
	if err := c.Bind().JSON(&req); err != nil || strings.TrimSpace(req.OfferMessageID) == "" {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "กรุณาระบุข้อความข้อเสนอที่ต้องการยืนยัน"})
	}
	rental, err := h.rentalRepository.ConfirmRental(c.Context(), userID, id, strings.TrimSpace(req.OfferMessageID))
	if err != nil {
		return writeRentalError(c, err)
	}
	return c.Status(http.StatusOK).JSON(rental)
}

// [POST] /api/rentals/:id/handover - ยืนยันการส่งมอบอุปกรณ์ (เปลี่ยนสถานะเป็น active)
func (h *RentalHandler) HandoverRental(c fiber.Ctx) error {
	userID, ok := authenticatedUserID(c, h.tokenVerifier)
	if !ok {
		return nil
	}
	id, ok := parseRentalID(c)
	if !ok {
		return nil
	}

	order, err := h.rentalRepository.UpdateRentalStatus(c.Context(), userID, id, "active")
	if err != nil {
		return writeRentalStatusError(c, err)
	}

	return c.Status(http.StatusOK).JSON(fiber.Map{
		"status":  http.StatusOK,
		"message": "ยืนยันการส่งมอบอุปกรณ์เรียบร้อยแล้ว",
		"rental":  order,
	})
}

// [POST] /api/rentals/:id/return - ยืนยันการรับคืนอุปกรณ์ (เปลี่ยนสถานะเป็น completed)
func (h *RentalHandler) ReturnRental(c fiber.Ctx) error {
	userID, ok := authenticatedUserID(c, h.tokenVerifier)
	if !ok {
		return nil
	}
	id, ok := parseRentalID(c)
	if !ok {
		return nil
	}

	order, err := h.rentalRepository.UpdateRentalStatus(c.Context(), userID, id, "completed")
	if err != nil {
		return writeRentalStatusError(c, err)
	}

	return c.Status(http.StatusOK).JSON(fiber.Map{
		"status":  http.StatusOK,
		"message": "ยืนยันการรับคืนอุปกรณ์เรียบร้อยแล้ว",
		"rental":  order,
	})
}

func writeRentalStatusError(c fiber.Ctx, err error) error {
	switch {
	case errors.Is(err, domain.ErrRentalNotFound):
		return c.Status(http.StatusNotFound).JSON(fiber.Map{"error": "ไม่พบรายการเช่านี้"})
	case errors.Is(err, domain.ErrRentalForbidden):
		return c.Status(http.StatusForbidden).JSON(fiber.Map{"error": "คุณไม่มีสิทธิ์จัดการรายการเช่านี้"})
	case errors.Is(err, domain.ErrRentalStatusTransition):
		return c.Status(http.StatusConflict).JSON(fiber.Map{"error": "ไม่สามารถเปลี่ยนสถานะการเช่านี้ได้เนื่องจากสถานะปัจจุบันไม่ถูกต้อง"})
	default:
		log.Printf("update rental status failed: %v", err)
		return c.Status(http.StatusInternalServerError).JSON(fiber.Map{"error": "ระบบอัปเดตสถานะการเช่าขัดข้อง"})
	}
}

func writeRentalError(c fiber.Ctx, err error) error {
	switch {
	case errors.Is(err, domain.ErrRentalForbidden):
		return c.Status(http.StatusForbidden).JSON(fiber.Map{"error": "ยืนยันได้เฉพาะข้อเสนอที่เจ้าของอุปกรณ์ส่งให้คุณเท่านั้น"})
	case errors.Is(err, domain.ErrRentalNotFound), errors.Is(err, domain.ErrItemNotFound):
		return c.Status(http.StatusNotFound).JSON(fiber.Map{"error": "ไม่พบรายการเช่าหรืออุปกรณ์"})
	case errors.Is(err, domain.ErrRentalUnavailable):
		return c.Status(http.StatusConflict).JSON(fiber.Map{"error": "อุปกรณ์หรือช่วงเวลานี้ไม่พร้อมให้เช่า"})
	case errors.Is(err, domain.ErrRentalStatusTransition):
		return c.Status(http.StatusConflict).JSON(fiber.Map{"error": "ไม่สามารถยืนยันรายการในสถานะปัจจุบันได้"})
	case errors.Is(err, domain.ErrInvalidRental):
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "ข้อมูลคำขอเช่าไม่ถูกต้อง"})
	default:
		log.Printf("rental request operation failed: %v", err)
		return c.Status(http.StatusInternalServerError).JSON(fiber.Map{"error": "ไม่สามารถส่งคำขอเช่าได้"})
	}
}
