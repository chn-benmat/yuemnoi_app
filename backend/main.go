package main

import (
	"context"
	"encoding/base64"
	"log"
	"log/slog"
	"net"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/aiservice"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/emaildns"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/fcm"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/geocoding"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/logging"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/config"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	"github.com/gofiber/fiber/v3"
	"github.com/mattn/go-colorable"
	"github.com/mattn/go-isatty"
)

func main() {
	// โหลดคอนฟิกูเรชันกลางของระบบ
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	// ใช้ JSON ในโหมด release และใส่สีให้ข้อความในโหมด debug เมื่อแสดงใน terminal
	var logHandler slog.Handler
	if cfg.Mode == "release" {
		logHandler = slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo})
	} else {
		useColor := isatty.IsTerminal(os.Stdout.Fd()) || isatty.IsCygwinTerminal(os.Stdout.Fd())
		logHandler = logging.NewTextHandler(colorable.NewColorableStdout(), &slog.HandlerOptions{Level: slog.LevelDebug}, useColor)
	}
	slog.SetDefault(slog.New(logHandler))

	// สร้าง Supabase Client และ Repositories
	supabaseClient := supabase.InitSupabaseClient(cfg.SupabaseURL, cfg.SupabaseServiceRoleKey)
	itemRepo := supabase.NewSupabaseItemRepository(supabaseClient, cfg.SupabaseServiceRoleKey)
	emailChecker := emaildns.NewChecker(&net.Resolver{PreferGo: true, StrictErrors: true})
	authGateway := domain.WithRegistrationEmailCheck(
		supabase.NewSupabaseUserRepository(supabaseClient, cfg.SupabaseServiceRoleKey), emailChecker,
	)
	contactRepository := supabase.NewSupabaseConversationContactRepository(supabaseClient)
	identityEncryption, identityKeyErr := base64.StdEncoding.DecodeString(cfg.IdentityEncryptionKey)
	if identityKeyErr != nil || len(identityEncryption) != 32 {
		if cfg.OperationsEnabled {
			log.Fatal("IDENTITY_ENCRYPTION_KEY must be base64 of 32 random bytes")
		}
		identityEncryption = nil
	}
	rentalRepository := supabase.NewSupabaseRentalRepository(supabaseClient, supabase.RentalRepositoryKeys{
		ServiceRole: cfg.SupabaseServiceRoleKey, PromptPayEncryption: identityEncryption,
	})
	// สร้าง AI Chatbot Gateway Adapter พร้อม Primary Internal Service Secret Key
	aiGateway := aiservice.NewClient(cfg.AIServiceURL, cfg.GetPrimaryInternalServiceKey(), cfg.AIServiceTimeout)

	// รวม APP_SECRET_KEY และ APP_SECRET_KEYS ทั้งหมดคั่นด้วย Comma สำหรับ Router (รองรับ Multi-Key Rotation)
	allAppSecretKeys := strings.Join(cfg.GetAppSecretKeys(), ",")

	// ตั้งค่า Router และฉีด Dependencies ทั้งหมดผ่าน DI
	var ops domain.OperationsOptions
	if cfg.OperationsEnabled {
		hmacKey, decodeErr := base64.StdEncoding.DecodeString(cfg.IdentityHMACKey)
		if decodeErr != nil || len(hmacKey) < 32 {
			log.Fatal("IDENTITY_HMAC_KEY must be base64 of at least 32 random bytes")
		}
		ops = domain.OperationsOptions{Store: supabase.NewOperationsRepository(cfg.SupabaseURL, cfg.SupabaseServiceRoleKey), EncryptionKey: identityEncryption, HMACKey: hmacKey, CleanupInterval: cfg.IdentityCleanupInterval}
	}
	ops.AccountDeletion = supabase.NewAccountDeletionRepository(supabaseClient, cfg.SupabaseServiceRoleKey)
	cleanupCtx, stopCleanup := context.WithCancel(context.Background())
	defer stopCleanup()
	notifications := supabase.NewSupabaseNotificationRepository(supabaseClient)
	ops.Notifications = notifications
	var deviceSender domain.DevicePushSender
	if sender, err := fcm.NewFCMSender(cfg.FirebaseSAPath, cfg.FirebaseSAJSON, nil); err != nil {
		slog.Warn("ไม่ได้เปิดใช้งานการส่ง Firebase", slog.String("reason", "firebase_configuration_unavailable"))
	} else {
		deviceSender = sender
	}
	var notificationWakeups chan struct{}
	if deviceSender != nil {
		listener, err := supabase.NewNotificationRealtimeListener(cfg.SupabaseURL, cfg.SupabaseServiceRoleKey)
		if err != nil {
			slog.Warn("ตั้งค่า WebSocket สำหรับแจ้งเตือนไม่สำเร็จ", slog.Any("error", err))
		} else {
			notificationWakeups = make(chan struct{}, 1)
			go listener.Run(cleanupCtx, notificationWakeups)
		}
	}
	go domain.NewNotificationWorker(notifications, deviceSender).Run(cleanupCtx, notificationWakeups)
	go func() {
		ticker := time.NewTicker(time.Minute)
		defer ticker.Stop()
		for {
			ctx, cancel := context.WithTimeout(cleanupCtx, 2*time.Minute)
			err := domain.ProcessAccountDeletions(ctx, ops.AccountDeletion)
			cancel()
			if err != nil && cleanupCtx.Err() == nil {
				slog.Warn("Account deletion incomplete; retry scheduled")
			}
			select {
			case <-cleanupCtx.Done():
				return
			case <-ticker.C:
			}
		}
	}()
	if ops.Store != nil {
		go func() {
			ticker := time.NewTicker(ops.CleanupInterval)
			defer ticker.Stop()
			for {
				ctx, cancel := context.WithTimeout(cleanupCtx, 2*time.Minute)
				err := ports.CleanupIdentity(ctx, ops.Store)
				cancel()
				if err != nil && cleanupCtx.Err() == nil {
					slog.Warn("Identity cleanup incomplete; retry scheduled")
				}
				select {
				case <-cleanupCtx.Done():
					return
				case <-ticker.C:
				}
			}
		}()
	}
	router := ports.SetupRouterWithOperations(ops,
		itemRepo,
		authGateway,
		contactRepository,
		rentalRepository,
		aiGateway,
		allAppSecretKeys,
		fiber.Config{ReadTimeout: cfg.ReadTimeout, WriteTimeout: cfg.WriteTimeout},
	)

	ports.RegisterHomeFeedRoutes(router, supabase.NewSupabaseHomeFeedRepository(supabaseClient), authGateway)
	ports.RegisterLocationRoutes(router, geocoding.NewClient(cfg.GeocodingURL, nil), geocoding.NewPhotonClient(cfg.PlaceSuggestionsURL, nil))
	// รัน Server แบบ Background (Non-blocking)
	go func() {
		slog.Info("Server is starting...", slog.String("port", cfg.Port), slog.String("mode", cfg.Mode))
		if err := router.Listen(":"+cfg.Port, fiber.ListenConfig{DisableStartupMessage: true}); err != nil {
			slog.Error("Server listen error", slog.Any("error", err))
			os.Exit(1)
		}
	}()

	// รอรับ Signal สำหรับการทำ Graceful Shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	slog.Info("Shutting down server...")

	// เคลียร์ Request ที่ค้างอยู่ให้จบภายในระยะเวลา ShutdownTimeout
	ctx, cancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
	defer cancel()
	if err := router.ShutdownWithContext(ctx); err != nil {
		slog.Error("Server forced to shutdown", slog.Any("error", err))
		os.Exit(1)
	}

	slog.Info("Server gracefully stopped")
}
