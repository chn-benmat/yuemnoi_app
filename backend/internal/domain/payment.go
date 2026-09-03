package domain

import (
	"context"
	"errors"
	"time"
)

var (
	ErrRentalNotFound       = errors.New("rental not found")
	ErrRentalUnavailable    = errors.New("rental period is unavailable")
	ErrInvalidRental        = errors.New("invalid rental")
	ErrPaymentNotFound      = errors.New("payment not found")
	ErrPaymentConfiguration = errors.New("payment is not configured")
)

const (
	PaymentStatusCreated           = "created"
	PaymentStatusCheckoutPending   = "checkout_pending"
	PaymentStatusPaid              = "paid"
	PaymentStatusFailed            = "failed"
	PaymentStatusExpired           = "expired"
	PaymentStatusRefunded          = "refunded"
	PaymentStatusPartiallyRefunded = "partially_refunded"
)

// CreateRentalRequest รับเฉพาะข้อมูลที่ผู้ใช้เลือก ส่วนราคาต้องคำนวณบนเซิร์ฟเวอร์เสมอ
type CreateRentalRequest struct {
	ItemID         int64     `json:"item_id" binding:"required,gt=0"`
	StartAt        time.Time `json:"start_at" binding:"required"`
	EndAt          time.Time `json:"end_at" binding:"required"`
	RentalType     string    `json:"rental_type" binding:"required,oneof=daily hourly"`
	PickupLocation string    `json:"pickup_location" binding:"required,min=1,max=500"`
}

type RentalOrder struct {
	ID                int64     `json:"id"`
	UserID            string    `json:"user_id"`
	ItemID            int64     `json:"item_id"`
	StartAt           time.Time `json:"start_at"`
	EndAt             time.Time `json:"end_at"`
	RentalType        string    `json:"type"`
	PickupLocation    string    `json:"pickup_location"`
	TotalAmountSatang int64     `json:"total_amount_satang"`
	Currency          string    `json:"currency"`
	Status            string    `json:"status"`
	PaymentStatus     string    `json:"payment_status"`
}

type PaymentOrder struct {
	ID                      string     `json:"id"`
	BookingID               int64      `json:"booking_id"`
	UserID                  string     `json:"user_id"`
	AmountSatang            int64      `json:"amount_satang"`
	Currency                string     `json:"currency"`
	Status                  string     `json:"status"`
	StripeCheckoutSessionID string     `json:"stripe_checkout_session_id"`
	StripePaymentIntentID   string     `json:"stripe_payment_intent_id"`
	IdempotencyKey          string     `json:"idempotency_key"`
	Livemode                *bool      `json:"livemode"`
	PaidAt                  *time.Time `json:"paid_at"`
	CreatedAt               time.Time  `json:"created_at"`
	UpdatedAt               time.Time  `json:"updated_at"`
}

type CheckoutRequest struct {
	PaymentOrderID string
	BookingID      int64
	ItemName       string
	AmountSatang   int64
	Currency       string
	IdempotencyKey string
}

type CheckoutSession struct {
	ID       string
	URL      string
	Livemode bool
}

type PaymentEvent struct {
	ID                      string
	Type                    string
	PaymentOrderID          string
	StripeCheckoutSessionID string
	StripePaymentIntentID   string
	AmountSatang            int64
	Currency                string
	Livemode                bool
	NextStatus              string
}

type PaymentRepository interface {
	CreateRental(ctx context.Context, userID string, request CreateRentalRequest) (*RentalOrder, error)
	FindRentalForUser(ctx context.Context, rentalID int64, userID string) (*RentalOrder, error)
	CreateOrGetPayment(ctx context.Context, rental *RentalOrder, idempotencyKey string) (*PaymentOrder, error)
	AttachCheckoutSession(ctx context.Context, paymentID, sessionID string, livemode bool) error
	FindPaymentForRental(ctx context.Context, rentalID int64, userID string) (*PaymentOrder, error)
	ProcessEvent(ctx context.Context, event PaymentEvent) (bool, error)
}

type PaymentGateway interface {
	CreateCheckoutSession(ctx context.Context, request CheckoutRequest) (*CheckoutSession, error)
	ParseWebhook(payload []byte, signature string) (*PaymentEvent, error)
}
