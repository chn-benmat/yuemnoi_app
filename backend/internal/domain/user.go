package domain

import (
	"context"
	"errors"
)

var ErrInvalidAccessToken = errors.New("invalid access token")

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

type AuthTokens struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
}

type UserProfile struct {
	UserID       string `json:"user_id"`
	Email        string `json:"email"`
	DisplayName  string `json:"display_name"`
	Username     string `json:"username"`
	Bio          string `json:"bio"`
	Phone        string `json:"phone"`
	UserImageURL string `json:"user_image_url"`
}

type UpdateProfileRequest struct {
	DisplayName *string `json:"display_name"`
	Username    *string `json:"username"`
	Bio         *string `json:"bio"`
}

type AuthRepository interface {
	Login(ctx context.Context, email, password string) (*AuthTokens, error)
	Register(ctx context.Context, user RegisterUser) (*RegisterResult, error)
	SyncGoogleProfileImage(ctx context.Context, userToken string) (string, error)
	ChangePassword(ctx context.Context, userToken, newPassword string) error
	SendOTP(ctx context.Context, email string) error
	VerifyOTP(ctx context.Context, email, otpCode string) (*AuthTokens, error)
	IsEmailExists(ctx context.Context, email string) (bool, error)
	GetProfile(ctx context.Context, userID string) (*UserProfile, error)
	UpdateProfile(ctx context.Context, userID string, req UpdateProfileRequest, img *ProfileImage) (*UserProfile, error)
	UpdateContact(ctx context.Context, userID string, phone string) error
	UpdateFCMToken(ctx context.Context, userID string, fcmToken string) error
	GetFCMToken(ctx context.Context, userID string) (string, error)
	DeleteFCMToken(ctx context.Context, userID string) error
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
