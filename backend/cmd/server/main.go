package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/service"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
)

func main() {
	// โหลดค่าจากไฟล์ .env (ถ้ามี)
	if err := godotenv.Load(); err != nil {
		_ = godotenv.Load("../../.env")
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	if os.Getenv("GIN_MODE") == "release" {
		gin.SetMode(gin.ReleaseMode)
	} else {
		gin.SetMode(gin.DebugMode)
	}

	sbURL := os.Getenv("SUPABASE_URL")
	sbKey := os.Getenv("SUPABASE_SERVICE_ROLE_KEY")
	supabaseClient := supabase.InitSupabaseClient(sbURL, sbKey)

	aiServiceURL := os.Getenv("AI_SERVICE_URL")
	if aiServiceURL == "" {
		aiServiceURL = "http://localhost:8000"
	}

	aiService := service.NewAIService(aiServiceURL)
	itemRepo := supabase.NewSupabaseItemRepository(supabaseClient)
	authGateway := supabase.NewSupabaseUserRepository(supabaseClient, sbKey)
	contactRepository := supabase.NewSupabaseConversationContactRepository(supabaseClient)
	rentalRepository := supabase.NewSupabaseRentalRepository(supabaseClient)

	router := ports.SetupRouter(
		itemRepo,
		authGateway,
		contactRepository,
		aiService,
		rentalRepository,
	)

	// กำหนดค่า HTTP Server
	srv := &http.Server{
		Addr:    ":" + port,
		Handler: router,
		// ปรับเพิ่ม Read/Write Timeout เพื่อรองรับ LLM / Agent Pipeline ที่อาจใช้เวลาประมวลผลนานกว่า API ทั่วไป
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 90 * time.Second,
	}

	// รัน Server แบบ Background (Non-blocking)
	go func() {
		log.Printf("Server is starting on port %s...", port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Listen error: %s\n", err)
		}
	}()

	// รอรับ Signal สำหรับการทำ Graceful Shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down server...")

	// เคลียร์ Request ที่ค้างอยู่ให้จบภายใน 5 วินาที
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Fatal("Server forced to shutdown:", err)
	}

	log.Println("Server gracefully stopped")
}
