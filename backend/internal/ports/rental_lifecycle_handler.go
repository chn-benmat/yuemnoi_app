package ports

import (
	"bytes"
	"encoding/json"
	"fmt"
	"image"
	"image/jpeg"
	_ "image/png"
	"io"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
)

// รูปหลักฐานผ่านการถอดและเข้ารหัสใหม่เพื่อลบ metadata ก่อนเก็บในพื้นที่ส่วนตัว
func rentalEvidenceImages(c fiber.Ctx, min, max int) ([]domain.ItemImage, error) {
	form, err := c.MultipartForm()
	if err != nil {
		return nil, fmt.Errorf("กรุณาแนบภาพถ่ายหลักฐาน")
	}
	files := form.File["photos"]
	if len(files) < min || len(files) > max {
		return nil, fmt.Errorf("กรุณาแนบภาพถ่าย %d–%d รูป", min, max)
	}
	result := make([]domain.ItemImage, 0, len(files))
	for _, header := range files {
		if header.Size <= 0 || header.Size > 5<<20 {
			return nil, fmt.Errorf("รูปแต่ละรูปต้องไม่เกิน 5 MB")
		}
		file, err := header.Open()
		if err != nil {
			return nil, err
		}
		data, readErr := io.ReadAll(io.LimitReader(file, (5<<20)+1))
		file.Close()
		if readErr != nil || len(data) > 5<<20 {
			return nil, fmt.Errorf("อ่านรูปภาพไม่ได้")
		}
		config, _, err := image.DecodeConfig(bytes.NewReader(data))
		if err != nil || config.Width <= 0 || config.Height <= 0 || int64(config.Width)*int64(config.Height) > 16000000 {
			return nil, fmt.Errorf("รูปต้องเป็น JPEG หรือ PNG ขนาดไม่เกิน 16 ล้านพิกเซล")
		}
		decoded, _, err := image.Decode(bytes.NewReader(data))
		if err != nil {
			return nil, fmt.Errorf("รูปภาพไม่สมบูรณ์")
		}
		var clean bytes.Buffer
		if err = jpeg.Encode(&clean, decoded, &jpeg.Options{Quality: 88}); err != nil || clean.Len() > 5<<20 {
			return nil, fmt.Errorf("รูปภาพมีขนาดใหญ่เกินไป")
		}
		result = append(result, domain.ItemImage{Data: clean.Bytes(), ContentType: "image/jpeg", Extension: ".jpg"})
	}
	return result, nil
}

func (h *RentalHandler) GetRentalReturnSession(c fiber.Ctx) error {
	user, ok := authenticatedUserID(c, h.tokenVerifier)
	if !ok {
		return nil
	}
	id, ok := parseRentalID(c)
	if !ok {
		return nil
	}
	result, err := h.rentalRepository.RentalReturnSession(c.Context(), user, id)
	if err != nil {
		return writeRentalStatusError(c, err)
	}
	c.Set("Cache-Control", "private, no-store")
	return c.JSON(result)
}

func (h *RentalHandler) SubmitRentalReturnEvidence(c fiber.Ctx) error {
	user, ok := authenticatedUserID(c, h.tokenVerifier)
	if !ok {
		return nil
	}
	id, ok := parseRentalID(c)
	if !ok {
		return nil
	}
	images, err := rentalEvidenceImages(c, 3, 3)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": err.Error()})
	}
	var checklist map[string]bool
	if json.Unmarshal([]byte(c.FormValue("checklist")), &checklist) != nil || !checklist["power_on"] || !checklist["no_new_cracks"] || !checklist["accessories_complete"] {
		return c.Status(400).JSON(fiber.Map{"error": "กรุณายืนยันรายการตรวจสภาพให้ครบทุกข้อ"})
	}
	order, err := h.rentalRepository.SubmitRentalEvidence(c.Context(), user, id, images, checklist)
	if err != nil {
		return writeRentalStatusError(c, err)
	}
	return c.JSON(order)
}

func (h *RentalHandler) InspectRentalReturn(c fiber.Ctx) error {
	user, ok := authenticatedUserID(c, h.tokenVerifier)
	if !ok {
		return nil
	}
	id, ok := parseRentalID(c)
	if !ok {
		return nil
	}
	var req struct {
		Checked bool `json:"checked"`
	}
	if c.Bind().JSON(&req) != nil || !req.Checked {
		return c.Status(400).JSON(fiber.Map{"error": "กรุณายืนยันว่าตรวจรับอุปกรณ์แล้ว"})
	}
	result, err := h.rentalRepository.InspectRentalReturn(c.Context(), user, id)
	if err != nil {
		return writeRentalStatusError(c, err)
	}
	c.Set("Cache-Control", "private, no-store")
	return c.JSON(result)
}

func (h *RentalHandler) ConfirmRentalReceipt(c fiber.Ctx) error {
	user, ok := authenticatedUserID(c, h.tokenVerifier)
	if !ok {
		return nil
	}
	id, ok := parseRentalID(c)
	if !ok {
		return nil
	}
	var req struct {
		Checked bool `json:"checked"`
	}
	if c.Bind().JSON(&req) != nil || !req.Checked {
		return c.Status(400).JSON(fiber.Map{"error": "กรุณายืนยันว่าตรวจรับอุปกรณ์แล้ว"})
	}
	order, err := h.rentalRepository.ConfirmRentalReceipt(c.Context(), user, id)
	if err != nil {
		return writeRentalStatusError(c, err)
	}
	return c.JSON(order)
}

func (h *RentalHandler) CancelRental(c fiber.Ctx) error {
	user, ok := authenticatedUserID(c, h.tokenVerifier)
	if !ok {
		return nil
	}
	id, ok := parseRentalID(c)
	if !ok {
		return nil
	}
	images, err := rentalEvidenceImages(c, 1, 5)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": err.Error()})
	}
	order, err := h.rentalRepository.CancelRental(c.Context(), user, id, c.FormValue("reason"), c.FormValue("note"), images)
	if err != nil {
		return writeRentalStatusError(c, err)
	}
	return c.JSON(order)
}
