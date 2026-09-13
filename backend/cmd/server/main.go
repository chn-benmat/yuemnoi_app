package main

import (
	"context"
	"log"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/aiservice"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/fcm"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/config"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	"github.com/gin-gonic/gin"
)

func main() {
	// โหลดคอนฟิกูเรชันกลางของระบบ
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	// ตั้งค่า Structured Logger (slog): JSON ใน Release mode, Text ใน Debug mode
	var logHandler slog.Handler
	if cfg.GinMode == "release" {
		gin.SetMode(gin.ReleaseMode)
		logHandler = slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo})
	} else {
		gin.SetMode(gin.DebugMode)
		logHandler = slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelDebug})
	}
	slog.SetDefault(slog.New(logHandler))

	// สร้าง Supabase Client และ Repositories
	supabaseClient := supabase.InitSupabaseClient(cfg.SupabaseURL, cfg.SupabaseServiceRoleKey)
	itemRepo := supabase.NewSupabaseItemRepository(supabaseClient)
	authGateway := supabase.NewSupabaseUserRepository(supabaseClient, cfg.SupabaseServiceRoleKey)
	contactRepository := supabase.NewSupabaseConversationContactRepository(supabaseClient)
	rentalRepository := supabase.NewSupabaseRentalRepository(supabaseClient)

	// สร้าง FCM Notification Adapter
	fcmSender, err := fcm.NewFCMSender(authGateway, cfg.FirebaseSAPath, cfg.FirebaseSAJSON, nil)
	if err != nil {
		slog.Warn("Failed to initialize FCM sender", slog.Any("error", err))
	}

	// สร้าง AI Chatbot Gateway Adapter พร้อม Primary Internal Service Secret Key
	aiGateway := aiservice.NewClient(cfg.AIServiceURL, cfg.GetPrimaryInternalServiceKey(), cfg.AIServiceTimeout)

	// รวม APP_SECRET_KEY และ APP_SECRET_KEYS ทั้งหมดคั่นด้วย Comma สำหรับ Router (รองรับ Multi-Key Rotation)
	allAppSecretKeys := strings.Join(cfg.GetAppSecretKeys(), ",")

	// ตั้งค่า Router และฉีด Dependencies ทั้งหมดผ่าน DI
	router := ports.SetupRouter(
		itemRepo,
		authGateway,
		contactRepository,
		rentalRepository,
		fcmSender,
		aiGateway,
		allAppSecretKeys,
	)

	// กำหนดค่า HTTP Server ด้วย Timeouts จาก Config
	srv := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      router,
		ReadTimeout:  cfg.ReadTimeout,
		WriteTimeout: cfg.WriteTimeout,
	}

	// รัน Server แบบ Background (Non-blocking)
	go func() {
		slog.Info("Server is starting...", slog.String("port", cfg.Port), slog.String("mode", cfg.GinMode))
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
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
	if err := srv.Shutdown(ctx); err != nil {
		slog.Error("Server forced to shutdown", slog.Any("error", err))
		os.Exit(1)
	}

	slog.Info("Server gracefully stopped")
}
