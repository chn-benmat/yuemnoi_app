package ports

import (
	"errors"
	"fmt"
	"io"
	"log"
	"mime/multipart"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gin-gonic/gin"
)

const (
	maxItemImages    = 5
	maxItemImageSize = 5 << 20
)

type ItemHandler struct {
	repo          domain.ItemRepository
	tokenVerifier domain.TokenVerifier
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

	var req domain.CreateItemRequest
	if err := c.ShouldBind(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลอุปกรณ์ไม่ถูกต้อง: " + err.Error()})
		return
	}

	images, err := itemImagesFromRequest(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	item, err := h.repo.Insert(c.Request.Context(), &domain.Item{
		UserID:       userID,
		ItemName:     strings.TrimSpace(req.ItemName),
		ItemImageURL: req.ItemImageURL,
		Description:  strings.TrimSpace(req.Description),
		Category:     strings.TrimSpace(req.Category),
		Price:        req.Price,
		Status:       "pending",
		Type:         req.Type,
	}, images)
	if err != nil {
		writeItemError(c, err)
		return
	}

	c.JSON(http.StatusCreated, item)
}

func itemImagesFromRequest(c *gin.Context) ([]domain.ItemImage, error) {
	if !strings.HasPrefix(strings.ToLower(c.GetHeader("Content-Type")), "multipart/form-data") {
		return nil, nil
	}

	form, err := c.MultipartForm()
	if err != nil {
		return nil, fmt.Errorf("ไม่สามารถอ่านรูปอุปกรณ์ได้")
	}
	headers := form.File["images"]
	if len(headers) > maxItemImages {
		return nil, fmt.Errorf("เพิ่มรูปอุปกรณ์ได้ไม่เกิน %d รูป", maxItemImages)
	}

	images := make([]domain.ItemImage, 0, len(headers))
	for _, header := range headers {
		image, err := readItemImage(header)
		if err != nil {
			return nil, err
		}
		images = append(images, *image)
	}
	return images, nil
}

func readItemImage(header *multipart.FileHeader) (*domain.ItemImage, error) {
	if header.Size <= 0 {
		return nil, fmt.Errorf("ไฟล์รูปอุปกรณ์ว่างเปล่า")
	}
	if header.Size > maxItemImageSize {
		return nil, fmt.Errorf("รูปอุปกรณ์แต่ละรูปต้องมีขนาดไม่เกิน 5 MB")
	}

	file, err := header.Open()
	if err != nil {
		return nil, fmt.Errorf("ไม่สามารถเปิดรูปอุปกรณ์ได้")
	}
	defer file.Close()

	data, err := io.ReadAll(io.LimitReader(file, maxItemImageSize+1))
	if err != nil {
		return nil, fmt.Errorf("ไม่สามารถอ่านรูปอุปกรณ์ได้")
	}
	if len(data) > maxItemImageSize {
		return nil, fmt.Errorf("รูปอุปกรณ์แต่ละรูปต้องมีขนาดไม่เกิน 5 MB")
	}

	contentType := http.DetectContentType(data)
	extensionByContentType := map[string]string{
		"image/jpeg": ".jpg",
		"image/png":  ".png",
		"image/webp": ".webp",
	}
	extension, ok := extensionByContentType[contentType]
	if !ok {
		return nil, fmt.Errorf("รูปอุปกรณ์ต้องเป็นไฟล์ JPEG, PNG หรือ WebP")
	}

	return &domain.ItemImage{Data: data, ContentType: contentType, Extension: extension}, nil
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

	var req domain.UpdateItemRequest
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
