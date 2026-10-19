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
	PickupLocation  string   `json:"pickup_location" form:"pickup_location"`
	PickupAddress   string   `json:"pickup_address" form:"pickup_address"`
	PickupNote      string   `json:"pickup_note" form:"pickup_note"`
	PickupLatitude  *float64 `json:"pickup_latitude" form:"pickup_latitude"`
	PickupLongitude *float64 `json:"pickup_longitude" form:"pickup_longitude"`

	ID             int64     `json:"id"`
	UserID         string    `json:"user_id"`
	ItemName       string    `json:"item_name"`
	ItemImageURL   []string  `json:"item_image_url"`
	Description    string    `json:"description"`
	Category       string    `json:"category"`
	Price          int       `json:"price"`
	Status         string    `json:"status"` // เช่น "pending", "verified", "rejected"
	OwnerHidden    bool      `json:"owner_hidden"`
	Type           string    `json:"type"` // เช่น "รายวัน", "รายชั่วโมง"
	OwnerName      string    `json:"owner_name,omitempty"`
	IsVerified     bool      `json:"is_verified"`
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

type ItemRepository interface {
	Insert(ctx context.Context, item *Item, images []ItemImage) (*Item, error)
	FindAll(ctx context.Context) ([]RankedItem, error)
	FindByID(ctx context.Context, id int64) (*Item, error)
	HasRentalAccess(ctx context.Context, id int64, userID string) (bool, error)
	Update(ctx context.Context, id int64, userID string, fields map[string]interface{}) (*Item, error)
	Delete(ctx context.Context, id int64, userID string) error
	GetAutoReply(ctx context.Context, id int64, userID string) (*ItemAutoReply, error)
	SaveAutoReply(ctx context.Context, id int64, userID string, settings ItemAutoReply) (*ItemAutoReply, error)
}
