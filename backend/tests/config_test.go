package tests

import (
	"testing"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/config"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestConfigLoadSuccessWithDefaults(t *testing.T) {
	t.Setenv("PORT", "")
	t.Setenv("APP_ENV", "")
	t.Setenv("SUPABASE_URL", "https://test.supabase.co")
	t.Setenv("SUPABASE_SERVICE_ROLE_KEY", "test-service-key")
	t.Setenv("APP_SECRET_KEY", "test-secret")

	cfg, err := config.Load()
	require.NoError(t, err)
	require.NotNil(t, cfg)

	assert.Equal(t, "8080", cfg.Port)
	assert.Equal(t, "debug", cfg.Mode)
	assert.Equal(t, "https://test.supabase.co", cfg.SupabaseURL)
	assert.Equal(t, "test-service-key", cfg.SupabaseServiceRoleKey)
	assert.Equal(t, "test-secret", cfg.AppSecretKey)
	assert.Equal(t, 15*time.Second, cfg.ReadTimeout)
	assert.Equal(t, 90*time.Second, cfg.WriteTimeout)
	assert.Equal(t, 5*time.Second, cfg.ShutdownTimeout)
}

func TestConfigLoadCustomValues(t *testing.T) {
	t.Setenv("PORT", "3000")
	t.Setenv("APP_ENV", "release")
	t.Setenv("SUPABASE_URL", "https://custom.supabase.co")
	t.Setenv("SUPABASE_SERVICE_ROLE_KEY", "custom-key")
	t.Setenv("APP_SECRET_KEY", "custom-secret-key")
	t.Setenv("INTERNAL_SERVICE_KEY", "custom-internal-service-secret-16chars")
	t.Setenv("READ_TIMEOUT", "30s")

	cfg, err := config.Load()
	require.NoError(t, err)
	require.NotNil(t, cfg)

	assert.Equal(t, "3000", cfg.Port)
	assert.Equal(t, "release", cfg.Mode)
	assert.Equal(t, "https://custom.supabase.co", cfg.SupabaseURL)
	assert.Equal(t, "custom-key", cfg.SupabaseServiceRoleKey)
	assert.Equal(t, "custom-secret-key", cfg.AppSecretKey)
	assert.Equal(t, "custom-internal-service-secret-16chars", cfg.InternalServiceKey)
	assert.Equal(t, 30*time.Second, cfg.ReadTimeout)
}

func TestConfigLoadMissingRequiredFields(t *testing.T) {
	t.Setenv("SUPABASE_URL", "")
	t.Setenv("SUPABASE_SERVICE_ROLE_KEY", "")

	cfg, err := config.Load()
	assert.Error(t, err)
	assert.Nil(t, cfg)
}
