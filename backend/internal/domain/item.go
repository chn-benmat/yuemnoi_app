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
	ID             int64     `json:"id"`
	UserID         string    `json:"user_id"`
	ItemName       string    `json:"item_name"`
	ItemImageURL   []string  `json:"item_image_url"`
	Description    string    `json:"description"`
	Category       string    `json:"category"`
	Price          int       `json:"price"`
	Status         string    `json:"status"` // เช่น "pending", "verified", "rejected"
	Type           string    `json:"type"`   // เช่น "รายวัน", "รายชั่วโมง"
	OwnerName      string    `json:"owner_name,omitempty"`
	OwnerAvatarURL string    `json:"owner_avatar_url,omitempty"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}

// RankedItem คือข้อมูลอุปกรณ์พร้อมสัญญาณจริงที่ใช้แสดงในฟีดหน้า Home
type RankedItem struct {
	Item
	Rating           float64 `json:"rating"`
	ReviewCount      int64   `json:"review_count"`
	PaidBookingCount int64   `json:"paid_booking_count"`
}

// ItemImage คือไฟล์รูปอุปกรณ์ที่ผ่านการตรวจสอบจาก HTTP handler แล้ว
type ItemImage struct {
	Data        []byte
	ContentType string
	Extension   string
}

type CreateItemRequest struct {
	ItemName     string   `json:"item_name" form:"item_name" binding:"required,min=1,max=150"`
	ItemImageURL []string `json:"item_image_url" form:"item_image_url" binding:"omitempty,dive,max=2048"`
	Description  string   `json:"description" form:"description" binding:"required,min=1,max=2000"`
	Category     string   `json:"category" form:"category" binding:"required,min=1,max=100"`
	Price        int      `json:"price" form:"price" binding:"required,gt=0"`
	Type         string   `json:"type" form:"type" binding:"required,oneof=รายวัน รายชั่วโมง"`
}

type UpdateItemRequest struct {
	ItemName     *string   `json:"item_name" binding:"omitempty,min=1,max=150"`
	ItemImageURL *[]string `json:"item_image_url" binding:"omitempty,dive,max=2048"`
	Description  *string   `json:"description" binding:"omitempty,min=1,max=2000"`
	Category     *string   `json:"category" binding:"omitempty,max=100"`
	Price        *int      `json:"price" binding:"omitempty,gt=0"`
	Status       *string   `json:"status" binding:"omitempty,max=50"`
	Type         *string   `json:"type" binding:"omitempty,max=100"`
}

type ItemRepository interface {
	Insert(ctx context.Context, item *Item, images []ItemImage) (*Item, error)
	FindAll(ctx context.Context) ([]RankedItem, error)
	FindByID(ctx context.Context, id int64) (*Item, error)
	Update(ctx context.Context, id int64, userID string, fields map[string]interface{}) (*Item, error)
	Delete(ctx context.Context, id int64, userID string) error
}
