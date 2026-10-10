package domain

import (
	"context"
	"encoding/json"
	"time"
)

// OperationsStore เป็นช่องทางข้อมูลเจ้าหน้าที่และหลักฐานที่เข้าถึงได้เฉพาะ backend
type OperationsStore interface {
	RPC(context.Context, string, map[string]any) (json.RawMessage, error)
	UploadEvidence(context.Context, string, []byte, string) error
	ReadEvidence(context.Context, string) ([]byte, string, error)
	DeleteEvidence(context.Context, string) error
}
type IdentityAnalysis struct {
	OCRText        string            `json:"ocr_text"`
	FaceSimilarity *float64          `json:"face_similarity"`
	LiveScore      *float64          `json:"live_score"`
	Warnings       []string          `json:"warnings"`
	Models         map[string]string `json:"models"`
}
type IdentityAnalyzer interface {
	AnalyzeIdentity(context.Context, []byte, []byte) (*IdentityAnalysis, error)
	ReadIdentityCard(context.Context, []byte) (*IdentityOCR, error)
}
type OperationsOptions struct {
	Store            OperationsStore
	Analyzer         IdentityAnalyzer
	EncryptionKey    []byte
	HMACKey          []byte
	CleanupInterval  time.Duration
	OCRMinConfidence float64
}
