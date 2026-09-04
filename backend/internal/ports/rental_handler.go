package ports

import (
	"errors"
	"log"
	"net/http"
	"strings"

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

// CreateRentalOrder creates a pending rental request. The server/database owns
// price calculation and availability validation.
func (h *RentalHandler) CreateRentalOrder(c *gin.Context) {
	userID, ok := h.authenticatedUserID(c)
	if !ok {
		return
	}

	var request domain.CreateRentalRequest
	if err := c.ShouldBindJSON(&request); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลคำขอเช่าไม่ถูกต้อง"})
		return
	}
	request.PickupLocation = strings.TrimSpace(request.PickupLocation)
	if !request.EndAt.After(request.StartAt) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "เวลาสิ้นสุดต้องอยู่หลังเวลาเริ่มต้น"})
		return
	}

	rental, err := h.rentalRepository.CreateRental(c.Request.Context(), userID, request)
	if err != nil {
		writeRentalError(c, err)
		return
	}
	c.JSON(http.StatusCreated, rental)
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
