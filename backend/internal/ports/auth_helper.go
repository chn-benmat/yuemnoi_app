package ports

import (
	"net/http"
	"strings"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gin-gonic/gin"
)

// extractToken สกัดเอา JWT Token ออกจาก Authorization Header (Bearer <token>)
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

// authenticatedUserID ดึงและตรวจสอบความถูกต้องของ Token พร้อมคืน User ID ของผู้ใช้
func authenticatedUserID(c *gin.Context, verifier domain.TokenVerifier) (string, bool) {
	token, ok := extractToken(c)
	if !ok {
		return "", false
	}

	if verifier == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ระบบตรวจสอบสิทธิ์ไม่พร้อมใช้งาน"})
		return "", false
	}

	userID, err := verifier.UserIDFromToken(c.Request.Context(), token)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Access Token ไม่ถูกต้องหรือหมดอายุ"})
		return "", false
	}

	return userID, true
}
