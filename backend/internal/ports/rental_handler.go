package ports

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"io"
	"log"
	"net/http"
	"strconv"
	"strings"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gin-gonic/gin"
)

const maxStripeWebhookBody = 1 << 20

type RentalHandler struct {
	paymentRepository domain.PaymentRepository
	paymentGateway    domain.PaymentGateway
	itemRepository    domain.ItemRepository
	tokenVerifier     domain.TokenVerifier
}

func NewRentalHandler(
	paymentRepository domain.PaymentRepository,
	paymentGateway domain.PaymentGateway,
	itemRepository domain.ItemRepository,
	tokenVerifier domain.TokenVerifier,
) *RentalHandler {
	return &RentalHandler{
		paymentRepository: paymentRepository,
		paymentGateway:    paymentGateway,
		itemRepository:    itemRepository,
		tokenVerifier:     tokenVerifier,
	}
}

func (h *RentalHandler) authenticatedUserID(c *gin.Context) (string, bool) {
	token, ok := extractToken(c)
	if !ok {
		return "", false
	}
	userID, err := h.tokenVerifier.UserIDFromToken(c.Request.Context(), token)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Access Token ไม่ถูกต้องหรือหมดอายุ"})
		return "", false
	}
	return userID, true
}

func parseRentalID(c *gin.Context) (int64, bool) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "รหัสการจองต้องเป็นจำนวนเต็มที่มากกว่า 0"})
		return 0, false
	}
	return id, true
}

// CreateRentalOrder สร้างรายการจองโดยให้ฐานข้อมูลอ่านและคำนวณจากราคาปัจจุบัน
func (h *RentalHandler) CreateRentalOrder(c *gin.Context) {
	userID, ok := h.authenticatedUserID(c)
	if !ok {
		return
	}

	var request domain.CreateRentalRequest
	if err := c.ShouldBindJSON(&request); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลการจองไม่ถูกต้อง"})
		return
	}
	request.PickupLocation = strings.TrimSpace(request.PickupLocation)
	if !request.EndAt.After(request.StartAt) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "เวลาสิ้นสุดต้องอยู่หลังเวลาเริ่มต้น"})
		return
	}

	rental, err := h.paymentRepository.CreateRental(c.Request.Context(), userID, request)
	if err != nil {
		writeRentalError(c, err)
		return
	}
	c.JSON(http.StatusCreated, rental)
}

// CreateCheckoutSession คืน URL ของ Stripe โดยสถานะสำเร็จต้องยืนยันผ่าน webhook เท่านั้น
func (h *RentalHandler) CreateCheckoutSession(c *gin.Context) {
	userID, ok := h.authenticatedUserID(c)
	if !ok {
		return
	}
	rentalID, ok := parseRentalID(c)
	if !ok {
		return
	}

	rental, err := h.paymentRepository.FindRentalForUser(c.Request.Context(), rentalID, userID)
	if err != nil {
		writeRentalError(c, err)
		return
	}
	if rental.PaymentStatus == domain.PaymentStatusPaid {
		c.JSON(http.StatusConflict, gin.H{"error": "รายการนี้ชำระเงินแล้ว"})
		return
	}

	item, err := h.itemRepository.FindByID(c.Request.Context(), rental.ItemID)
	if err != nil {
		writeRentalError(c, err)
		return
	}
	idempotencyKey, err := newPaymentIdempotencyKey()
	if err != nil {
		log.Printf("generate payment idempotency key failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถเริ่มการชำระเงินได้"})
		return
	}
	payment, err := h.paymentRepository.CreateOrGetPayment(c.Request.Context(), rental, idempotencyKey)
	if err != nil {
		writeRentalError(c, err)
		return
	}

	session, err := h.paymentGateway.CreateCheckoutSession(c.Request.Context(), domain.CheckoutRequest{
		PaymentOrderID: payment.ID,
		BookingID:      rental.ID,
		ItemName:       item.ItemName,
		AmountSatang:   payment.AmountSatang,
		Currency:       payment.Currency,
		IdempotencyKey: payment.IdempotencyKey,
	})
	if err != nil {
		writeRentalError(c, err)
		return
	}
	if err := h.paymentRepository.AttachCheckoutSession(
		c.Request.Context(), payment.ID, session.ID, session.Livemode,
	); err != nil {
		writeRentalError(c, err)
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"rental_id":        rental.ID,
		"payment_order_id": payment.ID,
		"checkout_url":     session.URL,
		"status":           domain.PaymentStatusCheckoutPending,
	})
}

func (h *RentalHandler) GetPaymentStatus(c *gin.Context) {
	userID, ok := h.authenticatedUserID(c)
	if !ok {
		return
	}
	rentalID, ok := parseRentalID(c)
	if !ok {
		return
	}
	payment, err := h.paymentRepository.FindPaymentForRental(c.Request.Context(), rentalID, userID)
	if err != nil {
		writeRentalError(c, err)
		return
	}

	// If payment is not marked as paid in DB, but has a Stripe Checkout Session ID,
	// query Stripe directly to see if payment was completed.
	if payment.Status != domain.PaymentStatusPaid && payment.StripeCheckoutSessionID != "" && h.paymentGateway != nil {
		event, err := h.paymentGateway.RetrieveCheckoutSession(c.Request.Context(), payment.StripeCheckoutSessionID)
		if err == nil && event != nil && event.NextStatus == domain.PaymentStatusPaid {
			if event.PaymentOrderID == "" {
				event.PaymentOrderID = payment.ID
			}
			_, _ = h.paymentRepository.ProcessEvent(c.Request.Context(), *event)
			if updatedPayment, err := h.paymentRepository.FindPaymentForRental(c.Request.Context(), rentalID, userID); err == nil {
				payment = updatedPayment
			}
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"rental_id":        rentalID,
		"payment_order_id": payment.ID,
		"status":           payment.Status,
		"amount_satang":    payment.AmountSatang,
		"currency":         payment.Currency,
		"paid_at":          payment.PaidAt,
	})
}

func (h *RentalHandler) HandleStripeWebhook(c *gin.Context) {
	body, err := io.ReadAll(http.MaxBytesReader(c.Writer, c.Request.Body, maxStripeWebhookBody))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "webhook payload ไม่ถูกต้อง"})
		return
	}
	event, err := h.paymentGateway.ParseWebhook(body, c.GetHeader("Stripe-Signature"))
	if err != nil {
		if errors.Is(err, domain.ErrPaymentConfiguration) {
			log.Printf("Stripe webhook is not configured")
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "ระบบชำระเงินยังไม่พร้อมใช้งาน"})
			return
		}
		c.JSON(http.StatusBadRequest, gin.H{"error": "ลายเซ็น webhook ไม่ถูกต้อง"})
		return
	}
	if event == nil {
		c.Status(http.StatusOK)
		return
	}
	if event.ID == "" || event.PaymentOrderID == "" || event.AmountSatang <= 0 || event.Currency == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูล webhook ไม่ครบถ้วน"})
		return
	}

	processed, err := h.paymentRepository.ProcessEvent(c.Request.Context(), *event)
	if err != nil {
		log.Printf("process Stripe event %s failed: %v", event.ID, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ประมวลผล webhook ไม่สำเร็จ"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"processed": processed})
}

// PaymentReturnPage เชื่อม redirect แบบ HTTPS ของ Stripe กลับเข้าแอปมือถือ
// หน้านี้ไม่เปลี่ยนสถานะเป็นสำเร็จ เพราะแอปต้องอ่านสถานะที่ยืนยันผ่าน webhook
func (h *RentalHandler) PaymentReturnPage(c *gin.Context) {
	rentalID, err := strconv.ParseInt(c.Query("rental_id"), 10, 64)
	if err != nil || rentalID <= 0 {
		c.String(http.StatusBadRequest, "Invalid rental id")
		return
	}
	result := "success"
	title := "กลับไปตรวจสอบสถานะในแอป Yuemnoi"
	if c.Query("result") == "cancel" {
		result = "cancel"
		title = "การชำระเงินถูกยกเลิก"
	}
	deepLink := "yuemnoi://payments/return?rental_id=" + strconv.FormatInt(rentalID, 10) + "&result=" + result
	c.Header("Content-Type", "text/html; charset=utf-8")
	c.String(http.StatusOK, `<!doctype html>
<html lang="th"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Yuemnoi Payment</title><style>body{font-family:system-ui,sans-serif;display:grid;place-items:center;min-height:100vh;margin:0;background:#f7f8fa;color:#1e2022}.card{text-align:center;background:#fff;padding:32px;border-radius:24px;box-shadow:0 8px 30px #0001;max-width:360px}a{display:inline-block;margin-top:18px;padding:14px 24px;border-radius:24px;background:#9251d0;color:#fff;text-decoration:none}</style></head>
<body><main class="card"><h1>%s</h1><p>สถานะสุดท้ายจะยืนยันจาก Stripe ผ่านเซิร์ฟเวอร์</p><a href="%s">เปิดแอป Yuemnoi</a></main></body></html>`, title, deepLink)
}

func newPaymentIdempotencyKey() (string, error) {
	random := make([]byte, 16)
	if _, err := rand.Read(random); err != nil {
		return "", err
	}
	return "yuemnoi-checkout-" + hex.EncodeToString(random), nil
}

func writeRentalError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, domain.ErrRentalNotFound), errors.Is(err, domain.ErrPaymentNotFound), errors.Is(err, domain.ErrItemNotFound):
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบรายการเช่าหรือรายการชำระเงิน"})
	case errors.Is(err, domain.ErrRentalUnavailable):
		c.JSON(http.StatusConflict, gin.H{"error": "อุปกรณ์หรือช่วงเวลานี้ไม่พร้อมให้เช่า"})
	case errors.Is(err, domain.ErrInvalidRental):
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลการเช่าไม่ถูกต้อง"})
	case errors.Is(err, domain.ErrPaymentConfiguration):
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "ระบบชำระเงินยังไม่พร้อมใช้งาน"})
	default:
		log.Printf("rental payment operation failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ระบบชำระเงินขัดข้อง"})
	}
}
