package domain

import (
	"context"
	"errors"
	"time"
)

var (
	ErrRentalNotFound         = errors.New("rental not found")
	ErrRentalUnavailable      = errors.New("rental period is unavailable")
	ErrItemRentalOccupied     = errors.New("item rental occupied")
	ErrInvalidRental          = errors.New("invalid rental")
	ErrRentalForbidden        = errors.New("forbidden to update this rental")
	ErrRentalStatusTransition = errors.New("invalid rental status transition")
	ErrRentalReturnToken      = errors.New("invalid or expired return token")
	ErrRentalNotStarted       = errors.New("rental has not started yet")
	ErrRentalRequestExpired   = errors.New("requested pickup time has passed")
	ErrRentalPriceChanged     = errors.New("rental listing price has changed")
	ErrRentalRequestChanged   = errors.New("rental request has changed")
	ErrReturnPenaltyNoAmount  = errors.New("return penalty has no amount")
	ErrReturnPenaltyNoAccount = errors.New("return penalty requires a PromptPay account")
)

// CreateRentalRequest accepts only user-selected values. Pricing is calculated
// by the database from the current item price.
type CreateRentalRequest struct {
	ExpectedPenaltyTerms *RentalPenaltyTerms `json:"expected_penalty_terms,omitempty"`
	ItemID               int64               `json:"item_id"`
	StartAt              time.Time           `json:"start_at"`
	EndAt                time.Time           `json:"end_at"`
	RentalType           string              `json:"rental_type"`
	PickupLocation       string              `json:"pickup_location"`
	OfferMessageID       string              `json:"offer_message_id,omitempty"`
	BookingID            int64               `json:"booking_id,omitempty"`
	ConversationID       string              `json:"conversation_id,omitempty"`
	PaymentMethod        string              `json:"payment_method,omitempty"`
	UnitPrice            int64               `json:"unit_price,omitempty"`
	QueueMessageID       int64               `json:"-"`
	RequestRevision      int                 `json:"-"`
}

type RentalOrder struct {
	PickupAddress string `json:"pickup_address"`
	PickupNote    string `json:"pickup_note"`

	ID               int64     `json:"id"`
	UserID           string    `json:"user_id"`
	ItemID           int64     `json:"item_id"`
	StartAt          time.Time `json:"start_at"`
	EndAt            time.Time `json:"end_at"`
	RentalType       string    `json:"type"`
	PickupLocation   string    `json:"pickup_location"`
	TotalPrice       int64     `json:"total_price"`
	Status           string    `json:"status"`
	PaymentMethod    string    `json:"payment_method,omitempty"`
	RequestMessageID int64     `json:"rental_request_message_id,omitempty"`
}

type RentalRepository interface {
	CreateRental(ctx context.Context, userID string, request CreateRentalRequest) (*RentalOrder, error)
	ConfirmRental(ctx context.Context, userID string, rentalID int64, offerMessageID, paymentMethod string, requestRevision int) (*RentalOrder, error)
	UpdateRentalStatus(ctx context.Context, userID string, rentalID int64, targetStatus string) (*RentalOrder, error)
	RentalReturnSession(ctx context.Context, userID string, rentalID int64) (map[string]any, error)
	SubmitRentalEvidence(ctx context.Context, userID string, rentalID int64, images []ItemImage, checklist map[string]bool) (*RentalOrder, error)
	InspectRentalReturn(ctx context.Context, userID string, rentalID int64) (*RentalReturnChallenge, error)
	ConfirmRentalReceipt(ctx context.Context, userID string, rentalID int64) (*RentalOrder, error)
	CompleteRentalReturn(ctx context.Context, userID string, rentalID int64, token string) (*RentalOrder, error)
	CancelRental(ctx context.Context, userID string, rentalID int64, reason, note string, images []ItemImage) (*RentalOrder, error)
}

type RentalHandoverRepository interface {
	HandoverPayment(ctx context.Context, userID string, rentalID int64, confirm bool) (RentalHandoverPayment, error)
	SavePromptPayAccount(ctx context.Context, userID string, rentalID int64, phone, nationalID string) (RentalHandoverPayment, error)
}

type RentalReturnPenaltyReport struct {
	Damaged      bool   `json:"damaged"`
	Late         bool   `json:"late"`
	Details      string `json:"details"`
	AmountSatang int64  `json:"amount_satang"`
}

type RentalReturnPenaltyRepository interface {
	SaveRentalReturnPenalty(ctx context.Context, userID string, rentalID int64, report RentalReturnPenaltyReport) (RentalReturnPenaltyReport, error)
	RentalReturnPenaltyQR(ctx context.Context, userID string, rentalID int64) (string, error)
}

type RentalIncomeRepository interface {
	GetRentalIncome(ctx context.Context, userID string) (RentalIncomeSummary, error)
}

type RentalIncomeSummary struct {
	TotalSatang  int64                 `json:"total_satang"`
	Transactions []RentalIncomeReceipt `json:"transactions"`
}

type RentalIncomeReceipt struct {
	ItemName      string    `json:"item_name"`
	ConfirmedAt   time.Time `json:"confirmed_at"`
	PaymentMethod string    `json:"payment_method"`
	AmountSatang  int64     `json:"amount_satang"`
}

type RentalHandoverPayment struct {
	PaymentMethod       string `json:"payment_method"`
	Status              string `json:"status"`
	PaymentConfirmed    bool   `json:"payment_confirmed"`
	TotalSatang         int64  `json:"total_satang,omitempty"`
	CanCollectPayment   bool   `json:"can_collect_payment"`
	PromptPayPhone      string `json:"promptpay_phone,omitempty"`
	PromptPayNationalID string `json:"-"`
	PromptPayIDType     string `json:"promptpay_id_type,omitempty"`
	PromptPayQR         string `json:"promptpay_qr,omitempty"`
}

type RentalReturnChallenge struct {
	Token     string    `json:"token"`
	OTP       string    `json:"otp"`
	ExpiresAt time.Time `json:"expires_at"`
}
