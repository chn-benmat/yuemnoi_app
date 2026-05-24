package ports

import (
	"net/http"
	"strings"

	"github.com/Chanachai04/yuemnoi_app/backend/internal/domain"
	"github.com/gin-gonic/gin"
)

type UserHandler struct {
	repo domain.AuthRepository
}

type UserLoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=6"`
}

type UserRegisterRequest struct {
	Email           string `json:"email" binding:"required,email"`
	Password        string `json:"password" binding:"required,min=6"`
	ConfirmPassword string `json:"confirm_password" binding:"required,min=6"`
}

type UserChangePasswordRequest struct {
	NewPassword string `json:"new_password" binding:"required,min=6"`
}

type UserRequestResetOTP struct {
	Email string `json:"email" binding:"required,email"`
}

type UserVerifyOTPResetRequest struct {
	Email       string `json:"email" binding:"required,email"`
	OTPCode     string `json:"otp_code" binding:"required,len=8"`
	NewPassword string `json:"new_password" binding:"required,min=6"`
}

func NewUserHandler(r domain.AuthRepository) *UserHandler {
	return &UserHandler{
		repo: r,
	}
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
	var req UserLoginRequest

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลที่ส่งมาไม่ถูกต้อง หรือรูปแบบอีเมลไม่สอดคล้อง"})
		return
	}

	token, err := h.repo.Login(c.Request.Context(), req.Email, req.Password)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "อีเมลหรือรหัสผ่านไม่ถูกต้อง"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":       http.StatusOK,
		"message":      "เข้าสู่ระบบสำเร็จ",
		"access_token": token,
	})
}

// [POST] /api/v1/auth/register - สมัครสมาชิกผู้ใช้ใหม่
func (h *UserHandler) Register(c *gin.Context) {
	var req UserRegisterRequest

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลไม่ถูกต้อง หรือรูปแบบอีเมลไม่สอดคล้อง"})
		return
	}

	if req.Password != req.ConfirmPassword {
		c.JSON(http.StatusBadRequest, gin.H{"error": "รหัสผ่านและยืนยันรหัสผ่านไม่ตรงกัน"})
		return
	}

	userID, err := h.repo.Register(c.Request.Context(), req.Email, req.Password)
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
		"status":  http.StatusCreated,
		"message": "สมัครสมาชิกสำเร็จ",
		"user_id": userID,
	})
}

// [POST] /api/v1/auth/change-password - เปลี่ยนรหัสผ่าน (ต้องมี Access Token)
func (h *UserHandler) ChangePassword(c *gin.Context) {
	var req UserChangePasswordRequest

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

// [POST] /api/v1/auth/request-reset-otp - ขอรหัส OTP เพื่อรีเซ็ตรหัสผ่าน (กรณีลืมรหัสผ่าน)
func (h *UserHandler) RequestResetOTP(c *gin.Context) {
	var req UserRequestResetOTP
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
	err = h.repo.RequestResetOTP(c.Request.Context(), req.Email)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ขอรหัส OTP ไม่สำเร็จ: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":  http.StatusOK,
		"message": "ขอรหัส OTP สำเร็จ โปรดตรวจสอบอีเมลของคุณ",
	})
}

// [POST] /api/v1/auth/verify-reset-otp - ตรวจสอบรหัส OTP
func (h *UserHandler) VerifyResetOTP(c *gin.Context) {
	var req UserVerifyOTPResetRequest

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "ข้อมูลไม่ถูกต้อง รหัส OTP ต้องมีความยาว 6 หลัก"})
		return
	}

	// เรียกใช้เมธอดที่เราพิชิตตัวแปรอินเทอร์เฟซสำเร็จในรอบที่แล้ว
	err := h.repo.VerifyOTP(c.Request.Context(), req.Email, req.OTPCode, req.NewPassword)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "การยืนยันรหัส OTP ล้มเหลว หรือรหัสหมดอายุ: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":  http.StatusOK,
		"message": "ยืนยัน OTP และเปลี่ยนรหัสผ่านใหม่สำเร็จแล้ว",
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
