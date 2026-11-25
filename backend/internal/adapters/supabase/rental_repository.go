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
	err := r.client.DB.Rpc("create_rental_request", params).ExecuteWithContext(ctx, &rental)
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
	var requestErr *postgrest.RequestError
	if !errors.As(err, &requestErr) {
		return fmt.Errorf("%s: %w", operation, err)
	}

	message := strings.ToLower(requestErr.Message)
	switch {
	case requestErr.Code == "23P01", strings.Contains(message, "rental period is unavailable"),
		strings.Contains(message, "item is unavailable"):
		return domain.ErrRentalUnavailable
	case strings.Contains(message, "booking not found"):
		return domain.ErrRentalNotFound
	case requestErr.Code == "22023":
		return domain.ErrInvalidRental
	default:
		return fmt.Errorf("%s: %w", operation, err)
	}
}
