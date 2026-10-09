package ports

import (
	"crypto/subtle"
	"net/http"
	"net/url"
	"strings"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/gofiber/fiber/v3"
	"github.com/gofiber/fiber/v3/middleware/recover"
)

func SetupRouter(
	itemRepo domain.ItemRepository,
	authGateway domain.AuthGateway,
	contactRepository domain.ConversationContactRepository,
	rentalRepository domain.RentalRepository,
	pushSender domain.PushNotificationSender,
	aiGateway domain.AIChatbotGateway,
	appSecretKey string,
	options ...fiber.Config,
) *fiber.App {

	// ใช้ Logger และ Recovery Middleware (ป้องกันเซิร์ฟเวอร์พังเวลาเกิด Panic โค้ดเอ๋อ)
	router := NewHTTPApp(options...)
	router.Use(accessLoggingMiddleware())
	router.Use(recover.New())
	router.Use(redirectTrailingSlash())
	router.Use(blockScannerPaths())

	// ตั้งค่า CORS แบบปลอดภัย ไม่อนุญาตให้สะท้อน Arbitrary Origin ควบคู่กับ Credentials
	router.Use(func(c fiber.Ctx) error {
		origin := c.Get("Origin")
		isAllowed := isAllowedOrigin(origin)

		if isAllowed {
			c.Set("Access-Control-Allow-Origin", origin)
			c.Set("Access-Control-Allow-Credentials", "true")
		} else if origin == "" {
			// สำหรับ Mobile Native App ที่ไม่ได้ส่ง Origin Header มา
			c.Set("Access-Control-Allow-Origin", "*")
		}

		c.Set("Access-Control-Allow-Methods", "POST, GET, OPTIONS, PUT, DELETE, PATCH")
		c.Set("Access-Control-Allow-Headers", "Origin, Content-Type, Accept, Authorization, X-Requested-With, X-App-Secret")

		// ถ้าระบบส่ง OPTIONS มาถามทาง ให้ตอบกลับ 204 แล้วจบงานตรงนี้เลย
		if c.Method() == "OPTIONS" {
			return c.SendStatus(http.StatusNoContent)
		}
		return c.Next()
	})
	router.Use(verifyAppSecret(appSecretKey))

	// Health check สำหรับ Docker และระบบเฝ้าระวัง โดยไม่เปิดเผยข้อมูลภายใน
	router.Get("/health", func(c fiber.Ctx) error {
		return c.JSON(fiber.Map{"status": "ok"})
	})

	// ติดตั้ง Rate Limiters เพื่อป้องกัน Brute-Force และ DoS
	authRateLimiter := NewRateLimiter(5.0/60.0, 5.0) // 5 ครั้งต่อนาทีสำหรับ Auth
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
		authRateLimit := RateLimitMiddleware(authRateLimiter, "คุณส่งคำขอยืนยันตัวตนบ่อยเกินไป กรุณารอสักครู่แล้วลองใหม่")
		{
			// POST /api/auth/register
			user.Post("/register", authRateLimit, userController.Register)
			// POST /api/auth/login
			user.Post("/login", authRateLimit, userController.Login)
			// POST /api/auth/google-profile
			user.Post("/google-profile", authRateLimit, userController.SyncGoogleProfileImage)
			// POST /api/auth/change-password
			user.Post("/change-password", authRateLimit, userController.ChangePassword)
			// POST /api/auth/send-otp
			user.Post("/send-otp", authRateLimit, userController.SendOTP)
			// POST /api/auth/verify-otp
			user.Post("/verify-otp", authRateLimit, userController.VerifyResetOTP)
		}

		// จัดการโปรไฟล์และข้อมูลผู้ใช้ (User Profile & Settings)
		profile := api.Group("/user")
		{
			// GET /api/user/profile
			profile.Get("/profile", userController.GetProfile)
			// PUT /api/user/profile
			profile.Put("/profile", userController.UpdateProfile)
			// PUT /api/user/contact
			profile.Put("/contact", userController.UpdateContact)
			// POST /api/user/fcm-token
			profile.Post("/fcm-token", userController.UpdateFCMToken)
		}
		// ทุกอย่างเกี่ยวกับ Items ปล่อยเช่า
		items := api.Group("/items")
		{
			// GET /api/items
			items.Get("", itemController.GetAllItems)
			// POST /api/items
			items.Post("", itemController.CreateItem)
			// GET /api/items/:id
			items.Get("/:id", itemController.GetItemByID)
			// PUT /api/items/:id
			items.Put("/:id", itemController.UpdateItem)
			// DELETE /api/items/:id
			items.Delete("/:id", itemController.DeleteItem)
		}

		// ทุกอย่างเกี่ยวกับการจอง (Rentals)
		rentals := api.Group("/rentals")
		{
			rentals.Post("", rentalController.CreateRentalOrder)
			rentals.Post("/:id/handover", rentalController.HandoverRental)
			rentals.Post("/:id/return", rentalController.ReturnRental)
		}

		// Push Notification - ป้องกันด้วย Authentication ภายใน Handler
		push := api.Group("/push")
		{
			push.Post("/chat", pushController.SendChatPush)
		}

		chat := api.Group("/chat")
		{
			// POST /api/chat/contact
			chat.Post("/contact", chatContactController.GetConversationContact)
		}

		// ระบบแชทสนทนากับ AI Chatbot (Stateless AI Gateway) - มี Rate Limit ป้องกัน GPU DoS
		chatAI := api.Group("/chat-ai")
		aiRateLimit := RateLimitMiddleware(aiRateLimiter, "คำขอสนทนากับ AI ถี่เกินไป กรุณารอสักครู่แล้วลองใหม่")
		{
			// POST /api/chat-ai (Non-Streaming)
			chatAI.Post("", aiRateLimit, chatbotController.SendMessage)
			// POST /api/chat-ai/stream (SSE Streaming)
			chatAI.Post("/stream", aiRateLimit, chatbotController.SendMessageStream)
		}
	}

	return router
}

// ตรวจ hostname จริง เพื่อไม่ให้โดเมนที่เลียนแบบชื่อหรือใส่ชื่อไว้ใน path ผ่าน CORS
func isAllowedOrigin(origin string) bool {
	parsed, err := url.Parse(origin)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") ||
		parsed.User != nil || parsed.Path != "" || parsed.RawQuery != "" || parsed.Fragment != "" {
		return false
	}
	host := strings.ToLower(parsed.Hostname())
	return host == "localhost" || host == "127.0.0.1" ||
		host == "yuemnoi.com" || strings.HasSuffix(host, ".yuemnoi.com") || strings.HasSuffix(host, ".ts.net")
}

func blockScannerPaths() fiber.Handler {
	return func(c fiber.Ctx) error {
		path := strings.ToLower(c.Path())
		if strings.Contains(path, ".env") ||
			strings.Contains(path, ".git") ||
			strings.Contains(path, ".php") {
			c.Status(http.StatusNotFound)
			return nil
		}

		return c.Next()
	}
}

// คง HTTP redirect ของเส้นทางเดิม เมื่อ client เติม slash หลัง endpoint ที่มีอยู่จริง
func redirectTrailingSlash() fiber.Handler {
	return func(c fiber.Ctx) error {
		path := c.Path()
		if path == "/" || !strings.HasSuffix(path, "/") {
			return c.Next()
		}
		target := strings.TrimSuffix(path, "/")
		for _, route := range c.App().GetRoutes(true) {
			if route.Method != c.Method() {
				continue
			}
			pattern, segments := strings.Split(route.Path, "/"), strings.Split(target, "/")
			if len(pattern) != len(segments) {
				continue
			}
			matched := true
			for i, segment := range pattern {
				if strings.HasPrefix(segment, ":") && segments[i] != "" {
					continue
				}
				if segment != segments[i] {
					matched = false
					break
				}
			}
			if matched {
				if query := string(c.Request().URI().QueryString()); query != "" {
					target += "?" + query
				}
				status := http.StatusTemporaryRedirect
				if c.Method() == http.MethodGet {
					status = http.StatusMovedPermanently
				}
				return c.Redirect().Status(status).To(target)
			}
		}
		return c.Next()
	}
}

func verifyAppSecret(expectedSecret string) fiber.Handler {
	// แยกคีย์ที่รองรับ (รองรับทั้งแบบเดี่ยวและแบบ Comma-separated สำหรับการหมุนเวียนกุญแจแบบไร้สะดุด)
	var validKeys []string
	for _, k := range strings.Split(expectedSecret, ",") {
		trimmed := strings.TrimSpace(k)
		if trimmed != "" {
			validKeys = append(validKeys, trimmed)
		}
	}

	return func(c fiber.Ctx) error {
		if len(validKeys) == 0 || c.Method() == http.MethodOptions || c.Path() == "/health" {
			return c.Next()
		}

		providedSecret := c.Get("X-App-Secret")
		if providedSecret == "" {
			return c.Status(http.StatusUnauthorized).JSON(fiber.Map{"error": "unauthorized"})
		}

		matched := false
		for _, expected := range validKeys {
			if subtle.ConstantTimeCompare([]byte(providedSecret), []byte(expected)) == 1 {
				matched = true
				break
			}
		}

		if !matched {
			return c.Status(http.StatusUnauthorized).JSON(fiber.Map{"error": "unauthorized"})
		}

		return c.Next()
	}
}
