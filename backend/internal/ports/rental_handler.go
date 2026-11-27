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
	ConversationID string    `json:"conversation_id" validate:"omitempty,uuid"`
	PaymentMethod  string    `json:"payment_method" validate:"omitempty,oneof=cash promptpay"`
	UnitPrice      int64     `json:"unit_price" validate:"omitempty,gt=0,lte=2147483647"`
	QueueMessageID int64     `json:"queue_message_id" validate:"omitempty,gt=0"`
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
	req.OfferMessageID = strings.TrimSpace(req.OfferMessageID)
	if (req.ConversationID != "" && (req.OfferMessageID != "" || req.BookingID > 0 || req.PaymentMethod == "" || req.UnitPrice == 0)) ||
		(req.ConversationID == "" && (req.PaymentMethod != "" || req.UnitPrice != 0 || req.QueueMessageID > 0)) {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "ข้อมูลคำขอเช่าไม่ถูกต้อง"})
	}
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
		OfferMessageID: req.OfferMessageID,
		BookingID:      req.BookingID,
		ConversationID: req.ConversationID,
		PaymentMethod:  req.PaymentMethod,
		UnitPrice:      req.UnitPrice,
		QueueMessageID: req.QueueMessageID,
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
	PaymentMethod  string `json:"payment_method"`
}

// ConfirmRentalOrder ยืนยันคำขอเช่าจากแชทตามสิทธิ์ของคู่เช่า
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
	if req.PaymentMethod != "" && req.PaymentMethod != "cash" && req.PaymentMethod != "promptpay" {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "กรุณาเลือกชำระด้วยเงินสดหรือ PromptPay"})
	}
	rental, err := h.rentalRepository.ConfirmRental(c.Context(), userID, id, strings.TrimSpace(req.OfferMessageID), req.PaymentMethod)
	if err != nil {
		return writeRentalError(c, err)
	}
	return c.Status(http.StatusOK).JSON(rental)
}

func (h *RentalHandler) GetHandoverPayment(c fiber.Ctx) error {
	return h.handoverPayment(c, false)
}

func (h *RentalHandler) ConfirmHandoverPayment(c fiber.Ctx) error {
	return h.handoverPayment(c, true)
}

func (h *RentalHandler) SavePromptPayAccount(c fiber.Ctx) error {
	return h.handoverPayment(c, false)
}

func (h *RentalHandler) handoverPayment(c fiber.Ctx, confirm bool) error {
	userID, ok := authenticatedUserID(c, h.tokenVerifier)
	if !ok {
		return nil
	}
	id, ok := parseRentalID(c)
	if !ok {
		return nil
	}
	repo, ok := h.rentalRepository.(domain.RentalHandoverRepository)
	if !ok {
		return c.Status(http.StatusInternalServerError).JSON(fiber.Map{"error": "ระบบตรวจสอบการชำระเงินยังไม่พร้อมใช้งาน"})
	}
	var payment domain.RentalHandoverPayment
	var err error
	if c.Method() == http.MethodPut {
		req, message := bindPromptPayAccount(c)
		if message != "" {
			return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": message})
		}
		payment, err = repo.SavePromptPayAccount(c.Context(), userID, id, req.Phone, req.NationalID)
	} else {
		payment, err = repo.HandoverPayment(c.Context(), userID, id, confirm)
	}
	if err != nil {
		return writeRentalStatusError(c, err)
	}
	if payment.CanCollectPayment {
		payment.PromptPayQR = domain.PromptPayQR(payment.PromptPayPhone, payment.PromptPayNationalID, payment.TotalSatang)
		if payment.PromptPayQR != "" {
			payment.PromptPayIDType = "phone"
			if payment.PromptPayNationalID != "" {
				payment.PromptPayIDType = "national_id"
			}
		}
	} else {
		payment.PromptPayPhone = ""
	}
	c.Set("Cache-Control", "private, no-store")
	return c.JSON(payment)
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

	var req struct {
		Token string `json:"token_or_otp"`
	}
	if err := c.Bind().JSON(&req); err != nil || strings.TrimSpace(req.Token) == "" || len(req.Token) > 200 {
		return c.Status(400).JSON(fiber.Map{"error": "กรุณาสแกน QR หรือกรอกรหัสยืนยันจากเจ้าของอุปกรณ์"})
	}
	order, err := h.rentalRepository.CompleteRentalReturn(c.Context(), userID, id, strings.TrimSpace(req.Token))
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
	case errors.Is(err, domain.ErrInvalidRental):
		return c.Status(400).JSON(fiber.Map{"error": "ข้อมูลหรือหลักฐานการเช่าไม่ครบถ้วน"})
	case errors.Is(err, domain.ErrRentalReturnToken):
		return c.Status(400).JSON(fiber.Map{"error": "รหัสยืนยันไม่ถูกต้องหรือหมดอายุ กรุณาขอรหัสใหม่จากเจ้าของอุปกรณ์", "code": "invalid_return_token"})
	case errors.Is(err, domain.ErrRentalNotStarted):
		return c.Status(http.StatusConflict).JSON(fiber.Map{"error": "ยังไม่ถึงเวลาเริ่มเช่าตามที่นัดไว้"})
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
	var verification *domain.RentalVerificationRequired
	switch {
	case errors.As(err, &verification):
		return writeRentalVerificationRequired(c, verification.Verification)
	case errors.Is(err, domain.ErrRentalForbidden):
		return c.Status(http.StatusForbidden).JSON(fiber.Map{"error": "คุณไม่มีสิทธิ์จัดการคำขอเช่านี้"})
	case errors.Is(err, domain.ErrRentalNotFound), errors.Is(err, domain.ErrItemNotFound):
		return c.Status(http.StatusNotFound).JSON(fiber.Map{"error": "ไม่พบรายการเช่าหรืออุปกรณ์"})
	case errors.Is(err, domain.ErrItemRentalOccupied):
		return c.Status(http.StatusConflict).JSON(fiber.Map{
			"code": "item_rental_occupied", "error": "อุปกรณ์นี้อยู่ระหว่างเช่าหรือมีคิวเช่าต่อ กรุณาตรวจสอบสิทธิ์อีกครั้ง",
		})
	case errors.Is(err, domain.ErrRentalUnavailable):
		return c.Status(http.StatusConflict).JSON(fiber.Map{"error": "อุปกรณ์หรือช่วงเวลานี้ไม่พร้อมให้เช่า"})
	case errors.Is(err, domain.ErrRentalRequestExpired):
		return c.Status(http.StatusConflict).JSON(fiber.Map{"error": "เวลานัดรับผ่านไปแล้ว กรุณาส่งคำขอพร้อมวันและเวลาใหม่"})
	case errors.Is(err, domain.ErrRentalPriceChanged):
		return c.Status(http.StatusConflict).JSON(fiber.Map{"error": "ราคาเช่ามีการเปลี่ยนแปลง กรุณากลับไปเปิดคำขอใหม่เพื่อตรวจสอบราคา"})
	case errors.Is(err, domain.ErrRentalStatusTransition):
		return c.Status(http.StatusConflict).JSON(fiber.Map{"error": "ไม่สามารถยืนยันรายการในสถานะปัจจุบันได้"})
	case errors.Is(err, domain.ErrInvalidRental):
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "ข้อมูลคำขอเช่าไม่ถูกต้อง"})
	default:
		log.Printf("rental request operation failed: %v", err)
		return c.Status(http.StatusInternalServerError).JSON(fiber.Map{"error": "ไม่สามารถส่งคำขอเช่าได้"})
	}
}
