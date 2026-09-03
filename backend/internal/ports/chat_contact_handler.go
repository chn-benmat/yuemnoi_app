package ports

import (
	"errors"
	"log"
	"net/http"
	"strings"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gin-gonic/gin"
)

type ChatContactHandler struct {
	repository    domain.ConversationContactRepository
	tokenVerifier domain.TokenVerifier
}

type chatContactRequest struct {
	ConversationID string `json:"conversation_id" binding:"required"`
}

func NewChatContactHandler(
	repository domain.ConversationContactRepository,
	tokenVerifier domain.TokenVerifier,
) *ChatContactHandler {
	return &ChatContactHandler{
		repository:    repository,
		tokenVerifier: tokenVerifier,
	}
}

// GetConversationContact คืนเบอร์ของคู่สนทนาเฉพาะผู้ที่อยู่ในห้องแชทเท่านั้น
func (h *ChatContactHandler) GetConversationContact(c *gin.Context) {
	token, ok := extractToken(c)
	if !ok {
		return
	}

	requesterID, err := h.tokenVerifier.UserIDFromToken(c.Request.Context(), token)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Access Token ไม่ถูกต้องหรือหมดอายุ"})
		return
	}

	var request chatContactRequest
	if err := c.ShouldBindJSON(&request); err != nil || strings.TrimSpace(request.ConversationID) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "กรุณาระบุห้องสนทนา"})
		return
	}

	phone, err := h.repository.PhoneForConversation(
		c.Request.Context(),
		requesterID,
		strings.TrimSpace(request.ConversationID),
	)
	if err != nil {
		switch {
		case errors.Is(err, domain.ErrConversationNotFound):
			c.JSON(http.StatusNotFound, gin.H{"error": "ไม่พบห้องสนทนา"})
		case errors.Is(err, domain.ErrContactForbidden):
			c.JSON(http.StatusForbidden, gin.H{"error": "คุณไม่มีสิทธิ์ดูข้อมูลติดต่อของห้องนี้"})
		case errors.Is(err, domain.ErrContactPhoneNotFound):
			c.JSON(http.StatusNotFound, gin.H{"error": "ผู้ใช้นี้ยังไม่ได้เพิ่มเบอร์โทรศัพท์"})
		default:
			log.Printf("load conversation contact failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "ไม่สามารถโหลดข้อมูลติดต่อได้"})
		}
		return
	}

	c.JSON(http.StatusOK, gin.H{"phone": phone})
}
