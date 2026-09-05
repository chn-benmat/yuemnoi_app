package domain

import (
	"context"
	"errors"
	"time"
)

var (
	ErrRentalNotFound    = errors.New("rental not found")
	ErrRentalUnavailable = errors.New("rental period is unavailable")
	ErrInvalidRental     = errors.New("invalid rental")
)

// CreateRentalRequest accepts only user-selected values. Pricing is calculated
// by the database from the current item price.
type CreateRentalRequest struct {
	ItemID         int64     `json:"item_id" binding:"required,gt=0"`
	StartAt        time.Time `json:"start_at" binding:"required"`
	EndAt          time.Time `json:"end_at" binding:"required"`
	RentalType     string    `json:"rental_type" binding:"required,oneof=daily hourly"`
	PickupLocation string    `json:"pickup_location" binding:"required,min=1,max=500"`
}

type RentalOrder struct {
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
}
