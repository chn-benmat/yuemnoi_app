package ports

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
	"image"
	"image/jpeg"
	_ "image/png"
	"io"
	"mime/multipart"
	"net/http"
	"strconv"
	"strings"
	"time"
)

type OperationsHandler struct {
	options  domain.OperationsOptions
	verifier domain.TokenVerifier
}

func NewOperationsHandler(o domain.OperationsOptions, v domain.TokenVerifier) *OperationsHandler {
	return &OperationsHandler{o, v}
}
func (h *OperationsHandler) actor(c fiber.Ctx) (string, bool) {
	c.Set("Cache-Control", "private, no-store")
	c.Set("X-Content-Type-Options", "nosniff")
	u, ok := authenticatedUserID(c, h.verifier)
	if !ok {
		return "", false
	}
	if h.options.Store == nil {
		_ = c.Status(503).JSON(fiber.Map{"error": "ระบบเจ้าหน้าที่และยืนยันตัวตนยังไม่เปิดใช้งาน"})
		return "", false
	}
	return u, true
}
func operationError(c fiber.Ctx, err error) error {
	code := err.Error()
	status := http.StatusConflict
	messages := map[string]string{
		"staff_required": "บัญชีนี้ไม่มีสิทธิ์เจ้าหน้าที่", "pilot_invite_required": "บัญชีนี้ยังไม่ได้รับเชิญเข้าร่วมทดลอง",
		"account_suspended": "บัญชีถูกระงับการทำรายการใหม่", "active_request_exists": "มีคำขอที่กำลังดำเนินการอยู่",
		"capture_expired": "รอบถ่ายภาพหมดอายุ กรุณาเริ่มใหม่", "request_not_pending": "คำขอนี้หมดอายุหรือมีผลพิจารณาแล้ว",
		"self_review_forbidden": "ต้องให้เจ้าหน้าที่คนอื่นพิจารณาคำขอนี้", "identity_duplicate": "พบข้อมูลซ้ำ กรุณาตรวจสอบโดยเจ้าหน้าที่",
		"card_expired": "บัตรหมดอายุ กรุณาใช้บัตรปัจจุบัน", "reason_required": "กรุณาระบุเหตุผล 3–500 ตัวอักษร",
		"card_validity_required": "กรุณาระบุวันหมดอายุหรือบัตรตลอดชีพตามภาพบัตรที่ตรวจแล้ว",
		"last_staff_required":    "ต้องเหลือเจ้าหน้าที่ที่ใช้งานได้อย่างน้อยหนึ่งบัญชี", "self_suspend_forbidden": "ไม่สามารถระงับบัญชีตนเอง",
		"manual_review_required": "กรุณายืนยันว่าตรวจหลักฐานด้วยตนเองแล้ว",
		"evidence_unavailable":   "หลักฐานหมดอายุหรือถูกลบแล้ว", "invalid_date_range": "ช่วงเวลารายงานไม่ถูกต้อง",
		"invalid_settings": "กรุณาระบุค่าการเปิดใช้งานเป็น true หรือ false",
	}
	message, known := messages[code]
	if !known {
		status = 503
		code = "operations_unavailable"
		message = "ไม่สามารถดำเนินการได้ กรุณาลองใหม่"
	}
	if code == "staff_required" || code == "account_suspended" {
		status = 403
	}
	if code == "invalid_settings" {
		status = http.StatusBadRequest
	}
	if code == "evidence_unavailable" {
		status = 410
	}
	return c.Status(status).JSON(fiber.Map{"error": message, "code": code})
}
func (h *OperationsHandler) rpc(c fiber.Ctx, name string, args map[string]any) error {
	result, err := h.options.Store.RPC(c.Context(), name, args)
	if err != nil {
		return operationError(c, err)
	}
	c.Set("Content-Type", "application/json")
	return c.Send(result)
}
func (h *OperationsHandler) Status(c fiber.Ctx) error {
	u, ok := h.actor(c)
	if !ok {
		return nil
	}
	return h.rpc(c, "identity_status", map[string]any{"p_actor": u})
}
func (h *OperationsHandler) Begin(c fiber.Ctx) error {
	u, ok := h.actor(c)
	if !ok {
		return nil
	}
	if len(h.options.EncryptionKey) != 32 || len(h.options.HMACKey) < 32 {
		return operationError(c, errors.New("operations_unavailable"))
	}
	var req struct {
		Minor     *bool   `json:"is_minor"`
		BirthDate *string `json:"birth_date"`
		Consent   string  `json:"consent_version" validate:"required,eq=identity-v1"`
	}
	if err := c.Bind().JSON(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "กรุณายอมรับเงื่อนไขการใช้ข้อมูลเพื่อยืนยันตัวตน"})
	}
	var minor bool
	if req.BirthDate != nil {
		// เก็บข้อมูลช่วงอายุเดิมเพื่อความเข้ากันได้เท่านั้น ไม่ใช้ตัดสิทธิ์หรือกำหนดผู้ปกครอง
		var err error
		minor, err = domain.IdentityAge(*req.BirthDate, time.Now().UTC())
		if err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "กรุณาระบุวันเกิดให้ถูกต้อง", "code": "invalid_birth_date"})
		}
	} else if req.Minor != nil {
		minor = *req.Minor
	}
	return h.rpc(c, "identity_begin", map[string]any{"p_actor": u, "p_minor": minor, "p_consent": req.Consent})
}
func readEvidence(header *multipart.FileHeader) ([]byte, string, error) {
	if header == nil || header.Size <= 0 || header.Size > 5<<20 {
		return nil, "", errors.New("invalid_image")
	}
	file, err := header.Open()
	if err != nil {
		return nil, "", err
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, (5<<20)+1))
	if err != nil || len(data) > 5<<20 {
		return nil, "", errors.New("invalid_image")
	}
	content := http.DetectContentType(data)
	if content != "image/jpeg" && content != "image/png" {
		return nil, "", errors.New("invalid_image")
	}
	config, _, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil || config.Width <= 0 || config.Height <= 0 || int64(config.Width)*int64(config.Height) > 16000000 {
		return nil, "", errors.New("invalid_image")
	}
	decoded, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return nil, "", errors.New("invalid_image")
	}
	var clean bytes.Buffer
	if err = jpeg.Encode(&clean, decoded, &jpeg.Options{Quality: 92}); err != nil || clean.Len() > 5<<20 {
		return nil, "", errors.New("invalid_image")
	}
	return clean.Bytes(), "image/jpeg", nil
}
func randomPath(user string) string {
	var b [20]byte
	_, _ = rand.Read(b[:])
	return user + "/" + hex.EncodeToString(b[:])
}

func (h *OperationsHandler) Submit(c fiber.Ctx) error {
	u, ok := h.actor(c)
	if !ok {
		return nil
	}
	if len(h.options.EncryptionKey) != 32 || len(h.options.HMACKey) < 32 {
		return operationError(c, errors.New("operations_unavailable"))
	}
	id := c.Params("id")
	if !validUUID(id) {
		return c.Status(400).JSON(fiber.Map{"error": "รหัสคำขอไม่ถูกต้อง"})
	}
	// ตรวจเจ้าของและอายุรอบถ่ายภาพก่อนรับหลักฐาน
	status, err := h.options.Store.RPC(c.Context(), "identity_status", map[string]any{"p_actor": u})
	if err != nil {
		return operationError(c, err)
	}
	var current struct {
		Request struct {
			ID, Status   string
			CaptureUntil time.Time `json:"capture_until"`
		} `json:"request"`
	}
	if json.Unmarshal(status, &current) != nil || current.Request.ID != id || current.Request.Status != "capture" || current.Request.CaptureUntil.Before(time.Now()) {
		return operationError(c, errors.New("capture_expired"))
	}
	legal := strings.TrimSpace(c.FormValue("legal_name"))
	citizen := strings.TrimSpace(c.FormValue("citizen_id"))
	dob := c.FormValue("birth_date")
	minor, err := domain.IdentityAge(dob, time.Now().UTC())
	if err != nil || !domain.ValidThaiCitizenID(citizen) || len(legal) < 3 || len(legal) > 450 {
		return c.Status(400).JSON(fiber.Map{"error": "กรุณาตรวจชื่อ เลขบัตร และวันเกิด"})
	}
	form, err := c.MultipartForm()
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "ไฟล์ภาพไม่ถูกต้อง"})
	}
	details, err := parseIdentityDetails(form.Value)
	if err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "กรุณาตรวจคำนำหน้าชื่อ ชื่อ นามสกุล และที่อยู่ตามบัตรประชาชนให้ครบถ้วน"})
	}
	if details != nil {
		legal = details.NamePrefix + " " + details.FirstName + " " + details.LastName
		if len(legal) > 450 {
			return c.Status(400).JSON(fiber.Map{"error": "ชื่อและนามสกุลยาวเกินกำหนด"})
		}
	}
	files := map[string][]byte{}
	types := map[string]string{}
	for _, kind := range []string{"card", "selfie"} {
		if len(form.File[kind]) != 1 {
			return c.Status(400).JSON(fiber.Map{"error": "ต้องมีภาพบัตรและภาพใบหน้าอย่างละหนึ่งภาพ"})
		}
		files[kind], types[kind], err = readEvidence(form.File[kind][0])
		if err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "รองรับ JPEG/PNG ไม่เกินภาพละ 5 MB"})
		}
	}
	raw, _ := json.Marshal(struct {
		*identityDetailsRequest
		CitizenID string `json:"citizen_id"`
		BirthDate string `json:"birth_date"`
	}{details, citizen, dob})
	encrypted, err := domain.EncryptIdentity(raw, h.options.EncryptionKey)
	if err != nil {
		return operationError(c, err)
	}
	paths := []string{}
	evidence := []map[string]any{}
	rollback := func() {
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		for _, p := range paths {
			_ = h.options.Store.DeleteEvidence(ctx, p)
		}
	}
	for _, kind := range []string{"card", "selfie"} {
		path := randomPath(u)
		paths = append(paths, path)
		evidence = append(evidence, map[string]any{"kind": kind, "object_path": path})
	}
	// ลงทะเบียนกำหนดลบก่อนอัปโหลด ป้องกันไฟล์ตกค้างเมื่อโปรเซสหยุดกลางทาง
	if _, err = h.options.Store.RPC(c.Context(), "identity_reserve_evidence", map[string]any{"p_actor": u, "p_id": id, "p_evidence": evidence}); err != nil {
		return operationError(c, err)
	}
	// อัปโหลดคนละไฟล์พร้อมกัน และรอทั้งสองงานจบก่อนบันทึกหรือลบไฟล์คืน
	uploadContext := c.Context()
	uploadErrors := make(chan error, len(paths))
	for i, kind := range []string{"card", "selfie"} {
		go func() {
			uploadErrors <- h.options.Store.UploadEvidence(uploadContext, paths[i], files[kind], types[kind])
		}()
	}
	var uploadError error
	for range paths {
		if failure := <-uploadErrors; failure != nil && uploadError == nil {
			uploadError = failure
		}
	}
	if uploadError != nil {
		rollback()
		return operationError(c, uploadError)
	}
	result, err := h.options.Store.RPC(c.Context(), "identity_submit", map[string]any{"p_actor": u, "p_id": id, "p_data": map[string]any{
		"legal_name": legal, "masked_id": "*********" + citizen[9:], "citizen_hmac": domain.CitizenHMAC(citizen, h.options.HMACKey),
		// อายุบัตรระบุโดยเจ้าหน้าที่หลังตรวจภาพเท่านั้น
		"expires_on": nil, "lifetime": false, "is_minor": minor, "raw_encrypted": encrypted, "analysis": map[string]any{"review_mode": "manual"},
	}, "p_evidence": evidence})
	if err != nil {
		rollback()
		return operationError(c, err)
	}
	c.Set("Content-Type", "application/json")
	return c.Status(201).Send(result)
}
func validUUID(s string) bool {
	if len(s) != 36 {
		return false
	}
	_, err := hex.DecodeString(strings.ReplaceAll(s, "-", ""))
	return err == nil && s[8] == '-' && s[13] == '-' && s[18] == '-' && s[23] == '-'
}
func (h *OperationsHandler) Complaint(c fiber.Ctx) error {
	u, ok := h.actor(c)
	if !ok {
		return nil
	}
	var req struct {
		ItemID      int64  `json:"item_id" validate:"required,gt=0"`
		Description string `json:"description" validate:"required,min=5,max=2000"`
	}
	if err := c.Bind().JSON(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "กรุณาระบุรายละเอียด 5–2000 ตัวอักษร"})
	}
	return h.rpc(c, "complaint_submit", map[string]any{"p_actor": u, "p_item": req.ItemID, "p_description": req.Description})
}
func (h *OperationsHandler) Read(c fiber.Ctx) error {
	u, ok := h.actor(c)
	if !ok {
		return nil
	}
	page, err := strconv.Atoi(c.Query("page", "0"))
	if err != nil || page < 0 || page > 100000 {
		return c.Status(400).JSON(fiber.Map{"error": "หน้าข้อมูลไม่ถูกต้อง"})
	}
	q := map[string]any{"page": page, "search": c.Query("search"), "status": c.Query("status")}
	for _, k := range []string{"from", "to", "id"} {
		if s := c.Query(k); s != "" {
			q[k] = s
		}
	}
	module := c.Params("module")
	if module == "guardians" || module == "guardian-detail" {
		return c.SendStatus(404)
	}
	raw, err := h.options.Store.RPC(c.Context(), "admin_read", map[string]any{"p_actor": u, "p_module": module, "p_query": q})
	if err != nil {
		return operationError(c, err)
	}
	var result map[string]any
	if err = json.Unmarshal(raw, &result); err != nil {
		return operationError(c, err)
	}
	if module == "identity-detail" && validUUID(c.Query("id")) {
		sensitive, e := h.options.Store.RPC(c.Context(), "identity_sensitive", map[string]any{"p_actor": u, "p_id": c.Query("id")})
		if e != nil {
			return operationError(c, e)
		}
		var encrypted struct {
			Value string `json:"raw_encrypted"`
		}
		if json.Unmarshal(sensitive, &encrypted) == nil && encrypted.Value != "" {
			plain, e := domain.DecryptIdentity(encrypted.Value, h.options.EncryptionKey)
			if e != nil {
				return operationError(c, e)
			}
			var value map[string]any
			if json.Unmarshal(plain, &value) != nil {
				return c.SendStatus(503)
			}
			result["sensitive"] = value
		}
	}
	if module == "health" {
		result["backend"] = "ready"
		result["cleanup"] = "unavailable"
		if last, ok := result["cleanup_last_success"].(string); ok {
			if t, e := time.Parse(time.RFC3339Nano, last); e == nil && time.Since(t) < 2*h.options.CleanupInterval {
				result["cleanup"] = "ready"
			}
		}
	}
	return c.JSON(result)
}
func (h *OperationsHandler) Action(c fiber.Ctx) error {
	if c.Params("action") == "guardian-review" || c.Params("action") == "revoke-guardian" {
		return c.SendStatus(404)
	}
	u, ok := h.actor(c)
	if !ok {
		return nil
	}
	var data map[string]any
	if err := c.Bind().JSON(&data); err != nil {
		return c.Status(400).JSON(fiber.Map{"error": "ข้อมูลการดำเนินงานไม่ถูกต้อง"})
	}
	return h.rpc(c, "admin_action", map[string]any{"p_actor": u, "p_action": c.Params("action"), "p_target": c.Params("target"), "p_data": data})
}
func (h *OperationsHandler) Evidence(c fiber.Ctx) error {
	u, ok := h.actor(c)
	if !ok {
		return nil
	}
	if !validUUID(c.Params("id")) {
		return c.SendStatus(400)
	}
	raw, err := h.options.Store.RPC(c.Context(), "evidence_access", map[string]any{"p_actor": u, "p_id": c.Params("id")})
	if err != nil {
		return operationError(c, err)
	}
	var e struct {
		Path string `json:"object_path"`
	}
	if json.Unmarshal(raw, &e) != nil || e.Path == "" {
		return c.SendStatus(410)
	}
	data, content, err := h.options.Store.ReadEvidence(c.Context(), e.Path)
	if err != nil {
		return operationError(c, err)
	}
	if content != "image/jpeg" && content != "image/png" {
		return c.SendStatus(415)
	}
	c.Set("Content-Type", content)
	return c.Send(data)
}

// CleanupIdentity ลบไฟล์ก่อนลบค่าดิบ เพื่อให้ retry ได้หาก Storage ขัดข้อง
func CleanupIdentity(ctx context.Context, store domain.OperationsStore) error {
	raw, err := store.RPC(ctx, "identity_cleanup", map[string]any{"p_done": nil})
	if err != nil {
		return err
	}
	var rows []struct {
		ID   string `json:"id"`
		Path string `json:"object_path"`
	}
	if err = json.Unmarshal(raw, &rows); err != nil {
		return err
	}
	for _, r := range rows {
		if err = store.DeleteEvidence(ctx, r.Path); err != nil {
			return err
		}
		if _, err = store.RPC(ctx, "identity_cleanup", map[string]any{"p_done": r.ID}); err != nil {
			return err
		}
	}
	_, err = store.RPC(ctx, "identity_cleanup", map[string]any{"p_done": nil, "p_completed": true})
	return err
}
