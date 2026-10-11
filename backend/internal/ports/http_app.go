package ports

import (
	"context"
	"errors"
	"time"

	"github.com/go-playground/validator/v10"
	"github.com/gofiber/fiber/v3"
)

type requestValidator struct {
	validate *validator.Validate
}

type requestCancelKey struct{}
type streamShutdownKey struct{}

func (v requestValidator) Validate(value any) error {
	return v.validate.Struct(value)
}

// NewHTTPApp รวมค่าพื้นฐานของ HTTP transport เพื่อให้ server และ tests ใช้สัญญาเดียวกัน
func NewHTTPApp(options ...fiber.Config) *fiber.App {
	cfg := fiber.Config{ReadTimeout: 15 * time.Second, WriteTimeout: 90 * time.Second}
	if len(options) > 0 {
		cfg = options[0]
	}
	validate := validator.New()
	cfg.StructValidator = requestValidator{validate: validate}
	cfg.Immutable = true
	cfg.CaseSensitive = true
	cfg.DisableHeadAutoRegister = true
	// ให้ handler จัดการ multipart ที่เสียรูปเป็น 400 หลังผ่าน middleware ตามปกติ
	cfg.DisablePreParseMultipartForm = true
	cfg.ProxyHeader = fiber.HeaderXForwardedFor
	cfg.EnableIPValidation = true
	// คงการอ่าน client IP หลัง reverse proxy ตาม transport เดิม
	if !cfg.TrustProxy {
		cfg.TrustProxy = true
		cfg.TrustProxyConfig = fiber.TrustProxyConfig{Proxies: []string{"0.0.0.0/0", "::/0"}}
	}
	// รองรับรูปสินค้า 5 รูป รูปละ 5 MiB รวมส่วนหัวและช่องข้อมูล multipart
	cfg.BodyLimit = 32 << 20
	cfg.ErrorHandler = func(c fiber.Ctx, err error) error {
		var httpErr *fiber.Error
		if errors.As(err, &httpErr) && (httpErr.Code == fiber.StatusNotFound || httpErr.Code == fiber.StatusMethodNotAllowed) {
			c.Response().Header.Del("Allow")
			return c.Status(fiber.StatusNotFound).SendString("404 page not found")
		}
		if errors.As(err, &httpErr) && httpErr.Code < fiber.StatusInternalServerError {
			return c.Status(httpErr.Code).SendString(httpErr.Message)
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{"error": "ระบบขัดข้องชั่วคราว"})
	}
	app := fiber.New(cfg)
	streamShutdown, cancelStreams := context.WithCancel(context.Background())
	app.Hooks().OnPreShutdown(func() error {
		cancelStreams()
		return nil
	})
	// ยกเลิกงานของ request ปกติเมื่อ handler จบ ส่วนสตรีมเป็นเจ้าของ lifecycle ของตนเอง
	app.Use(func(c fiber.Ctx) error {
		ctx, cancel := context.WithCancel(c.Context())
		ctx = context.WithValue(ctx, requestCancelKey{}, cancel)
		c.SetContext(context.WithValue(ctx, streamShutdownKey{}, streamShutdown))
		err := c.Next()
		if !c.Response().IsBodyStream() {
			cancel()
		}
		return err
	})
	return app
}
