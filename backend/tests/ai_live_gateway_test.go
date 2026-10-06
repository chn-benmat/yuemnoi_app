package tests

import (
	"encoding/json"
	"flag"
	"net"
	"net/http"
	"os"
	"testing"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/aiservice"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/config"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	"github.com/gin-gonic/gin"
)

var aiSmokeConfig = flag.String("ai-smoke-config", "", "ไฟล์คอนฟิกสำหรับทดสอบการส่งต่อจริงแบบ opt-in")

// เปิดเฉพาะ handler/adapter จริงบน loopback ไม่ใช่การเปิด production server
func TestAILiveEvaluationGateway(t *testing.T) {
	if *aiSmokeConfig == "" {
		t.Skip("live gateway is opt-in")
	}
	var run struct {
		AIURL            string `json:"ai_url"`
		Bind             string `json:"bind"`
		Ready            string `json:"ready"`
		Stop             string `json:"stop"`
		TimeoutSeconds   int    `json:"timeout_seconds"`
		PollMilliseconds int    `json:"poll_milliseconds"`
	}
	raw, err := os.ReadFile(*aiSmokeConfig)
	if err != nil || json.Unmarshal(raw, &run) != nil || run.TimeoutSeconds <= 0 || run.PollMilliseconds <= 0 {
		t.Fatal("invalid smoke configuration")
	}
	cfg, err := config.Load()
	if err != nil {
		t.Fatal("gateway configuration unavailable")
	}
	gin.SetMode(gin.ReleaseMode)
	router := gin.New()
	handler := ports.NewChatbotHandler(aiservice.NewClient(run.AIURL, cfg.GetPrimaryInternalServiceKey(), cfg.AIServiceTimeout), nil)
	router.POST("/api/v1/chat-ai", handler.SendMessage)
	router.POST("/api/v1/chat-ai/stream", handler.SendMessageStream)
	listener, err := net.Listen("tcp", run.Bind)
	if err != nil {
		t.Fatal("cannot listen for smoke")
	}
	if !listener.Addr().(*net.TCPAddr).IP.IsLoopback() {
		listener.Close()
		t.Fatal("loopback required")
	}
	server := &http.Server{Handler: router, ReadTimeout: cfg.ReadTimeout, WriteTimeout: cfg.WriteTimeout}
	defer server.Close()
	go server.Serve(listener)
	ready, _ := json.Marshal(map[string]string{"url": "http://" + listener.Addr().String()})
	if os.WriteFile(run.Ready, ready, 0600) != nil {
		t.Fatal("cannot publish smoke readiness")
	}
	deadline := time.NewTimer(time.Duration(run.TimeoutSeconds) * time.Second)
	defer deadline.Stop()
	ticker := time.NewTicker(time.Duration(run.PollMilliseconds) * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
			if _, err := os.Stat(run.Stop); err == nil {
				return
			}
		case <-deadline.C:
			t.Fatal("smoke controller timed out")
		}
	}
}
