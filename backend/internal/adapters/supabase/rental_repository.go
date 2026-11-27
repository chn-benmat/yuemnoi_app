package supabase

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/nedpals/supabase-go"
	postgrest "github.com/nedpals/supabase-go/postgrest/pkg"
)

type supabaseRentalRepository struct {
	client       *supabase.Client
	storage      *storageClient
	promptPayKey []byte
}

type RentalRepositoryKeys struct {
	ServiceRole         string
	PromptPayEncryption []byte
}

func NewSupabaseRentalRepository(sbClient *supabase.Client, options ...RentalRepositoryKeys) domain.RentalRepository {
	var keys RentalRepositoryKeys
	if len(options) > 0 {
		keys = options[0]
	}
	return &supabaseRentalRepository{
		client: sbClient, storage: newStorageClient(sbClient, keys.ServiceRole),
		promptPayKey: keys.PromptPayEncryption,
	}
}

func (r *supabaseRentalRepository) CreateRental(
	ctx context.Context,
	userID string,
	request domain.CreateRentalRequest,
) (*domain.RentalOrder, error) {
	if request.ConversationID != "" {
		var rental domain.RentalOrder
		params := map[string]any{
			"p_renter": userID, "p_conversation": request.ConversationID,
			"p_item_id": request.ItemID, "p_start_at": request.StartAt.UTC(), "p_end_at": request.EndAt.UTC(),
			"p_rental_type": request.RentalType, "p_pickup_location": request.PickupLocation,
			"p_payment_method": request.PaymentMethod, "p_expected_unit_price": request.UnitPrice,
		}
		if request.QueueMessageID > 0 {
			params["p_queue_message_id"] = request.QueueMessageID
		}
		if err := r.client.DB.Rpc("create_chat_rental_request", params).ExecuteWithContext(ctx, &rental); err != nil {
			return nil, mapRentalRepositoryError("create chat rental request", err)
		}
		return &rental, nil
	}
	if request.OfferMessageID != "" {
		return r.processChatOffer(ctx, userID, request, false, "")
	}
	return r.createRental(ctx, userID, request)
}

func (r *supabaseRentalRepository) createRental(ctx context.Context, userID string, request domain.CreateRentalRequest) (*domain.RentalOrder, error) {
	var rental domain.RentalOrder
	params := map[string]interface{}{
		"p_user_id":         userID,
		"p_item_id":         request.ItemID,
		"p_start_at":        request.StartAt.UTC(),
		"p_end_at":          request.EndAt.UTC(),
		"p_rental_type":     request.RentalType,
		"p_pickup_location": strings.TrimSpace(request.PickupLocation),
	}
	if request.OfferMessageID != "" {
		params["p_offer_message_id"] = request.OfferMessageID
	}
	rpc := "create_rental_request"
	if request.QueueMessageID > 0 {
		rpc = "create_queued_rental_request"
		params["p_queue_message_id"] = request.QueueMessageID
	}
	err := r.client.DB.Rpc(rpc, params).ExecuteWithContext(ctx, &rental)
	if err != nil {
		return nil, mapRentalRepositoryError("create rental request", err)
	}
	return &rental, nil
}

func (r *supabaseRentalRepository) UpdateRentalStatus(
	ctx context.Context,
	userID string,
	rentalID int64,
	targetStatus string,
) (*domain.RentalOrder, error) {
	return nil, domain.ErrRentalStatusTransition
}

func mapRentalRepositoryError(operation string, err error) error {
	err = mapRentalVerificationError(err)
	var requestErr *postgrest.RequestError
	if !errors.As(err, &requestErr) {
		return fmt.Errorf("%s: %w", operation, err)
	}

	message := strings.ToLower(requestErr.Message)
	switch {
	case message == "item_rental_occupied",
		requestErr.Code == "23505" && strings.Contains(message, "booking_tb_one_open_rental_per_item"):
		return domain.ErrItemRentalOccupied
	case requestErr.Code == "23P01", strings.Contains(message, "rental period is unavailable"),
		strings.Contains(message, "item is unavailable"):
		return domain.ErrRentalUnavailable
	case strings.Contains(message, "booking not found"):
		return domain.ErrRentalNotFound
	case message == "rental_forbidden":
		return domain.ErrRentalForbidden
	case message == "rental_transition":
		return domain.ErrRentalStatusTransition
	case message == "rental_request_expired", message == "rental_not_started":
		return domain.ErrRentalRequestExpired
	case message == "rental_price_changed":
		return domain.ErrRentalPriceChanged
	case requestErr.Code == "22023":
		return domain.ErrInvalidRental
	default:
		return fmt.Errorf("%s: %w", operation, err)
	}
}
