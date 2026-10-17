package ports

import (
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"regexp"
	"strings"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
)

type UserHandler struct {
	repo     domain.AuthRepository
	verifier domain.TokenVerifier
}

const maxProfileImageSize = 5 << 20

var (
	phoneLocalPattern = regexp.MustCompile(`^0[0-9]{9}$`)
	phoneIntlPattern  = regexp.MustCompile(`^\+66[0-9]{9}$`)
	phoneAltPattern   = regexp.MustCompile(`^66[0-9]{9}$`)
)

func NewUserHandler(gateway domain.AuthGateway) *UserHandler {
	return &UserHandler{
		repo:     gateway,
		verifier: gateway,
	}
}

// Request DTOs สำหรับ HTTP Transport Layer
type userLoginRequest struct {
	Email    string `json:"email" validate:"required,email"`
	Password string `json:"password" validate:"required,min=6"`
}

type userRegisterRequest struct {
	DisplayName     string `json:"display_name" form:"display_name" validate:"required,max=150"`
	Email           string `json:"email" form:"email" validate:"required,email"`
	Phone           string `json:"phone" form:"phone" validate:"required"`
	Password        string `json:"password" form:"password" validate:"required,min=6"`
	ConfirmPassword string `json:"confirm_password" form:"confirm_password" validate:"omitempty,min=6"`
}

type userChangePasswordRequest struct {
	NewPassword string `json:"new_password" validate:"required,min=6"`
}

type userSendOTPRequest struct {
	Email string `json:"email" validate:"required,email"`
}

type userVerifyOTPResetRequest struct {
	Email   string `json:"email" validate:"required,email"`
	OTPCode string `json:"otp_code" validate:"required,len=6,numeric"`
}

type updateProfileRequest struct {
	DisplayName *string `json:"display_name" form:"display_name" validate:"omitempty,max=150"`
	Username    *string `json:"username" form:"username" validate:"omitempty,max=100"`
	Bio         *string `json:"bio" form:"bio" validate:"omitempty,max=500"`
}

type updateContactRequest struct {
	Phone string `json:"phone" validate:"required"`
}

type updateFCMTokenRequest struct {
	FCMToken string `json:"fcm_token" validate:"required"`
}

// [POST] /api/auth/login - เข้าสู่ระบบและรับ Access Token
func (h *UserHandler) Login(c fiber.Ctx) error {
	var req userLoginRequest

	if err := c.Bind().JSON(&req); err != nil {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "ข้อมูลที่ส่งมาไม่ถูกต้อง หรือรูปแบบอีเมลไม่สอดคล้อง"})
	}

	tokens, err := h.repo.Login(c.Context(), req.Email, req.Password)
	if err != nil {
		return c.Status(http.StatusUnauthorized).JSON(fiber.Map{"error": "อีเมลหรือรหัสผ่านไม่ถูกต้อง"})
	}
	if _, err := h.verifier.UserIDFromToken(c.Context(), tokens.AccessToken); err != nil {
		return appTokenError(c, err)
	}

	return c.Status(http.StatusOK).JSON(fiber.Map{
		"status":        http.StatusOK,
		"message":       "เข้าสู่ระบบสำเร็จ",
		"access_token":  tokens.AccessToken,
		"refresh_token": tokens.RefreshToken,
	})
}

// [POST] /api/auth/google-profile - บันทึกรูปโปรไฟล์จาก Google Avatar
func (h *UserHandler) SyncGoogleProfileImage(c fiber.Ctx) error {
	if _, ok := authenticatedUserID(c, h.verifier); !ok {
		return nil
	}
	userToken, ok := extractToken(c)
	if !ok {
		return nil
	}

	imageURL, err := h.repo.SyncGoogleProfileImage(c.Context(), userToken)
	if err != nil {
		status := http.StatusInternalServerError
		message := "ไม่สามารถบันทึกรูปโปรไฟล์ Google ได้"
		if strings.Contains(err.Error(), "invalid access token") ||
			strings.Contains(err.Error(), "does not contain a user") {
			status = http.StatusUnauthorized
			message = "Access Token ไม่ถูกต้องหรือหมดอายุ"
		} else if strings.Contains(err.Error(), "profile image URL was not found") ||
			strings.Contains(err.Error(), "profile was not found") {
			status = http.StatusUnprocessableEntity
			message = "ไม่พบข้อมูลโปรไฟล์หรือรูปโปรไฟล์ Google"
		}

		return c.Status(status).JSON(fiber.Map{"error": message})
	}

	return c.Status(http.StatusOK).JSON(fiber.Map{
		"status":         http.StatusOK,
		"message":        "บันทึกรูปโปรไฟล์ Google สำเร็จ",
		"user_image_url": imageURL,
	})
}

// [POST] /api/auth/register - สมัครสมาชิกผู้ใช้ใหม่
func (h *UserHandler) Register(c fiber.Ctx) error {
	var req userRegisterRequest

	if err := c.Bind().Body(&req); err != nil {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "ข้อมูลไม่ถูกต้อง หรือรูปแบบอีเมลไม่สอดคล้อง"})
	}

	req.DisplayName = strings.TrimSpace(req.DisplayName)
	req.Email = strings.TrimSpace(req.Email)
	phone, validPhone := normalizePhone(req.Phone)
	if req.DisplayName == "" {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "ชื่อ-นามสกุลไม่ถูกต้อง"})
	}
	if !validPhone {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "เบอร์โทรศัพท์ต้องเป็นตัวเลข 10 หลักและขึ้นต้นด้วย 0"})
	}
	req.Phone = phone

	if req.ConfirmPassword != "" && req.Password != req.ConfirmPassword {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "รหัสผ่านและยืนยันรหัสผ่านไม่ตรงกัน"})
	}

	profileImage, err := profileImageFromRequest(c)
	if err != nil {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": err.Error()})
	}

	result, err := h.repo.Register(c.Context(), domain.RegisterUser{
		DisplayName:  req.DisplayName,
		Email:        req.Email,
		Phone:        req.Phone,
		Password:     req.Password,
		ProfileImage: profileImage,
	})
	if err != nil {
		if strings.Contains(err.Error(), "email already registered") {
			return c.Status(http.StatusConflict).JSON(fiber.Map{"error": "อีเมลนี้ถูกใช้งานในระบบแล้ว โปรดใช้อีเมลอื่น"})
		}
		return c.Status(http.StatusInternalServerError).JSON(fiber.Map{"error": "ไม่สามารถสมัครสมาชิกได้"})
	}

	return c.Status(http.StatusCreated).JSON(fiber.Map{
		"status":         http.StatusCreated,
		"message":        "สมัครสมาชิกสำเร็จ",
		"user_id":        result.UserID,
		"user_image_url": result.UserImageURL,
	})
}

func normalizePhone(phone string) (string, bool) {
	normalized := strings.TrimSpace(phone)
	if phoneLocalPattern.MatchString(normalized) {
		return "+66" + strings.TrimPrefix(normalized, "0"), true
	}
	if phoneIntlPattern.MatchString(normalized) {
		return normalized, true
	}
	if phoneAltPattern.MatchString(normalized) {
		return "+" + normalized, true
	}
	return "", false
}

func profileImageFromRequest(c fiber.Ctx) (*domain.ProfileImage, error) {
	if !strings.HasPrefix(strings.ToLower(c.Get("Content-Type")), "multipart/form-data") {
		return nil, nil
	}

	form, err := c.MultipartForm()
	if err != nil {
		return nil, fmt.Errorf("ไม่สามารถอ่านรูปโปรไฟล์ได้")
	}
	if len(form.File["image"]) == 0 {
		return nil, nil
	}
	return readProfileImage(form.File["image"][0])
}

func readProfileImage(header *multipart.FileHeader) (*domain.ProfileImage, error) {
	if header.Size <= 0 {
		return nil, fmt.Errorf("ไฟล์รูปโปรไฟล์ว่างเปล่า")
	}
	if header.Size > maxProfileImageSize {
		return nil, fmt.Errorf("รูปโปรไฟล์ต้องมีขนาดไม่เกิน 5 MB")
	}

	file, err := header.Open()
	if err != nil {
		return nil, fmt.Errorf("ไม่สามารถเปิดรูปโปรไฟล์ได้")
	}
	defer file.Close()

	data, err := io.ReadAll(io.LimitReader(file, maxProfileImageSize+1))
	if err != nil {
		return nil, fmt.Errorf("ไม่สามารถอ่านรูปโปรไฟล์ได้")
	}
	if len(data) > maxProfileImageSize {
		return nil, fmt.Errorf("รูปโปรไฟล์ต้องมีขนาดไม่เกิน 5 MB")
	}

	contentType := http.DetectContentType(data)
	extensionByContentType := map[string]string{
		"image/jpeg": ".jpg",
		"image/png":  ".png",
		"image/webp": ".webp",
	}
	extension, ok := extensionByContentType[contentType]
	if !ok {
		return nil, fmt.Errorf("รูปโปรไฟล์ต้องเป็นไฟล์ JPEG, PNG หรือ WebP")
	}

	return &domain.ProfileImage{
		Data:        data,
		ContentType: contentType,
		Extension:   extension,
	}, nil
}

// [POST] /api/auth/change-password - เปลี่ยนรหัสผ่าน (ต้องมี Access Token)
func (h *UserHandler) ChangePassword(c fiber.Ctx) error {
	if _, ok := authenticatedUserID(c, h.verifier); !ok {
		return nil
	}
	var req userChangePasswordRequest

	if err := c.Bind().JSON(&req); err != nil {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "ข้อมูลที่ส่งมาไม่ถูกต้อง"})
	}

	userToken, ok := extractToken(c)
	if !ok {
		return nil
	}

	err := h.repo.ChangePassword(c.Context(), userToken, req.NewPassword)
	if err != nil {
		if errors.Is(err, domain.ErrInvalidAccessToken) {
			return c.Status(http.StatusUnauthorized).JSON(fiber.Map{"error": "Access Token ไม่ถูกต้องหรือหมดอายุ"})
		}
		return c.Status(http.StatusInternalServerError).JSON(fiber.Map{"error": "เปลี่ยนรหัสผ่านไม่สำเร็จ"})
	}

	return c.Status(http.StatusOK).JSON(fiber.Map{
		"status":  http.StatusOK,
		"message": "เปลี่ยนรหัสผ่านสำเร็จ",
	})
}

// [POST] /api/auth/send-otp - ส่งรหัส OTP เพื่อรีเซ็ตรหัสผ่าน (กรณีลืมรหัสผ่าน)
func (h *UserHandler) SendOTP(c fiber.Ctx) error {
	var req userSendOTPRequest
	if err := c.Bind().JSON(&req); err != nil {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "รูปแบบอีเมลไม่ถูกต้อง"})
	}

	exists, err := h.repo.IsEmailExists(c.Context(), req.Email)
	if err != nil {
		return c.Status(http.StatusInternalServerError).JSON(fiber.Map{"error": "ระบบตรวจสอบอีเมลขัดข้อง"})
	}

	if !exists {
		return c.Status(http.StatusNotFound).JSON(fiber.Map{
			"error": "ไม่พบอีเมลนี้ในระบบสมัครสมาชิก โปรดตรวจสอบความถูกต้อง",
		})
	}

	err = h.repo.SendOTP(c.Context(), req.Email)
	if err != nil {
		return c.Status(http.StatusInternalServerError).JSON(fiber.Map{"error": "ขอรหัส OTP ไม่สำเร็จ"})
	}

	return c.Status(http.StatusOK).JSON(fiber.Map{
		"status":  http.StatusOK,
		"message": "ขอรหัส OTP สำเร็จ โปรดตรวจสอบอีเมลของคุณ",
	})
}

// [POST] /api/auth/verify-otp - ตรวจสอบรหัส OTP
func (h *UserHandler) VerifyResetOTP(c fiber.Ctx) error {
	var req userVerifyOTPResetRequest

	if err := c.Bind().JSON(&req); err != nil {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "ข้อมูลไม่ถูกต้อง รหัส OTP ต้องเป็นตัวเลข 6 หลัก"})
	}

	tokens, err := h.repo.VerifyOTP(c.Context(), req.Email, req.OTPCode)
	if err != nil {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "การยืนยันรหัส OTP ล้มเหลว หรือรหัสหมดอายุ"})
	}
	if _, err := h.verifier.UserIDFromToken(c.Context(), tokens.AccessToken); err != nil {
		return appTokenError(c, err)
	}

	return c.Status(http.StatusOK).JSON(fiber.Map{
		"status":        http.StatusOK,
		"message":       "ยืนยัน OTP เรียบร้อยแล้ว",
		"access_token":  tokens.AccessToken,
		"refresh_token": tokens.RefreshToken,
	})
}

// ตรวจ session จาก OAuth และ session ที่กู้คืนก่อนเปิดข้อมูลส่วนตัวในแอป
func (h *UserHandler) Session(c fiber.Ctx) error {
	c.Set("Cache-Control", "private, no-store")
	userID, ok := authenticatedUserID(c, h.verifier)
	if !ok {
		return nil
	}
	return c.JSON(fiber.Map{"user_id": userID})
}

// [GET] /api/user/profile - ดึงข้อมูลโปรไฟล์ของผู้ใช้ที่ล็อกอินอยู่
func (h *UserHandler) GetProfile(c fiber.Ctx) error {
	userID, ok := authenticatedUserID(c, h.verifier)
	if !ok {
		return nil
	}

	profile, err := h.repo.GetProfile(c.Context(), userID)
	if err != nil {
		return c.Status(http.StatusInternalServerError).JSON(fiber.Map{"error": "ไม่สามารถโหลดข้อมูลโปรไฟล์ได้"})
	}

	return c.Status(http.StatusOK).JSON(profile)
}

// [PUT] /api/user/profile - อัปเดตข้อมูลโปรไฟล์ (ชื่อ, ไบโอ, รูปภาพ)
func (h *UserHandler) UpdateProfile(c fiber.Ctx) error {
	userID, ok := authenticatedUserID(c, h.verifier)
	if !ok {
		return nil
	}

	var req updateProfileRequest
	if strings.HasPrefix(strings.ToLower(c.Get("Content-Type")), "multipart/form-data") {
		if err := c.Bind().Body(&req); err != nil {
			return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "ข้อมูลโปรไฟล์ไม่ถูกต้อง: " + err.Error()})
		}
	} else {
		if err := c.Bind().JSON(&req); err != nil {
			return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "ข้อมูลโปรไฟล์ไม่ถูกต้อง: " + err.Error()})
		}
	}

	profileImage, err := profileImageFromRequest(c)
	if err != nil {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": err.Error()})
	}

	domainReq := domain.UpdateProfileRequest{
		DisplayName: req.DisplayName,
		Username:    req.Username,
		Bio:         req.Bio,
	}

	profile, err := h.repo.UpdateProfile(c.Context(), userID, domainReq, profileImage)
	if err != nil {
		return c.Status(http.StatusInternalServerError).JSON(fiber.Map{"error": "ไม่สามารถแก้ไขโปรไฟล์ได้"})
	}

	return c.Status(http.StatusOK).JSON(fiber.Map{
		"status":  http.StatusOK,
		"message": "บันทึกข้อมูลโปรไฟล์เรียบร้อย",
		"profile": profile,
	})
}

// [PUT] /api/user/contact - อัปเดตเบอร์โทรศัพท์ติดต่อ
func (h *UserHandler) UpdateContact(c fiber.Ctx) error {
	userID, ok := authenticatedUserID(c, h.verifier)
	if !ok {
		return nil
	}

	var req updateContactRequest
	if err := c.Bind().JSON(&req); err != nil {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "กรุณาระบุเบอร์โทรศัพท์"})
	}

	phone, valid := normalizePhone(req.Phone)
	if !valid {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "เบอร์โทรศัพท์ต้องเป็นตัวเลข 10 หลักและขึ้นต้นด้วย 0 หรือ +66"})
	}

	if err := h.repo.UpdateContact(c.Context(), userID, phone); err != nil {
		return c.Status(http.StatusInternalServerError).JSON(fiber.Map{"error": "ไม่สามารถบันทึกเบอร์โทรศัพท์ได้"})
	}

	return c.Status(http.StatusOK).JSON(fiber.Map{
		"status":  http.StatusOK,
		"message": "บันทึกข้อมูลติดต่อเรียบร้อย",
		"phone":   phone,
	})
}

// [POST] /api/user/fcm-token - อัปเดต FCM Push Token
func (h *UserHandler) UpdateFCMToken(c fiber.Ctx) error {
	userID, ok := authenticatedUserID(c, h.verifier)
	if !ok {
		return nil
	}

	var req updateFCMTokenRequest
	if err := c.Bind().JSON(&req); err != nil {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "กรุณาระบุ fcm_token"})
	}
	if strings.TrimSpace(req.FCMToken) == "" {
		return c.Status(http.StatusBadRequest).JSON(fiber.Map{"error": "กรุณาระบุ fcm_token"})
	}

	if err := h.repo.UpdateFCMToken(c.Context(), userID, req.FCMToken); err != nil {
		return c.Status(http.StatusInternalServerError).JSON(fiber.Map{"error": "ไม่สามารถบันทึก FCM Token ได้"})
	}

	return c.Status(http.StatusOK).JSON(fiber.Map{
		"status":  http.StatusOK,
		"message": "บันทึก FCM Token เรียบร้อย",
	})
}
