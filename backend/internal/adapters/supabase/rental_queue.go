package supabase

import (
	"context"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

func (r *supabaseRentalRepository) RentalQueue(ctx context.Context, actor string, request domain.RentalQueueRequest) (domain.RentalQueueResult, error) {
	params := map[string]any{
		"p_actor":        actor,
		"p_conversation": request.ConversationID,
		"p_action":       request.Action,
	}
	if request.ItemID > 0 {
		params["p_item_id"] = request.ItemID
	}
	if request.MessageID > 0 {
		params["p_message_id"] = request.MessageID
	}
	var result domain.RentalQueueResult
	err := r.client.DB.Rpc("rental_queue_action", params).ExecuteWithContext(ctx, &result)
	if err != nil {
		return result, rentalLifecycleError(err)
	}
	return result, nil
}

func (r *supabaseRentalRepository) ConfirmRentalReceiptWithPause(ctx context.Context, actor string, id int64) (*domain.RentalOrder, error) {
	var result map[string]any
	err := r.client.DB.Rpc("confirm_rental_receipt_with_pause", map[string]any{
		"p_actor": actor, "p_booking": id,
	}).ExecuteWithContext(ctx, &result)
	if err != nil {
		return nil, rentalLifecycleError(err)
	}
	return rentalOrderFromAction(result)
}
