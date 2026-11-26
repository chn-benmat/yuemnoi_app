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
type OperationsOptions struct {
	Store           OperationsStore
	AccountDeletion AccountDeletionRepository
	EncryptionKey   []byte
	HMACKey         []byte
	CleanupInterval time.Duration
}
