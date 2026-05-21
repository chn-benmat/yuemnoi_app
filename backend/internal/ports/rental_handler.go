package ports

import (
	"github.com/gin-gonic/gin"
	"net/http"
)

type RentalHandler struct{}

func NewRentalHandler() *RentalHandler {
	return &RentalHandler{}
}

// [POST] /api/v1/rentals - ลูกค้ากดปุ่ม "จอง/เช่าอุปกรณ์" จาก Flutter
func (h *RentalHandler) CreateRentalOrder(c *gin.Context) {
	c.JSON(http.StatusCreated, gin.H{"message": "สร้างใบจองเช่าอุปกรณ์สำเร็จ (POST)"})
}

// [PUT] /api/v1/rentals/:id/status - อัปเดตสเตตัสการเช่า (เช่น ส่งของแล้ว, ได้รับคืนแล้ว)
func (h *RentalHandler) UpdateRentalStatus(c *gin.Context) {
	id := c.Param("id")
	c.JSON(http.StatusOK, gin.H{"message": "อัปเดตสถานะใบจองไอดี " + id + " สำเร็จ (PUT)"})
}
