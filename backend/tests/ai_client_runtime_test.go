package tests

import (
	"github.com/chn-benmat/yuemnoi_app/backend/internal/config"
	"github.com/stretchr/testify/require"
	"os"
	"testing"
	"time"
)

// ค่า environment ที่ระบุชัดเจนต้องไม่ถูกไฟล์ JSON ทับ
func TestAIClientRuntimeConfiguration(t *testing.T) {
	original, had := os.LookupEnv("AI_SERVICE_TIMEOUT")
	require.NoError(t, os.Unsetenv("AI_SERVICE_TIMEOUT"))
	t.Cleanup(func() {
		if had {
			_ = os.Setenv("AI_SERVICE_TIMEOUT", original)
		} else {
			_ = os.Unsetenv("AI_SERVICE_TIMEOUT")
		}
	})
	cfg := config.Config{AIServiceTimeout: time.Minute, AIClientRuntimePath: "../../ai_service/config/chat_client_runtime.json"}
	require.NoError(t, cfg.ApplyAIClientRuntime())
	require.Equal(t, 45*time.Second, cfg.AIServiceTimeout)
	t.Setenv("AI_SERVICE_TIMEOUT", "25s")
	cfg.AIServiceTimeout = 25 * time.Second
	require.NoError(t, cfg.ApplyAIClientRuntime())
	require.Equal(t, 25*time.Second, cfg.AIServiceTimeout)
	cfg.AIClientRuntimePath = "missing-client-config.json"
	require.Error(t, cfg.ApplyAIClientRuntime())
}
