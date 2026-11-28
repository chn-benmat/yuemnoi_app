package supabase

import (
	"context"
	"fmt"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

func (r *supabaseItemRepository) GetAutoReply(ctx context.Context, id int64, userID string) (*domain.ItemAutoReply, error) {
	var rows []domain.ItemAutoReply
	err := r.client.DB.Rpc("get_item_auto_reply", map[string]any{
		"p_item_id": id,
		"p_actor":   userID,
	}).ExecuteWithContext(ctx, &rows)
	if err != nil {
		return nil, fmt.Errorf("read item auto-reply: %w", err)
	}
	if len(rows) == 0 {
		return nil, domain.ErrItemNotFound
	}
	return &rows[0], nil
}

func (r *supabaseItemRepository) SaveAutoReply(ctx context.Context, id int64, userID string, settings domain.ItemAutoReply) (*domain.ItemAutoReply, error) {
	var rows []domain.ItemAutoReply
	err := r.client.DB.Rpc("save_item_auto_reply", map[string]any{
		"p_item_id": id,
		"p_actor":   userID,
		"p_enabled": settings.Enabled,
		"p_message": settings.Message,
	}).ExecuteWithContext(ctx, &rows)
	if err != nil {
		return nil, fmt.Errorf("save item auto-reply: %w", err)
	}
	if len(rows) == 0 {
		return nil, domain.ErrItemNotFound
	}
	return &rows[0], nil
}
