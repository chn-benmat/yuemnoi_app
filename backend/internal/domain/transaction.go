package domain

import (
	"context"
	"time"
)

// Wallet ตรงกับตาราง wallet_tb
type Wallet struct {
	ID        string    `json:"id"`
	UserID    string    `json:"user_id"`
	Amount    int       `json:"amount"` // ใน schema ตัวนี้เก็บเป็น integer null
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// Transaction ตรงกับตาราง transaction_tb
type Transaction struct {
	ID        string    `json:"id"`
	UserID    string    `json:"user_id"`
	WalletID  int64     `json:"wallet_id"`
	BookingID int64     `json:"booking_id"` // ผูกกับรายการจองเช่าอุปกรณ์
	Amount    string    `json:"amount"`     // ตาม schema ของคุณเก็บเป็น text
	Type      string    `json:"type"`       // เช่น "deposit" (ฝาก), "withdraw" (ถอน), "payment" (จ่ายค่าเช่า)
	Status    string    `json:"status"`     // เช่น "success", "pending", "failed"
	CreatedAt time.Time `json:"created_at"`
}

type TransactionRepository interface {
	GetWalletByUserID(ctx context.Context, userID string) (*Wallet, error)
	UpdateWalletAmount(ctx context.Context, userID string, newAmount int) error
	CreateTransaction(ctx context.Context, tx *Transaction) error
}
