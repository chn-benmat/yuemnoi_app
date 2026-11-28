package ports

import (
	"errors"
	"fmt"
	"io"
	"log"
	"math"
	"mime/multipart"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
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

type createItemRequest struct {
	PickupLocation  string   `json:"pickup_location" form:"pickup_location"`
	PickupAddress   string   `json:"pickup_address" form:"pickup_address"`
	PickupLatitude  *float64 `json:"pickup_latitude" form:"pickup_latitude"`
	PickupLongitude *float64 `json:"pickup_longitude" form:"pickup_longitude"`

	ItemName     string   `json:"item_name" form:"item_name" validate:"required,min=1,max=150"`
	ItemImageURL []string `json:"item_image_url" form:"item_image_url" validate:"omitempty,dive,max=2048"`
	Description  string   `json:"description" form:"description" validate:"required,min=1,max=2000"`
	Category     string   `json:"category" form:"category" validate:"required,min=1,max=100"`
	HourlyRate   *int     `json:"hourly_rate" form:"hourly_rate" validate:"omitempty,gt=0,lte=2147483647"`
	DailyRate    *int     `json:"daily_rate" form:"daily_rate" validate:"omitempty,gt=0,lte=2147483647"`
	legacyPricing
	DamageFee     int    `json:"damage_fee" form:"damage_fee" validate:"gte=0,lte=2147483647"`
	LateReturnFee int    `json:"late_return_fee" form:"late_return_fee" validate:"gte=0,lte=2147483647"`
	DamageTerms   string `json:"damage_terms" form:"damage_terms" validate:"max=500"`
}

// legacyPricing คือราคาแบบเดิมที่แอปรุ่นก่อนยังส่งมา: price ตาม type และ daily_price เสริมของรายชั่วโมง
type legacyPricing struct {
	Price      *int    `json:"price" form:"price" validate:"omitempty,gt=0,lte=2147483647"`
	DailyPrice *int    `json:"daily_price" form:"daily_price" validate:"omitempty,gte=0,lte=2147483647"`
	Type       *string `json:"type" form:"type" validate:"omitempty,oneof=รายวัน รายชั่วโมง day hour daily hourly"`
}

func (p legacyPricing) present() bool {
	return p.Price != nil || p.DailyPrice != nil || p.Type != nil
}

// rates แปลงราคาแบบเดิมเป็นเรตต่อหน่วย ค่า 0 หมายถึงลบเรตนั้น และ ok=false เมื่อข้อมูลไม่พอ
func (p legacyPricing) rates() (hourly, daily *int, ok bool) {
	if p.Price == nil || p.Type == nil {
		return nil, nil, false
	}
	zero := 0
	if isHourlyItemType(*p.Type) {
		daily = p.DailyPrice
		if daily == nil {
			daily = &zero
		}
		return p.Price, daily, true
	}
	return &zero, p.Price, true
}

type updateItemRequest struct {
	PickupLocation  string   `json:"pickup_location" form:"pickup_location"`
	PickupAddress   string   `json:"pickup_address" form:"pickup_address"`
	PickupLatitude  *float64 `json:"pickup_latitude" form:"pickup_latitude"`
	PickupLongitude *float64 `json:"pickup_longitude" form:"pickup_longitude"`

	ItemName      *string   `json:"item_name" validate:"omitempty,min=1,max=150"`
	ItemImageURL  *[]string `json:"item_image_url" validate:"omitempty,dive,max=2048"`
	Description   *string   `json:"description" validate:"omitempty,min=1,max=2000"`
	Category      *string   `json:"category" validate:"omitempty,max=100"`
	HourlyRate    *int      `json:"hourly_rate" validate:"omitempty,gte=0,lte=2147483647"`
	DailyRate     *int      `json:"daily_rate" validate:"omitempty,gte=0,lte=2147483647"`
	DamageFee     *int      `json:"damage_fee" validate:"omitempty,gte=0,lte=2147483647"`
	LateReturnFee *int      `json:"late_return_fee" validate:"omitempty,gte=0,lte=2147483647"`
	DamageTerms   *string   `json:"damage_terms" validate:"omitempty,max=500"`
	OwnerHidden   *bool     `json:"owner_hidden"`
	legacyPricing
}

func parseItemID(c fiber.Ctx) (int64, bool) {
	id, err := strconv.ParseInt(c.Params("id"), 10, 64)
	if err != nil || id <= 0 {
		_ = c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "รหัสอุปกรณ์ต้องเป็นจำนวนเต็มที่มากกว่า 0"})
		return 0, false
	}

	return id, true
}

func positiveRate(rate *int) *int {
	if rate == nil || *rate <= 0 {
		return nil
	}
	return rate
}

func rateField(rate int) interface{} {
	if rate == 0 {
		return nil
	}
	return rate
}

func isHourlyItemType(rentalType string) bool {
	return rentalType == "รายชั่วโมง" || rentalType == "hourly" || rentalType == "hour"
}

func writeItemError(c fiber.Ctx, err error) error {
	var verification *domain.RentalVerificationRequired
	switch {
	case errors.As(err, &verification):
		return writeRentalVerificationRequired(c, verification.Verification)
	case errors.Is(err, domain.ErrItemNotFound):
		return c.Status(http.StatusNotFound).JSON(fiber.Map{"error": "ไม่พบอุปกรณ์ หรือคุณไม่ใช่เจ้าของอุปกรณ์นี้"})
	case errors.Is(err, domain.ErrItemInUse):
		return c.Status(http.StatusConflict).JSON(fiber.Map{"error": "ไม่สามารถลบอุปกรณ์ที่มีการจองหรือรีวิวอ้างอิงอยู่"})
	default:
		log.Printf("item operation failed: %v", err)
		return c.Status(http.StatusInternalServerError).JSON(fiber.Map{"error": "ระบบจัดการอุปกรณ์ขัดข้อง"})
	}
}

// [GET] /api/items - ดึงข้อมูลอุปกรณ์เช่าทั้งหมด (รองรับ query params: search, category)
func (h *ItemHandler) GetAllItems(c fiber.Ctx) error {
	items, err := h.repo.FindAll(c.Context())
	if err != nil {
		return writeItemError(c, err)
	}

	search := strings.TrimSpace(strings.ToLower(c.Query("search")))
	category := strings.TrimSpace(strings.ToLower(c.Query("category")))

	if search != "" || (category != "" && category != "all") {
		filtered := make([]domain.RankedItem, 0, len(items))
		for _, item := range items {
			if category != "" && category != "all" {
				itemCat := strings.ToLower(item.Category)
				if !strings.Contains(itemCat, category) {
					continue
				}
			}

			if search != "" {
				nameMatch := strings.Contains(strings.ToLower(item.ItemName), search)
				descMatch := strings.Contains(strings.ToLower(item.Description), search)
				catMatch := strings.Contains(strings.ToLower(item.Category), search)
				ownerMatch := strings.Contains(strings.ToLower(item.OwnerName), search)

				if !nameMatch && !descMatch && !catMatch && !ownerMatch {
					continue
				}
			}

			filtered = append(filtered, item)
		}
		items = filtered
	}

	return c.Status(http.StatusOK).JSON(items)
}

// [GET] /api/items/:id - ดึงข้อมูลอุปกรณ์เช่าตาม ID
func (h *ItemHandler) GetItemByID(c fiber.Ctx) error {
	id, ok := parseItemID(c)
	if !ok {
		return nil
	}

	item, err := h.repo.FindByID(c.Context(), id)
	if err != nil {
		return writeItemError(c, err)
	}
	if item.AccountDeletionHidden {
		return writeItemError(c, domain.ErrItemNotFound)
	}
	if item.ModerationHidden || item.OwnerHidden {
		// รายการที่ถูกซ่อนจากฟีดอ่านได้เฉพาะเจ้าของและผู้เช่าที่มีประวัติอ้างอิงอยู่
		auth := strings.Fields(c.Get("Authorization"))
		if len(auth) != 2 || !strings.EqualFold(auth[0], "Bearer") || h.tokenVerifier == nil {
			return writeItemError(c, domain.ErrItemNotFound)
		}
		userID, err := h.tokenVerifier.UserIDFromToken(c.Context(), auth[1])
		if err != nil || userID == "" {
			return writeItemError(c, domain.ErrItemNotFound)
		}
		if userID != item.UserID {
			allowed, err := h.repo.HasRentalAccess(c.Context(), id, userID)
			if err != nil {
				return writeItemError(c, err)
			}
			if !allowed {
				return writeItemError(c, domain.ErrItemNotFound)
			}
		}
	}

	return c.Status(http.StatusOK).JSON(item)
}

// [POST] /api/items - เพิ่มอุปกรณ์ของผู้ใช้ที่เข้าสู่ระบบ
func (h *ItemHandler) CreateItem(c fiber.Ctx) error {
	userID, ok := authenticatedUserID(c, h.tokenVerifier)
	if !ok {
		return nil
	}

	var req createItemRequest
	if err := c.Bind().Body(&req); err != nil {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "ข้อมูลอุปกรณ์ไม่ถูกต้อง: " + err.Error()})
	}
	if strings.TrimSpace(req.ItemName) == "" || strings.TrimSpace(req.Description) == "" || strings.TrimSpace(req.Category) == "" {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "กรุณาระบุชื่อ รายละเอียด และหมวดหมู่อุปกรณ์"})
	}
	hourlyRate, dailyRate := req.HourlyRate, req.DailyRate
	if hourlyRate == nil && dailyRate == nil && req.legacyPricing.present() {
		var ok bool
		if hourlyRate, dailyRate, ok = req.legacyPricing.rates(); !ok {
			return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "กรุณาระบุราคาและประเภทการให้เช่า"})
		}
		hourlyRate, dailyRate = positiveRate(hourlyRate), positiveRate(dailyRate)
	}
	if hourlyRate == nil && dailyRate == nil {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "กรุณาระบุราคาต่อชั่วโมงหรือราคาต่อวันอย่างน้อยหนึ่งแบบ"})
	}
	if req.DamageFee > 0 && strings.TrimSpace(req.DamageTerms) == "" {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "กรุณาระบุเงื่อนไขค่าปรับกรณีชำรุด"})
	}

	if !validPickupLocation(req.PickupLocation, req.PickupLatitude, req.PickupLongitude) {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "กรุณาระบุชื่อและพิกัดจุดนัดรับสินค้า"})
	}
	images, err := itemImagesFromRequest(c)
	if err != nil {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": err.Error()})
	}

	item, err := h.repo.Insert(c.Context(), &domain.Item{
		UserID:          userID,
		PickupLocation:  strings.TrimSpace(req.PickupLocation),
		PickupAddress:   strings.TrimSpace(req.PickupAddress),
		PickupLatitude:  req.PickupLatitude,
		PickupLongitude: req.PickupLongitude,
		ItemName:        strings.TrimSpace(req.ItemName),
		ItemImageURL:    req.ItemImageURL,
		Description:     strings.TrimSpace(req.Description),
		Category:        strings.TrimSpace(req.Category),
		HourlyRate:      hourlyRate,
		DailyRate:       dailyRate,
		DamageFee:       req.DamageFee,
		LateReturnFee:   req.LateReturnFee,
		DamageTerms:     strings.TrimSpace(req.DamageTerms),
		Status:          "pending_review",
	}, images)
	if err != nil {
		return writeItemError(c, err)
	}

	return c.Status(http.StatusCreated).JSON(item)
}

func itemImagesFromRequest(c fiber.Ctx) ([]domain.ItemImage, error) {
	if !strings.HasPrefix(strings.ToLower(c.Get("Content-Type")), "multipart/form-data") {
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

// [PUT] /api/items/:id - แก้ไขอุปกรณ์ของผู้ใช้ที่เข้าสู่ระบบ
func (h *ItemHandler) UpdateItem(c fiber.Ctx) error {
	userID, ok := authenticatedUserID(c, h.tokenVerifier)
	if !ok {
		return nil
	}
	id, ok := parseItemID(c)
	if !ok {
		return nil
	}

	var req updateItemRequest
	if err := c.Bind().JSON(&req); err != nil {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "ข้อมูลอุปกรณ์ไม่ถูกต้อง: " + err.Error()})
	}
	if (req.ItemName != nil && strings.TrimSpace(*req.ItemName) == "") ||
		(req.Description != nil && strings.TrimSpace(*req.Description) == "") {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "ชื่อและรายละเอียดอุปกรณ์ต้องไม่เป็นข้อความว่าง"})
	}

	hourlyRate, dailyRate := req.HourlyRate, req.DailyRate
	if hourlyRate == nil && dailyRate == nil && req.legacyPricing.present() {
		var ok bool
		if hourlyRate, dailyRate, ok = req.legacyPricing.rates(); !ok {
			return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "กรุณาระบุราคาต่อชั่วโมงเมื่อเพิ่มราคาต่อวัน"})
		}
	}
	if hourlyRate != nil && dailyRate != nil && *hourlyRate == 0 && *dailyRate == 0 {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "กรุณาระบุราคาต่อชั่วโมงหรือราคาต่อวันอย่างน้อยหนึ่งแบบ"})
	}
	if req.DamageFee != nil && *req.DamageFee > 0 && req.DamageTerms != nil && strings.TrimSpace(*req.DamageTerms) == "" {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "กรุณาระบุเงื่อนไขค่าปรับกรณีชำรุด"})
	}

	fields := make(map[string]interface{})
	listingContentChanged := req.ItemName != nil || req.ItemImageURL != nil || req.Description != nil ||
		req.Category != nil || hourlyRate != nil || dailyRate != nil ||
		req.DamageFee != nil || req.LateReturnFee != nil || req.DamageTerms != nil ||
		req.PickupLocation != "" || req.PickupLatitude != nil || req.PickupLongitude != nil
	if listingContentChanged {
		if !validPickupLocation(req.PickupLocation, req.PickupLatitude, req.PickupLongitude) {
			return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "กรุณาระบุชื่อและพิกัดจุดนัดรับสินค้า"})
		}
		fields["pickup_location"] = strings.TrimSpace(req.PickupLocation)
		fields["pickup_address"] = strings.TrimSpace(req.PickupAddress)
		fields["pickup_latitude"] = *req.PickupLatitude
		fields["pickup_longitude"] = *req.PickupLongitude
	}
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
	// ค่า 0 คือเลิกให้เช่าหน่วยนั้น ฐานบังคับให้เหลืออย่างน้อยหนึ่งเรต
	if hourlyRate != nil {
		fields["hourly_rate"] = rateField(*hourlyRate)
	}
	if dailyRate != nil {
		fields["daily_rate"] = rateField(*dailyRate)
	}
	if req.DamageFee != nil {
		fields["damage_fee"] = *req.DamageFee
	}
	if req.LateReturnFee != nil {
		fields["late_return_fee"] = *req.LateReturnFee
	}
	if req.DamageTerms != nil {
		fields["damage_terms"] = strings.TrimSpace(*req.DamageTerms)
	}
	if req.OwnerHidden != nil {
		fields["owner_hidden"] = *req.OwnerHidden
	}
	if listingContentChanged {
		// การแก้เนื้อหาประกาศต้องกลับเข้าคิวตรวจสอบก่อนแสดงในฟีดอีกครั้ง
		fields["status"] = "pending_review"
		fields["moderation_hidden"] = true
	}
	if len(fields) == 0 {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "กรุณาระบุข้อมูลที่ต้องการแก้ไขอย่างน้อย 1 ช่อง"})
	}
	fields["updated_at"] = time.Now().UTC()

	item, err := h.repo.Update(c.Context(), id, userID, fields)
	if err != nil {
		return writeItemError(c, err)
	}

	return c.Status(http.StatusOK).JSON(item)
}

// [DELETE] /api/items/:id - ลบอุปกรณ์ของผู้ใช้ที่เข้าสู่ระบบ
func (h *ItemHandler) DeleteItem(c fiber.Ctx) error {
	userID, ok := authenticatedUserID(c, h.tokenVerifier)
	if !ok {
		return nil
	}
	id, ok := parseItemID(c)
	if !ok {
		return nil
	}

	if err := h.repo.Delete(c.Context(), id, userID); err != nil {
		return writeItemError(c, err)
	}

	return c.SendStatus(http.StatusNoContent)
}

func validPickupLocation(name string, lat, lng *float64) bool {
	return strings.TrimSpace(name) != "" && len(name) <= 500 && lat != nil && lng != nil &&
		!math.IsNaN(*lat) && !math.IsNaN(*lng) && !math.IsInf(*lat, 0) && !math.IsInf(*lng, 0) &&
		*lat >= -90 && *lat <= 90 && *lng >= -180 && *lng <= 180
}
