package ports

import (
	"net/http"

	"github.com/Chanachai04/yuemnoi_app/backend/internal/domain"
	"github.com/gin-gonic/gin"
)

func SetupRouter(
	itemRepo domain.ItemRepository,
	authGateway domain.AuthGateway,
	aiService domain.AIService,
) *gin.Engine {

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

	// Health check สำหรับ Docker และระบบเฝ้าระวัง โดยไม่เปิดเผยข้อมูลภายใน
	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	// นำเข้าคอนโทรลเลอร์ต่างๆ
	itemController := NewItemHandler(itemRepo, authGateway)
	rentalController := NewRentalHandler()
	userController := NewUserHandler(authGateway)
	aiHandler := NewAIHandler(aiService)

	// จัดการกลุ่มเส้นทาง API
	v1 := router.Group("/api/v1")
	{
		// ทุกอย่างเกี่ยวกับการยืนยันตัวตน (Authentication)
		user := v1.Group("/auth")
		{
			// POST /api/v1/auth/register
			user.POST("/register", userController.Register)
			// POST /api/v1/auth/login
			user.POST("/login", userController.Login)
			// POST /api/v1/auth/google-profile
			user.POST("/google-profile", userController.SyncGoogleProfileImage)
			// POST /api/v1/auth/change-password
			user.POST("/change-password", userController.ChangePassword)
			// POST /api/v1/auth/send-otp
			user.POST("/send-otp", userController.SendOTP)
			// POST /api/v1/auth/verify-otp
			user.POST("/verify-otp", userController.VerifyResetOTP)
			// POST /api/v1/auth/logout
			user.POST("/logout", userController.Logout)
		}
		// ทุกอย่างเกี่ยวกับ Items ปล่อยเช่า
		items := v1.Group("/items")
		{
			// GET /api/v1/items
			items.GET("", itemController.GetAllItems)
			// POST /api/v1/items
			items.POST("", itemController.CreateItem)
			// GET /api/v1/items/:id
			items.GET("/:id", itemController.GetItemByID)
			// PUT /api/v1/items/:id
			items.PUT("/:id", itemController.UpdateItem)
			// DELETE /api/v1/items/:id
			items.DELETE("/:id", itemController.DeleteItem)
		}

		// ทุกอย่างเกี่ยวกับการจอง (Rentals)
		rentals := v1.Group("/rentals")
		{
			rentals.POST("", rentalController.CreateRentalOrder)

		}

		// ทุกอย่างเกี่ยวกับ AI
		ai := v1.Group("/chat-ai")
		{
			ai.POST("", aiHandler.HandleChat)
		}
	}

	return router
}
