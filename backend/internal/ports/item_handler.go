// internal/ports/item_handler.go
package ports

import (
	"github.com/Chanachai04/yuemnoi_app/backend/internal/domain"
	"github.com/gin-gonic/gin"
	"net/http"
)

type ItemHandler struct {
	repo domain.ItemRepository
}

func NewItemHandler(r domain.ItemRepository) *ItemHandler {
	return &ItemHandler{
		repo: r,
	}
}

// [GET] /api/v1/items - ดึงข้อมูลอุปกรณ์เช่าทั้งหมด
func (h *ItemHandler) GetAllItems(c *gin.Context) {
	items, err := h.repo.FindAll(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, items)
}
