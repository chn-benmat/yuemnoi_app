package ports

import (
	"crypto/subtle"
	"net/http"
	"strings"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gin-gonic/gin"
)

func SetupRouter(
	itemRepo domain.ItemRepository,
	authGateway domain.AuthGateway,
	contactRepository domain.ConversationContactRepository,
	rentalRepository domain.RentalRepository,
	pushSender domain.PushNotificationSender,
	aiGateway domain.AIChatbotGateway,
	appSecretKey string,
) *gin.Engine {

	// ใช้ Logger และ Recovery Middleware (ป้องกันเซิร์ฟเวอร์พังเวลาเกิด Panic โค้ดเอ๋อ)
	router := gin.New()
	router.Use(gin.Logger())
	router.Use(gin.Recovery())
	router.Use(blockScannerPaths())

	// ตั้งค่า CORS แบบปลอดภัย ไม่อนุญาตให้สะท้อน Arbitrary Origin ควบคู่กับ Credentials
	router.Use(func(c *gin.Context) {
		origin := c.Request.Header.Get("Origin")
		isAllowed := false
		if origin != "" {
			// ตรวจสอบ Whitelist สำหรับ Origin ที่อนุญาต
			if strings.HasPrefix(origin, "http://localhost") ||
				strings.HasPrefix(origin, "http://127.0.0.1") ||
				strings.HasSuffix(origin, ".ts.net") ||
				strings.HasSuffix(origin, "yuemnoi.com") {
				isAllowed = true
			}
		}

		if isAllowed {
			c.Writer.Header().Set("Access-Control-Allow-Origin", origin)
			c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		} else if origin == "" {
			// สำหรับ Mobile Native App ที่ไม่ได้ส่ง Origin Header มา
			c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		}

		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, GET, OPTIONS, PUT, DELETE, PATCH")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Origin, Content-Type, Accept, Authorization, X-Requested-With, X-App-Secret")

		// ถ้าระบบส่ง OPTIONS มาถามทาง ให้ตอบกลับ 204 แล้วจบงานตรงนี้เลย
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	})
	router.Use(verifyAppSecret(appSecretKey))

	// Health check สำหรับ Docker และระบบเฝ้าระวัง โดยไม่เปิดเผยข้อมูลภายใน
	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	// ติดตั้ง Rate Limiters เพื่อป้องกัน Brute-Force และ DoS
	authRateLimiter := NewRateLimiter(5.0/60.0, 5.0)  // 5 ครั้งต่อนาทีสำหรับ Auth
	aiRateLimiter := NewRateLimiter(15.0/60.0, 15.0) // 15 ครั้งต่อนาทีสำหรับ AI

	// นำเข้าคอนโทรลเลอร์ต่างๆ
	itemController := NewItemHandler(itemRepo, authGateway)
	rentalController := NewRentalHandler(rentalRepository, authGateway)
	userController := NewUserHandler(authGateway)
	pushController := NewPushHandler(pushSender, authGateway)
	chatContactController := NewChatContactHandler(contactRepository, authGateway)
	chatbotController := NewChatbotHandler(aiGateway, authGateway)

	// จัดการกลุ่มเส้นทาง API
	api := router.Group("/api")
	{
		// ทุกอย่างเกี่ยวกับการยืนยันตัวตน (Authentication) - มี Rate Limit ป้องกัน Brute-force
		user := api.Group("/auth")
		user.Use(RateLimitMiddleware(authRateLimiter, "คุณส่งคำขอยืนยันตัวตนบ่อยเกินไป กรุณารอสักครู่แล้วลองใหม่"))
		{
			// POST /api/auth/register
			user.POST("/register", userController.Register)
			// POST /api/auth/login
			user.POST("/login", userController.Login)
			// POST /api/auth/google-profile
			user.POST("/google-profile", userController.SyncGoogleProfileImage)
			// POST /api/auth/change-password
			user.POST("/change-password", userController.ChangePassword)
			// POST /api/auth/send-otp
			user.POST("/send-otp", userController.SendOTP)
			// POST /api/auth/verify-otp
			user.POST("/verify-otp", userController.VerifyResetOTP)
		}

		// จัดการโปรไฟล์และข้อมูลผู้ใช้ (User Profile & Settings)
		profile := api.Group("/user")
		{
			// GET /api/user/profile
			profile.GET("/profile", userController.GetProfile)
			// PUT /api/user/profile
			profile.PUT("/profile", userController.UpdateProfile)
			// PUT /api/user/contact
			profile.PUT("/contact", userController.UpdateContact)
			// POST /api/user/fcm-token
			profile.POST("/fcm-token", userController.UpdateFCMToken)
		}
		// ทุกอย่างเกี่ยวกับ Items ปล่อยเช่า
		items := api.Group("/items")
		{
			// GET /api/items
			items.GET("", itemController.GetAllItems)
			// POST /api/items
			items.POST("", itemController.CreateItem)
			// GET /api/items/:id
			items.GET("/:id", itemController.GetItemByID)
			// PUT /api/items/:id
			items.PUT("/:id", itemController.UpdateItem)
			// DELETE /api/items/:id
			items.DELETE("/:id", itemController.DeleteItem)
		}

		// ทุกอย่างเกี่ยวกับการจอง (Rentals)
		rentals := api.Group("/rentals")
		{
			rentals.POST("", rentalController.CreateRentalOrder)
			rentals.POST("/:id/handover", rentalController.HandoverRental)
			rentals.POST("/:id/return", rentalController.ReturnRental)
		}

		// Push Notification - ป้องกันด้วย Authentication ภายใน Handler
		push := api.Group("/push")
		{
			push.POST("/chat", pushController.SendChatPush)
		}

		chat := api.Group("/chat")
		{
			// POST /api/chat/contact
			chat.POST("/contact", chatContactController.GetConversationContact)
		}

		// ระบบแชทสนทนากับ AI Chatbot (Stateless AI Gateway) - มี Rate Limit ป้องกัน GPU DoS
		chatAI := api.Group("/chat-ai")
		chatAI.Use(RateLimitMiddleware(aiRateLimiter, "คำขอสนทนากับ AI ถี่เกินไป กรุณารอสักครู่แล้วลองใหม่"))
		{
			// POST /api/chat-ai (Non-Streaming)
			chatAI.POST("", chatbotController.SendMessage)
			// POST /api/chat-ai/stream (SSE Streaming)
			chatAI.POST("/stream", chatbotController.SendMessageStream)
		}
	}

	return router
}

func blockScannerPaths() gin.HandlerFunc {
	return func(c *gin.Context) {
		path := strings.ToLower(c.Request.URL.Path)
		if strings.Contains(path, ".env") ||
			strings.Contains(path, ".git") ||
			strings.Contains(path, ".php") {
			c.AbortWithStatus(http.StatusNotFound)
			return
		}

		c.Next()
	}
}

func verifyAppSecret(expectedSecret string) gin.HandlerFunc {
	// แยกคีย์ที่รองรับ (รองรับทั้งแบบเดี่ยวและแบบ Comma-separated สำหรับการหมุนเวียนกุญแจแบบไร้สะดุด)
	var validKeys []string
	for _, k := range strings.Split(expectedSecret, ",") {
		trimmed := strings.TrimSpace(k)
		if trimmed != "" {
			validKeys = append(validKeys, trimmed)
		}
	}

	return func(c *gin.Context) {
		if len(validKeys) == 0 || c.Request.Method == http.MethodOptions || c.Request.URL.Path == "/health" {
			c.Next()
			return
		}

		providedSecret := c.GetHeader("X-App-Secret")
		if providedSecret == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
			return
		}

		matched := false
		for _, expected := range validKeys {
			if subtle.ConstantTimeCompare([]byte(providedSecret), []byte(expected)) == 1 {
				matched = true
				break
			}
		}

		if !matched {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
			return
		}

		c.Next()
	}
}
