package supabase

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

func (r *supabaseItemRepository) requireItemOwner(ctx context.Context, id int64, userID string) error {
	var items []struct {
		ID int64 `json:"id"`
	}
	err := r.client.DB.From("item_tb").Select("id").Eq("id", strconv.FormatInt(id, 10)).Eq("user_id", userID).ExecuteWithContext(ctx, &items)
	if err != nil {
		return fmt.Errorf("find auto-reply item owner: %w", err)
	}
	if len(items) == 0 {
		return domain.ErrItemNotFound
	}
	return nil
}

func (r *supabaseItemRepository) GetAutoReply(ctx context.Context, id int64, userID string) (*domain.ItemAutoReply, error) {
	if err := r.requireItemOwner(ctx, id, userID); err != nil {
		return nil, err
	}
	var rows []domain.ItemAutoReply
	err := r.client.DB.From("item_auto_reply_tb").Select("enabled", "message").Eq("item_id", strconv.FormatInt(id, 10)).ExecuteWithContext(ctx, &rows)
	if err != nil {
		return nil, fmt.Errorf("read item auto-reply: %w", err)
	}
	if len(rows) == 0 {
		return &domain.ItemAutoReply{}, nil
	}
	return &rows[0], nil
}

func (r *supabaseItemRepository) SaveAutoReply(ctx context.Context, id int64, userID string, settings domain.ItemAutoReply) (*domain.ItemAutoReply, error) {
	if err := r.requireItemOwner(ctx, id, userID); err != nil {
		return nil, err
	}
	var rows []domain.ItemAutoReply
	err := r.client.DB.From("item_auto_reply_tb").Upsert(map[string]interface{}{
		"item_id": id, "enabled": settings.Enabled, "message": settings.Message, "updated_at": time.Now().UTC(),
	}).ExecuteWithContext(ctx, &rows)
	if err != nil {
		return nil, fmt.Errorf("save item auto-reply: %w", err)
	}
	if len(rows) == 0 {
		return nil, fmt.Errorf("save item auto-reply returned no row")
	}
	return &rows[0], nil
}
