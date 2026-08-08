package domain

import (
	"context"
	"time"
)

// Profile ตรงกับตาราง profile_tb ในฐานข้อมูล Supabase
type Profile struct {
	ID           string    `json:"id"`
	UserID       string    `json:"user_id"`
	UserImageUrl string    `json:"user_image_url"`
	Latitude     float64   `json:"latitude"`  // เก็บพิกัดละติจูด
	Longitude    float64   `json:"longitude"` // เก็บพิกัดลองจิจูด
	CreatedAt    time.Time `json:"created_at"`
}

// Verification ตรงกับตาราง verification_tb ในฐานข้อมูล Supabase
type Verification struct {
	ID          string    `json:"id"`
	UserID      string    `json:"user_id"`
	Provider    string    `json:"provider"`     // เช่น "ndid", "thaid"
	ProviderRef string    `json:"provider_ref"` // รหัสอ้างอิงจากผู้ให้บริการยืนยันตัวตน
	Status      string    `json:"status"`       // เช่น "pending", "verified", "rejected"
	CreatedAt   time.Time `json:"created_at"`
}

// RegisterUser contains all data required to create an Auth user and an
// optional profile image. DisplayName is stored as Auth user metadata, Phone
// is stored in both Auth and metadata, and ProfileImage goes to Storage.
type RegisterUser struct {
	DisplayName  string
	Email        string
	Phone        string
	Password     string
	ProfileImage *ProfileImage
}

type ProfileImage struct {
	Data        []byte
	ContentType string
	Extension   string
}

type RegisterResult struct {
	UserID       string `json:"user_id"`
	UserImageURL string `json:"user_image_url,omitempty"`
}

type UserLoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=6"`
}

type AuthTokens struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
}

type UserRegisterRequest struct {
	DisplayName     string `json:"display_name" form:"display_name" binding:"required,max=150"`
	Email           string `json:"email" form:"email" binding:"required,email"`
	Phone           string `json:"phone" form:"phone" binding:"required"`
	Password        string `json:"password" form:"password" binding:"required,min=6"`
	ConfirmPassword string `json:"confirm_password" form:"confirm_password" binding:"omitempty,min=6"`
}

type UserChangePasswordRequest struct {
	NewPassword string `json:"new_password" binding:"required,min=6"`
}

type UserSendOTP struct {
	Email string `json:"email" binding:"required,email"`
}

type UserVerifyOTPResetRequest struct {
	Email   string `json:"email" binding:"required,email"`
	OTPCode string `json:"otp_code" binding:"required,len=6,numeric"`
}

type AuthRepository interface {
	Login(ctx context.Context, email, password string) (*AuthTokens, error)
	Register(ctx context.Context, user RegisterUser) (*RegisterResult, error)
	SyncGoogleProfileImage(ctx context.Context, userToken string) (string, error)
	ChangePassword(ctx context.Context, userToken, newPassword string) error
	SendOTP(ctx context.Context, email string) error
	VerifyOTP(ctx context.Context, email, otpCode string) (*AuthTokens, error)
	IsEmailExists(ctx context.Context, email string) (bool, error)
	Logout(ctx context.Context, userToken string) error
}

type TokenVerifier interface {
	UserIDFromToken(ctx context.Context, userToken string) (string, error)
}

// AuthGateway groups the authentication and token contracts implemented by
// the same external authentication adapter.
type AuthGateway interface {
	AuthRepository
	TokenVerifier
}

type UserRepository interface {
	UpdateProfile(ctx context.Context, profile *Profile) error
	GetProfileByUserID(ctx context.Context, userID string) (*Profile, error)
	CreateKYCVerification(ctx context.Context, v *Verification) error
}
