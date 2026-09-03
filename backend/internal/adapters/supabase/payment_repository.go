package supabase

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"strings"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/nedpals/supabase-go"
	postgrest "github.com/nedpals/supabase-go/postgrest/pkg"
)

type supabasePaymentRepository struct {
	client *supabase.Client
}

func NewSupabasePaymentRepository(sbClient *supabase.Client) domain.PaymentRepository {
	return &supabasePaymentRepository{client: sbClient}
}

func (r *supabasePaymentRepository) CreateRental(
	ctx context.Context,
	userID string,
	request domain.CreateRentalRequest,
) (*domain.RentalOrder, error) {
	var rental domain.RentalOrder
	err := r.client.DB.Rpc("create_stripe_rental_order", map[string]interface{}{
		"p_user_id":         userID,
		"p_item_id":         request.ItemID,
		"p_start_at":        request.StartAt.UTC(),
		"p_end_at":          request.EndAt.UTC(),
		"p_rental_type":     request.RentalType,
		"p_pickup_location": strings.TrimSpace(request.PickupLocation),
	}).ExecuteWithContext(ctx, &rental)
	if err != nil {
		return nil, mapPaymentRepositoryError("create rental", err)
	}
	return &rental, nil
}

func (r *supabasePaymentRepository) FindRentalForUser(
	ctx context.Context,
	rentalID int64,
	userID string,
) (*domain.RentalOrder, error) {
	var rentals []domain.RentalOrder
	err := r.client.DB.From("booking_tb").
		Select("id,user_id,item_id,start_at,end_at,type,pickup_location,total_amount_satang,currency,status,payment_status").
		Eq("id", strconv.FormatInt(rentalID, 10)).
		Eq("user_id", userID).
		ExecuteWithContext(ctx, &rentals)
	if err != nil {
		return nil, fmt.Errorf("find rental: %w", err)
	}
	if len(rentals) == 0 {
		return nil, domain.ErrRentalNotFound
	}
	return &rentals[0], nil
}

func (r *supabasePaymentRepository) CreateOrGetPayment(
	ctx context.Context,
	rental *domain.RentalOrder,
	idempotencyKey string,
) (*domain.PaymentOrder, error) {
	var payment domain.PaymentOrder
	err := r.client.DB.Rpc("create_or_get_stripe_payment_order", map[string]interface{}{
		"p_booking_id":      rental.ID,
		"p_user_id":         rental.UserID,
		"p_idempotency_key": idempotencyKey,
	}).ExecuteWithContext(ctx, &payment)
	if err != nil {
		return nil, mapPaymentRepositoryError("create payment order", err)
	}
	return &payment, nil
}

func (r *supabasePaymentRepository) AttachCheckoutSession(
	ctx context.Context,
	paymentID string,
	sessionID string,
	livemode bool,
) error {
	var payment domain.PaymentOrder
	err := r.client.DB.Rpc("attach_stripe_checkout_session", map[string]interface{}{
		"p_payment_order_id":           paymentID,
		"p_stripe_checkout_session_id": sessionID,
		"p_livemode":                   livemode,
	}).ExecuteWithContext(ctx, &payment)
	if err != nil {
		return mapPaymentRepositoryError("attach Checkout Session", err)
	}
	return nil
}

func (r *supabasePaymentRepository) FindPaymentForRental(
	ctx context.Context,
	rentalID int64,
	userID string,
) (*domain.PaymentOrder, error) {
	var payments []domain.PaymentOrder
	err := r.client.DB.From("payment_order_tb").
		Select("id,booking_id,user_id,amount_satang,currency,status,stripe_checkout_session_id,stripe_payment_intent_id,idempotency_key,livemode,paid_at,created_at,updated_at").
		Eq("booking_id", strconv.FormatInt(rentalID, 10)).
		Eq("user_id", userID).
		ExecuteWithContext(ctx, &payments)
	if err != nil {
		return nil, fmt.Errorf("find payment order: %w", err)
	}
	if len(payments) == 0 {
		return nil, domain.ErrPaymentNotFound
	}
	return &payments[0], nil
}

func (r *supabasePaymentRepository) ProcessEvent(ctx context.Context, event domain.PaymentEvent) (bool, error) {
	var processed bool
	err := r.client.DB.Rpc("process_stripe_payment_event", map[string]interface{}{
		"p_stripe_event_id":            event.ID,
		"p_payment_order_id":           event.PaymentOrderID,
		"p_event_type":                 event.Type,
		"p_stripe_checkout_session_id": event.StripeCheckoutSessionID,
		"p_stripe_payment_intent_id":   event.StripePaymentIntentID,
		"p_amount_satang":              event.AmountSatang,
		"p_currency":                   strings.ToLower(event.Currency),
		"p_livemode":                   event.Livemode,
		"p_next_status":                event.NextStatus,
	}).ExecuteWithContext(ctx, &processed)
	if err != nil {
		return false, mapPaymentRepositoryError("process Stripe event", err)
	}
	return processed, nil
}

func mapPaymentRepositoryError(operation string, err error) error {
	var requestErr *postgrest.RequestError
	if !errors.As(err, &requestErr) {
		return fmt.Errorf("%s: %w", operation, err)
	}

	message := strings.ToLower(requestErr.Message)
	switch {
	case strings.Contains(message, "rental period is unavailable"),
		strings.Contains(message, "item is unavailable"):
		return domain.ErrRentalUnavailable
	case strings.Contains(message, "booking not found"):
		return domain.ErrRentalNotFound
	case strings.Contains(message, "payment order not found"):
		return domain.ErrPaymentNotFound
	case requestErr.Code == "22023":
		return domain.ErrInvalidRental
	default:
		return fmt.Errorf("%s: %w", operation, err)
	}
}
