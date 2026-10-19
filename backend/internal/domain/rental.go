package domain

import (
	"context"
	"errors"
	"time"
)

var (
	ErrRentalNotFound         = errors.New("rental not found")
	ErrRentalUnavailable      = errors.New("rental period is unavailable")
	ErrInvalidRental          = errors.New("invalid rental")
	ErrRentalForbidden        = errors.New("forbidden to update this rental")
	ErrRentalStatusTransition = errors.New("invalid rental status transition")
	ErrRentalReturnToken      = errors.New("invalid or expired return token")
)

// CreateRentalRequest accepts only user-selected values. Pricing is calculated
// by the database from the current item price.
type CreateRentalRequest struct {
	ItemID         int64     `json:"item_id"`
	StartAt        time.Time `json:"start_at"`
	EndAt          time.Time `json:"end_at"`
	RentalType     string    `json:"rental_type"`
	PickupLocation string    `json:"pickup_location"`
	OfferMessageID string    `json:"offer_message_id,omitempty"`
	BookingID      int64     `json:"booking_id,omitempty"`
}

type RentalOrder struct {
	PickupAddress string  `json:"pickup_address"`
	PickupNote    string  `json:"pickup_note"`
	Latitude      *string `json:"latitude"`
	Longitude     *string `json:"longitude"`

	ID             int64     `json:"id"`
	UserID         string    `json:"user_id"`
	ItemID         int64     `json:"item_id"`
	StartAt        time.Time `json:"start_at"`
	EndAt          time.Time `json:"end_at"`
	RentalType     string    `json:"type"`
	PickupLocation string    `json:"pickup_location"`
	TotalPrice     int64     `json:"total_price"`
	Status         string    `json:"status"`
}

type RentalRepository interface {
	CreateRental(ctx context.Context, userID string, request CreateRentalRequest) (*RentalOrder, error)
	ConfirmRental(ctx context.Context, userID string, rentalID int64, offerMessageID string) (*RentalOrder, error)
	UpdateRentalStatus(ctx context.Context, userID string, rentalID int64, targetStatus string) (*RentalOrder, error)
	RentalReturnSession(ctx context.Context, userID string, rentalID int64) (map[string]any, error)
	SubmitRentalEvidence(ctx context.Context, userID string, rentalID int64, images []ItemImage, checklist map[string]bool) (*RentalOrder, error)
	InspectRentalReturn(ctx context.Context, userID string, rentalID int64) (*RentalReturnChallenge, error)
	CompleteRentalReturn(ctx context.Context, userID string, rentalID int64, token string) (*RentalOrder, error)
	CancelRental(ctx context.Context, userID string, rentalID int64, reason, note string, images []ItemImage) (*RentalOrder, error)
}

type RentalReturnChallenge struct {
	Token     string    `json:"token"`
	OTP       string    `json:"otp"`
	ExpiresAt time.Time `json:"expires_at"`
}
