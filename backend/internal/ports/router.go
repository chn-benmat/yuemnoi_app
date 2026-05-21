package ports

import (
	"net/http"

	"github.com/Chanachai04/yuemnoi_app/backend/internal/adapters/supabase"
	"github.com/gin-gonic/gin"
	supa "github.com/nedpals/supabase-go"
)

func SetupRouter(sbClient *supa.Client, aiHandler *AIHandler) *gin.Engine {

	// ใช้ Logger และ Recovery Middleware (ป้องกันเซิร์ฟเวอร์พังเวลาเกิด Panic โค้ดเอ๋อ)
	router := gin.New()
	router.Use(gin.Logger())
	router.Use(gin.Recovery())

	// ตั้งค่า CORS  เพื่อให้ Flutter ยิงเข้ามาหาได้ไม่ติดบล็อก
	router.Use(func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, GET, OPTIONS, PUT, DELETE")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Origin, Content-Type, Accept, Authorization")

		// ถ้าระบบส่ง OPTIONS มาถามทาง ให้ตอบกลับ 204 แล้วจบงานตรงนี้เลย
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()

	})

	itemRepo := supabase.NewSupabaseItemRepository(sbClient)
	// นำเข้าคอนโทรลเลอร์ต่างๆ
	itemController := NewItemHandler(itemRepo)
	rentalController := NewRentalHandler()

	// จัดการกลุ่มเส้นทาง API
	v1 := router.Group("/api/v1")
	{
		// ทุกอย่างเกี่ยวกับ Items ปล่อยเช่า
		items := v1.Group("/items")
		{
			items.GET("", itemController.GetAllItems) // GET /api/v1/items
		}

		// ทุกอย่างเกี่ยวกับการจอง (Rentals)
		rentals := v1.Group("/rentals")
		{
			rentals.POST("", rentalController.CreateRentalOrder)
		}

		// ทุกอย่างเกี่ยวกับ AI
		v1.POST("/chat-ai", aiHandler.HandleChat)
	}

	return router
}
