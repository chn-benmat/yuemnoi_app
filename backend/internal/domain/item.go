package domain

import (
	"context"
	"errors"
	"time"
)

var (
	ErrItemNotFound = errors.New("item not found")
	ErrItemInUse    = errors.New("item is referenced by another record")
)

// Item ตรงกับตาราง item_tb ในฐานข้อมูล Supabase
type Item struct {
	ID           int64     `json:"id"`
	UserID       string    `json:"user_id"`
	ItemName     string    `json:"item_name"`
	ItemImageURL []string  `json:"item_image_url"`
	Description  string    `json:"description"`
	Category     string    `json:"category"`
	Price        int       `json:"price"`
	Status       string    `json:"status"` // เช่น "pending", "verified", "rejected"
	Type         string    `json:"type"`   // เช่น "ปล่อยเช่า", "ไม่ปล่อยเช่า"
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// Review ตรงกับตาราง review_tb ในฐานข้อมูล Supabase
type Review struct {
	ID          string    `json:"id"`
	UserID      string    `json:"user_id"`
	ItemName    string    `json:"item_name"`
	Rating      string    `json:"rating"` // การให้คะแนน
	Description string    `json:"description"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

type ItemRepository interface {
	Insert(ctx context.Context, item *Item) (*Item, error)
	FindAll(ctx context.Context) ([]Item, error)
	FindByID(ctx context.Context, id int64) (*Item, error)
	Update(ctx context.Context, id int64, userID string, fields map[string]interface{}) (*Item, error)
	Delete(ctx context.Context, id int64, userID string) error
	// InsertReview(ctx context.Context, review *Review) error
}
