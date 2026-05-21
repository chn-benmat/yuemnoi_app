package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/Chanachai04/yuemnoi_app/backend/internal/adapters/supabase"
	"github.com/Chanachai04/yuemnoi_app/backend/internal/ports"
	"github.com/gin-gonic/gin"
)

func main() {

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// ตั้งค่าโหมดการทำงานของ Gin (gin.DebugMode สำหรับเทสต์ / gin.ReleaseMode สำหรับใช้งานจริง)
	if os.Getenv("GIN_MODE") == "release" {
		gin.SetMode(gin.ReleaseMode)
	} else {
		gin.SetMode(gin.DebugMode)
	}

	sbURL := os.Getenv("SUPABASE_URL")
	sbKey := os.Getenv("SUPABASE_ANON_KEY")
	supabaseClient := supabase.InitSupabaseClient(sbURL, sbKey)

	// ใช้ Logger และ Recovery Middleware (ป้องกันเซิร์ฟเวอร์พังเวลาเกิด Panic โค้ดเอ๋อ)
	router := ports.SetupRouter(supabaseClient)

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      router,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	// รัน Server
	go func() {
		log.Printf("Server is starting on port %s...", port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Listen error: %s\n", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit // โค้ดจะหยุดนิ่งรอตรงนี้ จนกว่าคุณจะกด Ctrl+C ใน Terminal
	log.Println("Shutting down server...")

	// เคลียร์ Request ที่ค้างอยู่ให้จบภายใน 5 วินาที
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Fatal("Server forced to shutdown:", err)
	}

	log.Println("Server gracefully stopped")
}
