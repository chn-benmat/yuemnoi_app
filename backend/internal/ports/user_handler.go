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
	"github.com/gin-gonic/gin"
)

type UserHandler struct {
	repo     domain.AuthRepository
	verifier domain.TokenVerifier
}

const maxProfileImageSize = 5 << 20

var phonePattern = regexp.MustCompile(`^0[0-9]{9}$`)

func NewUserHandler(gateway domain.AuthGateway) *UserHandler {
	return &UserHandler{
		repo:     gateway,
		verifier: gateway,
	}
}

func (h *UserHandler) authenticatedUserID(c *gin.Context) (string, bool) {
	token, ok := extractToken(c)
	if !ok {
		return "", false
	}

	userID, err := h.verifier.UserIDFromToken(c.Request.Context(), token)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Access Token ไม่ถูกต้องหรือหมดอายุ"})
		return "", false
	}

	return userID, true
}

// สำหรับสกัดเอาเฉพาะ JWT Token ล้วนๆ
func extractToken(c *gin.Context) (string, bool) {
	authHeader := c.GetHeader("Authorization")
	if authHeader == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "กรุณาแนบ Access Token ใน Header"})
		return "", false
	}

	tokenParts := strings.Split(authHeader, " ")
	if len(tokenParts) != 2 || strings.ToLower(tokenParts[0]) != "bearer" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "รูปแบบ Authorization Header ไม่ถูกต้อง (ต้องเป็น Bearer <token>)"})
		return "", false
	}
	return tokenParts[1], true
}

// [POST] /api/v1/auth/login - เข้าสู่ระบบและรับ Access Token
func (h *UserHandler) Login(c *gin.Context) {
	var req domain.UserLoginRequest

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลที่ส่งมาไม่ถูกต้อง หรือรูปแบบอีเมลไม่สอดคล้อง"})
		return
	}

	tokens, err := h.repo.Login(c.Request.Context(), req.Email, req.Password)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "อีเมลหรือรหัสผ่านไม่ถูกต้อง"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":        http.StatusOK,
		"message":       "เข้าสู่ระบบสำเร็จ",
		"access_token":  tokens.AccessToken,
		"refresh_token": tokens.RefreshToken,
	})
}

// [POST] /api/v1/auth/register - สมัครสมาชิกผู้ใช้ใหม่
// SyncGoogleProfileImage saves the signed-in Google user's avatar URL.
func (h *UserHandler) SyncGoogleProfileImage(c *gin.Context) {
	userToken, ok := extractToken(c)
	if !ok {
		return
	}

	imageURL, err := h.repo.SyncGoogleProfileImage(c.Request.Context(), userToken)
	if err != nil {
		status := http.StatusInternalServerError
		if strings.Contains(err.Error(), "invalid access token") ||
			strings.Contains(err.Error(), "does not contain a user") {
			status = http.StatusUnauthorized
		} else if strings.Contains(err.Error(), "profile image URL was not found") ||
			strings.Contains(err.Error(), "profile was not found") {
			status = http.StatusUnprocessableEntity
		}

		c.JSON(status, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":         http.StatusOK,
		"message":        "บันทึกรูปโปรไฟล์ Google สำเร็จ",
		"user_image_url": imageURL,
	})
}

func (h *UserHandler) Register(c *gin.Context) {
	var req domain.UserRegisterRequest

	if err := c.ShouldBind(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลไม่ถูกต้อง หรือรูปแบบอีเมลไม่สอดคล้อง"})
		return
	}

	req.DisplayName = strings.TrimSpace(req.DisplayName)
	req.Email = strings.TrimSpace(req.Email)
	phone, validPhone := normalizePhone(req.Phone)
	if req.DisplayName == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ชื่อ-นามสกุลไม่ถูกต้อง"})
		return
	}
	if !validPhone {
		c.JSON(http.StatusBadRequest, gin.H{"error": "เบอร์โทรศัพท์ต้องเป็นตัวเลข 10 หลักและขึ้นต้นด้วย 0"})
		return
	}
	req.Phone = phone

	if req.ConfirmPassword != "" && req.Password != req.ConfirmPassword {
		c.JSON(http.StatusBadRequest, gin.H{"error": "รหัสผ่านและยืนยันรหัสผ่านไม่ตรงกัน"})
		return
	}

	profileImage, err := profileImageFromRequest(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	result, err := h.repo.Register(c.Request.Context(), domain.RegisterUser{
		DisplayName:  req.DisplayName,
		Email:        req.Email,
		Phone:        req.Phone,
		Password:     req.Password,
		ProfileImage: profileImage,
	})
	if err != nil {
		// ตรวจจับอีเมลซ้ำ
		if strings.Contains(err.Error(), "email already registered") {
			c.JSON(http.StatusConflict, gin.H{"error": "อีเมลนี้ถูกใช้งานในระบบแล้ว โปรดใช้อีเมลอื่น"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถสมัครสมาชิกได้: " + err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"status":         http.StatusCreated,
		"message":        "สมัครสมาชิกสำเร็จ",
		"user_id":        result.UserID,
		"user_image_url": result.UserImageURL,
	})
}

func normalizePhone(phone string) (string, bool) {
	normalized := strings.TrimSpace(phone)
	if !phonePattern.MatchString(normalized) {
		return "", false
	}
	return "+66" + strings.TrimPrefix(normalized, "0"), true
}

func profileImageFromRequest(c *gin.Context) (*domain.ProfileImage, error) {
	if !strings.HasPrefix(strings.ToLower(c.GetHeader("Content-Type")), "multipart/form-data") {
		return nil, nil
	}

	header, err := c.FormFile("image")
	if errors.Is(err, http.ErrMissingFile) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("ไม่สามารถอ่านรูปโปรไฟล์ได้")
	}

	return readProfileImage(header)
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

// [POST] /api/v1/auth/change-password - เปลี่ยนรหัสผ่าน (ต้องมี Access Token)
func (h *UserHandler) ChangePassword(c *gin.Context) {
	var req domain.UserChangePasswordRequest

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลที่ส่งมาไม่ถูกต้อง"})
		return
	}

	// เรียกใช้ตัวสกัด Token คลีนๆ ของเรา
	userToken, ok := extractToken(c)
	if !ok {
		return
	}

	err := h.repo.ChangePassword(c.Request.Context(), userToken, req.NewPassword)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "เปลี่ยนรหัสผ่านไม่สำเร็จ: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":  http.StatusOK,
		"message": "เปลี่ยนรหัสผ่านสำเร็จ",
	})
}

// [POST] /api/v1/auth/send-otp - ส่งรหัส OTP เพื่อรีเซ็ตรหัสผ่าน (กรณีลืมรหัสผ่าน)
func (h *UserHandler) SendOTP(c *gin.Context) {
	var req domain.UserSendOTP
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "รูปแบบอีเมลไม่ถูกต้อง"})
		return
	}

	exists, err := h.repo.IsEmailExists(c.Request.Context(), req.Email)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ระบบตรวจสอบอีเมลขัดข้อง: " + err.Error()})
		return
	}

	// ถ้าไม่เจออีเมลนี้ในระบบ ให้ดีดกลับด้วย 404 Not Found ทันที ไม่ต้องส่ง OTP
	if !exists {
		c.JSON(http.StatusNotFound, gin.H{
			"error": "ไม่พบอีเมลนี้ในระบบสมัครสมาชิก โปรดตรวจสอบความถูกต้อง",
		})
		return
	}

	// ตรวจสอบแล้วส่ง OTP จริง
	err = h.repo.SendOTP(c.Request.Context(), req.Email)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ขอรหัส OTP ไม่สำเร็จ: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":  http.StatusOK,
		"message": "ขอรหัส OTP สำเร็จ โปรดตรวจสอบอีเมลของคุณ",
	})
}

// [POST] /api/v1/auth/verify-otp - ตรวจสอบรหัส OTP
func (h *UserHandler) VerifyResetOTP(c *gin.Context) {
	var req domain.UserVerifyOTPResetRequest

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลไม่ถูกต้อง รหัส OTP ต้องเป็นตัวเลข 6 หลัก"})
		return
	}

	// เรียกใช้เมธอดที่เราพิชิตตัวแปรอินเทอร์เฟซสำเร็จในรอบที่แล้ว
	tokens, err := h.repo.VerifyOTP(c.Request.Context(), req.Email, req.OTPCode)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "การยืนยันรหัส OTP ล้มเหลว หรือรหัสหมดอายุ"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":        http.StatusOK,
		"message":       "ยืนยัน OTP เรียบร้อยแล้ว",
		"access_token":  tokens.AccessToken,
		"refresh_token": tokens.RefreshToken,
	})
}

// [POST] /api/v1/auth/logout - ออกจากระบบ
func (h *UserHandler) Logout(c *gin.Context) {
	// เอา Token ออกไปล็อกเอาต์เหมือนกัน
	userToken, ok := extractToken(c)
	if !ok {
		return
	}

	err := h.repo.Logout(c.Request.Context(), userToken)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ออกจากระบบไม่สำเร็จ: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":  http.StatusOK,
		"message": "ออกจากระบบสำเร็จ",
	})
}

// [GET] /api/v1/user/profile - ดึงข้อมูลโปรไฟล์ของผู้ใช้ที่ล็อกอินอยู่
func (h *UserHandler) GetProfile(c *gin.Context) {
	userID, ok := h.authenticatedUserID(c)
	if !ok {
		return
	}

	profile, err := h.repo.GetProfile(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถโหลดข้อมูลโปรไฟล์ได้: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, profile)
}

// [PUT] /api/v1/user/profile - อัปเดตข้อมูลโปรไฟล์ (ชื่อ, ไบโอ, รูปภาพ)
func (h *UserHandler) UpdateProfile(c *gin.Context) {
	userID, ok := h.authenticatedUserID(c)
	if !ok {
		return
	}

	var req domain.UpdateProfileRequest
	if strings.HasPrefix(strings.ToLower(c.GetHeader("Content-Type")), "multipart/form-data") {
		if err := c.ShouldBind(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลโปรไฟล์ไม่ถูกต้อง: " + err.Error()})
			return
		}
	} else {
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลโปรไฟล์ไม่ถูกต้อง: " + err.Error()})
			return
		}
	}

	profileImage, err := profileImageFromRequest(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	profile, err := h.repo.UpdateProfile(c.Request.Context(), userID, req, profileImage)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถแก้ไขโปรไฟล์ได้: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":  http.StatusOK,
		"message": "บันทึกข้อมูลโปรไฟล์เรียบร้อย",
		"profile": profile,
	})
}

// [PUT] /api/v1/user/contact - อัปเดตเบอร์โทรศัพท์ติดต่อ
func (h *UserHandler) UpdateContact(c *gin.Context) {
	userID, ok := h.authenticatedUserID(c)
	if !ok {
		return
	}

	var req domain.UpdateContactRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "กรุณาระบุเบอร์โทรศัพท์"})
		return
	}

	phone, valid := normalizePhone(req.Phone)
	if !valid {
		c.JSON(http.StatusBadRequest, gin.H{"error": "เบอร์โทรศัพท์ต้องเป็นตัวเลข 10 หลักและขึ้นต้นด้วย 0"})
		return
	}

	if err := h.repo.UpdateContact(c.Request.Context(), userID, phone); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถบันทึกเบอร์โทรศัพท์ได้: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":  http.StatusOK,
		"message": "บันทึกข้อมูลติดต่อเรียบร้อย",
		"phone":   phone,
	})
}

// [POST] /api/v1/user/fcm-token - อัปเดต FCM Push Token
func (h *UserHandler) UpdateFCMToken(c *gin.Context) {
	userID, ok := h.authenticatedUserID(c)
	if !ok {
		return
	}

	var req domain.UpdateFCMTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "กรุณาระบุ fcm_token"})
		return
	}

	if err := h.repo.UpdateFCMToken(c.Request.Context(), userID, req.FCMToken); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถบันทึก FCM Token ได้: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":  http.StatusOK,
		"message": "บันทึก FCM Token เรียบร้อย",
	})
}
