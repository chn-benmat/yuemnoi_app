package ports

import (
	"errors"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/Chanachai04/yuemnoi_app/backend/internal/domain"
	"github.com/gin-gonic/gin"
)

type ItemHandler struct {
	repo          domain.ItemRepository
	tokenVerifier domain.TokenVerifier
}

type CreateItemRequest struct {
	ItemName     string   `json:"item_name" binding:"required,min=1,max=150"`
	ItemImageURL []string `json:"item_image_url" binding:"omitempty,dive,max=2048"`
	Description  string   `json:"description" binding:"required,min=1,max=2000"`
	Category     string   `json:"category" binding:"omitempty,max=100"`
	Price        int      `json:"price" binding:"required,gt=0"`
	Status       string   `json:"status" binding:"omitempty,max=50"`
	Type         string   `json:"type" binding:"omitempty,max=100"`
}

type UpdateItemRequest struct {
	ItemName     *string   `json:"item_name" binding:"omitempty,min=1,max=150"`
	ItemImageURL *[]string `json:"item_image_url" binding:"omitempty,dive,max=2048"`
	Description  *string   `json:"description" binding:"omitempty,min=1,max=2000"`
	Category     *string   `json:"category" binding:"omitempty,max=100"`
	Price        *int      `json:"price" binding:"omitempty,gt=0"`
	Status       *string   `json:"status" binding:"omitempty,max=50"`
	Type         *string   `json:"type" binding:"omitempty,max=100"`
}

func NewItemHandler(r domain.ItemRepository, tokenVerifier domain.TokenVerifier) *ItemHandler {
	return &ItemHandler{
		repo:          r,
		tokenVerifier: tokenVerifier,
	}
}

func (h *ItemHandler) authenticatedUserID(c *gin.Context) (string, bool) {
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

func parseItemID(c *gin.Context) (int64, bool) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "รหัสอุปกรณ์ต้องเป็นจำนวนเต็มที่มากกว่า 0"})
		return 0, false
	}

	return id, true
}

func writeItemError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, domain.ErrItemNotFound):
		c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบอุปกรณ์ หรือคุณไม่ใช่เจ้าของอุปกรณ์นี้"})
	case errors.Is(err, domain.ErrItemInUse):
		c.JSON(http.StatusConflict, gin.H{"error": "ไม่สามารถลบอุปกรณ์ที่มีการจองหรือรีวิวอ้างอิงอยู่"})
	default:
		log.Printf("item operation failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ระบบจัดการอุปกรณ์ขัดข้อง"})
	}
}

// [GET] /api/v1/items - ดึงข้อมูลอุปกรณ์เช่าทั้งหมด
func (h *ItemHandler) GetAllItems(c *gin.Context) {
	items, err := h.repo.FindAll(c.Request.Context())
	if err != nil {
		writeItemError(c, err)
		return
	}

	c.JSON(http.StatusOK, items)
}

// [GET] /api/v1/items/:id - ดึงข้อมูลอุปกรณ์เช่าตาม ID
func (h *ItemHandler) GetItemByID(c *gin.Context) {
	id, ok := parseItemID(c)
	if !ok {
		return
	}

	item, err := h.repo.FindByID(c.Request.Context(), id)
	if err != nil {
		writeItemError(c, err)
		return
	}

	c.JSON(http.StatusOK, item)
}

// [POST] /api/v1/items - เพิ่มอุปกรณ์ของผู้ใช้ที่เข้าสู่ระบบ
func (h *ItemHandler) CreateItem(c *gin.Context) {
	userID, ok := h.authenticatedUserID(c)
	if !ok {
		return
	}

	var req CreateItemRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลอุปกรณ์ไม่ถูกต้อง: " + err.Error()})
		return
	}

	item, err := h.repo.Insert(c.Request.Context(), &domain.Item{
		UserID:       userID,
		ItemName:     req.ItemName,
		ItemImageURL: req.ItemImageURL,
		Description:  req.Description,
		Category:     req.Category,
		Price:        req.Price,
		Status:       req.Status,
		Type:         req.Type,
	})
	if err != nil {
		writeItemError(c, err)
		return
	}

	c.JSON(http.StatusCreated, item)
}

// [PUT] /api/v1/items/:id - แก้ไขอุปกรณ์ของผู้ใช้ที่เข้าสู่ระบบ
func (h *ItemHandler) UpdateItem(c *gin.Context) {
	userID, ok := h.authenticatedUserID(c)
	if !ok {
		return
	}
	id, ok := parseItemID(c)
	if !ok {
		return
	}

	var req UpdateItemRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลอุปกรณ์ไม่ถูกต้อง: " + err.Error()})
		return
	}

	fields := make(map[string]interface{})
	if req.ItemName != nil {
		fields["item_name"] = *req.ItemName
	}
	if req.ItemImageURL != nil {
		fields["item_image_url"] = *req.ItemImageURL
	}
	if req.Description != nil {
		fields["description"] = *req.Description
	}
	if req.Category != nil {
		fields["category"] = *req.Category
	}
	if req.Price != nil {
		fields["price"] = *req.Price
	}
	if req.Status != nil {
		fields["status"] = *req.Status
	}
	if req.Type != nil {
		fields["type"] = *req.Type
	}
	if len(fields) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "กรุณาระบุข้อมูลที่ต้องการแก้ไขอย่างน้อย 1 ช่อง"})
		return
	}
	fields["updated_at"] = time.Now().UTC()

	item, err := h.repo.Update(c.Request.Context(), id, userID, fields)
	if err != nil {
		writeItemError(c, err)
		return
	}

	c.JSON(http.StatusOK, item)
}

// [DELETE] /api/v1/items/:id - ลบอุปกรณ์ของผู้ใช้ที่เข้าสู่ระบบ
func (h *ItemHandler) DeleteItem(c *gin.Context) {
	userID, ok := h.authenticatedUserID(c)
	if !ok {
		return
	}
	id, ok := parseItemID(c)
	if !ok {
		return
	}

	if err := h.repo.Delete(c.Request.Context(), id, userID); err != nil {
		writeItemError(c, err)
		return
	}

	c.Status(http.StatusNoContent)
}
