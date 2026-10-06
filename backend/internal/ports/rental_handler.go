package ports

import (
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gin-gonic/gin"
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
	ItemID         int64     `json:"item_id" binding:"required,gt=0"`
	StartAt        time.Time `json:"start_at" binding:"required"`
	EndAt          time.Time `json:"end_at" binding:"required"`
	RentalType     string    `json:"rental_type" binding:"required,oneof=daily hourly"`
	PickupLocation string    `json:"pickup_location" binding:"required,min=1,max=500"`
}

// CreateRentalOrder สร้างคำขอจองอุปกรณ์ใหม่ โดยระบบจะตรวจสอบความพร้อมและคำนวณราคา
func (h *RentalHandler) CreateRentalOrder(c *gin.Context) {
	userID, ok := authenticatedUserID(c, h.tokenVerifier)
	if !ok {
		return
	}

	var req createRentalRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลคำขอเช่าไม่ถูกต้อง"})
		return
	}
	req.PickupLocation = strings.TrimSpace(req.PickupLocation)
	if !req.EndAt.After(req.StartAt) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "เวลาสิ้นสุดต้องอยู่หลังเวลาเริ่มต้น"})
		return
	}

	rental, err := h.rentalRepository.CreateRental(c.Request.Context(), userID, domain.CreateRentalRequest{
		ItemID:         req.ItemID,
		StartAt:        req.StartAt,
		EndAt:          req.EndAt,
		RentalType:     req.RentalType,
		PickupLocation: req.PickupLocation,
	})
	if err != nil {
		writeRentalError(c, err)
		return
	}
	c.JSON(http.StatusCreated, rental)
}

func parseRentalID(c *gin.Context) (int64, bool) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "รหัสการเช่าต้องเป็นจำนวนเต็มที่มากกว่า 0"})
		return 0, false
	}
	return id, true
}

// [POST] /api/rentals/:id/handover - ยืนยันการส่งมอบอุปกรณ์ (เปลี่ยนสถานะเป็น active)
func (h *RentalHandler) HandoverRental(c *gin.Context) {
	userID, ok := authenticatedUserID(c, h.tokenVerifier)
	if !ok {
		return
	}
	id, ok := parseRentalID(c)
	if !ok {
		return
	}

	order, err := h.rentalRepository.UpdateRentalStatus(c.Request.Context(), userID, id, "active")
	if err != nil {
		writeRentalStatusError(c, err)
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":  http.StatusOK,
		"message": "ยืนยันการส่งมอบอุปกรณ์เรียบร้อยแล้ว",
		"rental":  order,
	})
}

// [POST] /api/rentals/:id/return - ยืนยันการรับคืนอุปกรณ์ (เปลี่ยนสถานะเป็น completed)
func (h *RentalHandler) ReturnRental(c *gin.Context) {
	userID, ok := authenticatedUserID(c, h.tokenVerifier)
	if !ok {
		return
	}
	id, ok := parseRentalID(c)
	if !ok {
		return
	}

	order, err := h.rentalRepository.UpdateRentalStatus(c.Request.Context(), userID, id, "completed")
	if err != nil {
		writeRentalStatusError(c, err)
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":  http.StatusOK,
		"message": "ยืนยันการรับคืนอุปกรณ์เรียบร้อยแล้ว",
		"rental":  order,
	})
}

func writeRentalStatusError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, domain.ErrRentalNotFound):
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบรายการเช่านี้"})
	case errors.Is(err, domain.ErrRentalForbidden):
		c.JSON(http.StatusForbidden, gin.H{"error": "คุณไม่มีสิทธิ์จัดการรายการเช่านี้"})
	case errors.Is(err, domain.ErrRentalStatusTransition):
		c.JSON(http.StatusConflict, gin.H{"error": "ไม่สามารถเปลี่ยนสถานะการเช่านี้ได้เนื่องจากสถานะปัจจุบันไม่ถูกต้อง"})
	default:
		log.Printf("update rental status failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ระบบอัปเดตสถานะการเช่าขัดข้อง"})
	}
}

func writeRentalError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, domain.ErrRentalNotFound), errors.Is(err, domain.ErrItemNotFound):
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบรายการเช่าหรืออุปกรณ์"})
	case errors.Is(err, domain.ErrRentalUnavailable):
		c.JSON(http.StatusConflict, gin.H{"error": "อุปกรณ์หรือช่วงเวลานี้ไม่พร้อมให้เช่า"})
	case errors.Is(err, domain.ErrInvalidRental):
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลคำขอเช่าไม่ถูกต้อง"})
	default:
		log.Printf("rental request operation failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถส่งคำขอเช่าได้"})
	}
}
