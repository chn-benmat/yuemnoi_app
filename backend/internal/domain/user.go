package domain

import (
	"context"
	"time"
)

// Profile ตรงกับตาราง profile_tb ในฐานข้อมูล Supabase
type Profile struct {
	ID           int64     `json:"id"`
	UserID       string    `json:"user_id"`
	UserImageUrl string    `json:"user_image_url"`
	Latitude     float64   `json:"latitude"`  // เก็บพิกัดละติจูด
	Longitude    float64   `json:"longitude"` // เก็บพิกัดลองจิจูด
	CreatedAt    time.Time `json:"created_at"`
}

type Verification struct {
	ID          int64     `json:"id"`
	UserID      string    `json:"user_id"`
	Provider    string    `json:"provider"`     // เช่น "ndid", "thaid"
	ProviderRef string    `json:"provider_ref"` // รหัสอ้างอิงจากผู้ให้บริการยืนยันตัวตน
	Status      string    `json:"status"`       // เช่น "pending", "verified", "rejected"
	CreatedAt   time.Time `json:"created_at"`
}

type UserRepository interface {
	UpdateProfile(ctx context.Context, profile *Profile) error
	GetProfileByUserID(ctx context.Context, userID string) (*Profile, error)
	CreateKYCVerification(ctx context.Context, v *Verification) error
}
