package config

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/caarlos0/env/v11"
	"github.com/joho/godotenv"
)

// Config โครงสร้างเก็บคอนฟิกูเรชันทั้งหมดของระบบ Backend ผ่าน Struct Tag
type Config struct {
	PlaceSuggestionsURL     string        `env:"PLACE_SUGGESTIONS_URL" envDefault:"https://photon.komoot.io"`
	GeocodingURL            string        `env:"GEOCODING_URL" envDefault:"https://nominatim.openstreetmap.org"`
	OperationsEnabled       bool          `env:"OPERATIONS_ENABLED" envDefault:"false"`
	IdentityEncryptionKey   string        `env:"IDENTITY_ENCRYPTION_KEY"`
	IdentityHMACKey         string        `env:"IDENTITY_HMAC_KEY"`
	IdentityCleanupInterval time.Duration `env:"IDENTITY_CLEANUP_INTERVAL" envDefault:"15m"`

	Port                   string        `env:"PORT" envDefault:"8080"`
	Mode                   string        `env:"APP_ENV"`
	LegacyMode             string        `env:"GIN_MODE" envDefault:"debug"`
	SupabaseURL            string        `env:"SUPABASE_URL,notEmpty"`
	SupabaseServiceRoleKey string        `env:"SUPABASE_SERVICE_ROLE_KEY,notEmpty"`
	AppSecretKey           string        `env:"APP_SECRET_KEY"`
	AppSecretKeys          string        `env:"APP_SECRET_KEYS"`
	InternalServiceKey     string        `env:"INTERNAL_SERVICE_KEY"`
	AIServiceURL           string        `env:"AI_SERVICE_URL" envDefault:"http://localhost:8000"`
	AIServiceTimeout       time.Duration `env:"AI_SERVICE_TIMEOUT" envDefault:"45s"`
	AIClientRuntimePath    string        `env:"AI_CLIENT_RUNTIME_PATH"`
	ReadTimeout            time.Duration `env:"READ_TIMEOUT" envDefault:"15s"`
	WriteTimeout           time.Duration `env:"WRITE_TIMEOUT" envDefault:"90s"`
	ShutdownTimeout        time.Duration `env:"SHUTDOWN_TIMEOUT" envDefault:"5s"`
}

// GetAppSecretKeys คืนรายการกุญแจ APP_SECRET_KEY ทั้งหมด (รองรับ Multi-Key Rotation)
func (c *Config) GetAppSecretKeys() []string {
	var keys []string
	addKeys := func(raw string) {
		for _, k := range strings.Split(raw, ",") {
			trimmed := strings.TrimSpace(k)
			if trimmed != "" {
				keys = append(keys, trimmed)
			}
		}
	}
	addKeys(c.AppSecretKey)
	addKeys(c.AppSecretKeys)
	return keys
}

// GetPrimaryInternalServiceKey คืนกุญแจหลักสำหรับส่งไปยัง AI Service (ตัวแรกในกรณีมีหลายคีย์)
func (c *Config) GetPrimaryInternalServiceKey() string {
	for _, k := range strings.Split(c.InternalServiceKey, ",") {
		trimmed := strings.TrimSpace(k)
		if trimmed != "" {
			return trimmed
		}
	}
	return ""
}

// Validate ตรวจสอบค่าคอนฟิกที่จำเป็นทั้งหมด
func (c *Config) Validate() error {
	if c.IdentityCleanupInterval <= 0 {
		return fmt.Errorf("IDENTITY_CLEANUP_INTERVAL must be positive")
	}
	if c.AIServiceTimeout <= 0 {
		return fmt.Errorf("AI_SERVICE_TIMEOUT must be positive")
	}
	if strings.TrimSpace(c.SupabaseURL) == "" {
		return fmt.Errorf("SUPABASE_URL is required")
	}
	if strings.TrimSpace(c.SupabaseServiceRoleKey) == "" {
		return fmt.Errorf("SUPABASE_SERVICE_ROLE_KEY is required")
	}

	// ในโหมด Release (Production) ต้องบังคับให้มีกุญแจความปลอดภัยที่แข็งแกร่ง
	if c.Mode == "release" {
		if len(c.GetAppSecretKeys()) == 0 {
			return fmt.Errorf("APP_SECRET_KEY is required in release mode")
		}
		primaryInternalKey := c.GetPrimaryInternalServiceKey()
		if primaryInternalKey == "" {
			return fmt.Errorf("INTERNAL_SERVICE_KEY is required in release mode")
		}
		if len(primaryInternalKey) < 16 {
			return fmt.Errorf("INTERNAL_SERVICE_KEY must be at least 16 characters for security")
		}
	}
	return nil
}

// Load อ่านคอนฟิกจากไฟล์ .env (ถ้ามี) และแปลง Environment Variables ลงใน Config Struct
func Load() (*Config, error) {
	// โหลดไฟล์ .env ถ้ามีอยู่
	if err := godotenv.Load(); err != nil {
		_ = godotenv.Load("../../.env")
	}

	var cfg Config
	if err := env.Parse(&cfg); err != nil {
		return nil, fmt.Errorf("parse config error: %w", err)
	}
	// รองรับ environment ของ deployment เดิม โดย APP_ENV ที่กำหนดชัดเจนมีสิทธิ์สูงกว่า
	if cfg.Mode == "" {
		cfg.Mode = cfg.LegacyMode
	}
	if err := cfg.ApplyAIClientRuntime(); err != nil {
		return nil, err
	}

	if err := cfg.Validate(); err != nil {
		return nil, err
	}

	return &cfg, nil
}

// โหลดค่าจาก JSON ร่วมกับ Flutter และให้ environment/.env ที่ระบุชัดเจนมีสิทธิ์สูงกว่า
func (c *Config) ApplyAIClientRuntime() error {
	if strings.TrimSpace(c.AIClientRuntimePath) == "" {
		return nil
	}
	raw, err := os.ReadFile(c.AIClientRuntimePath)
	if err != nil {
		return fmt.Errorf("cannot read AI client runtime")
	}
	var runtime struct {
		SchemaVersion  string `json:"schema_version"`
		GatewaySeconds int    `json:"AI_GATEWAY_TIMEOUT_SECONDS"`
	}
	if json.Unmarshal(raw, &runtime) != nil || runtime.SchemaVersion != "1" || runtime.GatewaySeconds <= 0 {
		return fmt.Errorf("invalid AI client runtime")
	}
	if _, explicit := os.LookupEnv("AI_SERVICE_TIMEOUT"); !explicit {
		c.AIServiceTimeout = time.Duration(runtime.GatewaySeconds) * time.Second
	}
	return nil
}
