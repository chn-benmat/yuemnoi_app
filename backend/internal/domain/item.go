package domain

import (
	"context"
	"time"
)

// Item ตรงกับตาราง item_tb ในฐานข้อมูล Supabase
type Item struct {
	ID           int64     `json:"id"`
	UserID       string    `json:"user_id"`
	ItemName     string    `json:"item_name"`
	ItemImageUrl []string  `json:"item_image_url"`
	Description  string    `json:"description"`
	Category     string    `json:"category"`
	Status       string    `json:"status"` // เช่น "pending", "verified", "rejected"
	Type         string    `json:"type"`   // เช่น "ปล่อยเช่า", "ไม่ปล่อยเช่า"
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// Review ตรงกับตาราง review_tb ในฐานข้อมูล Supabase
type Review struct {
	ID          int64     `json:"id"`
	UserID      string    `json:"user_id"`
	ItemName    string    `json:"item_name"`
	Rating      string    `json:"rating"` // การให้คะแนน
	Description string    `json:"description"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

type ItemRepository interface {
	Insert(ctx context.Context, item *Item) error
	FindAll(ctx context.Context) ([]Item, error)
	// GetByID(ctx context.Context, id int64) (*Item, error)
	// InsertReview(ctx context.Context, review *Review) error
}
