package ports

import (
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
)

type RentalHandler struct{}

func NewRentalHandler() *RentalHandler {
	return &RentalHandler{}
}

// [POST] /api/v1/rentals - ลูกค้ากดปุ่ม "จอง/เช่าอุปกรณ์" จาก Flutter
func (h *RentalHandler) CreateRentalOrder(c *gin.Context) {
	// ดึง userID ที่ได้มาจาก AuthMiddleware
	userID, exists := c.Get("userID")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	log.Printf("User %s is creating a rental order", userID)

	c.JSON(http.StatusCreated, gin.H{"message": "สร้างใบจองเช่าอุปกรณ์สำเร็จ (POST)"})
}
