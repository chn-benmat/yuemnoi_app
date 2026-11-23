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
	client     *supabase.Client
	storage    *storageClient
	codePepper string
}

func NewSupabaseRentalRepository(sbClient *supabase.Client, serviceKeys ...string) domain.RentalRepository {
	key := ""
	if len(serviceKeys) > 0 {
		key = serviceKeys[0]
	}
	return &supabaseRentalRepository{client: sbClient, storage: newStorageClient(sbClient, key), codePepper: key}
}

func (r *supabaseRentalRepository) CreateRental(
	ctx context.Context,
	userID string,
	request domain.CreateRentalRequest,
) (*domain.RentalOrder, error) {
	if request.OfferMessageID != "" {
		return r.processChatOffer(ctx, userID, request, false)
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
	if targetStatus != "active" {
		return nil, domain.ErrRentalStatusTransition
	}
	return nil, domain.ErrRentalHandoverCode
}

func (r *supabaseRentalRepository) CompleteHandover(ctx context.Context, userID string, rentalID int64, handoverCode string) (*domain.RentalOrder, error) {
	if r.codePepper == "" {
		return nil, fmt.Errorf("handover code secret is not configured")
	}
	if len(handoverCode) != 6 || strings.Trim(handoverCode, "0123456789") != "" {
		return nil, domain.ErrRentalHandoverCode
	}
	digest := r.handoverCodeDigest(rentalID, handoverCode)
	var result map[string]any
	err := r.client.DB.Rpc("complete_rental_handover_pin", map[string]any{
		"p_actor": userID, "p_booking": rentalID, "p_code_digest": digest,
	}).ExecuteWithContext(ctx, &result)
	if err != nil {
		return nil, rentalLifecycleError(err)
	}
	if result["error"] == "invalid_handover_pin" {
		return nil, domain.ErrRentalHandoverCode
	}
	if result["error"] == "rental_not_started" {
		return nil, domain.ErrRentalNotStarted
	}
	raw, err := json.Marshal(result["booking"])
	if err != nil {
		return nil, err
	}
	var order domain.RentalOrder
	if err = json.Unmarshal(raw, &order); err != nil {
		return nil, err
	}
	if order.ID <= 0 {
		return nil, fmt.Errorf("handover RPC returned no booking")
	}
	return &order, nil
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
