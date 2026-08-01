package supabase

import (
	"context"
	"errors"
	"fmt"
	"strconv"

	"github.com/Chanachai04/yuemnoi_app/backend/internal/domain"
	"github.com/nedpals/supabase-go"
	postgrest "github.com/nedpals/supabase-go/postgrest/pkg"
)

// เป็นตัวแทนในการทำงานกับตาราง item_tb และ review_tb
type SupabaseItemRepository struct {
	client *supabase.Client
}

func NewSupabaseItemRepository(sbClient *supabase.Client) domain.ItemRepository {
	return &SupabaseItemRepository{
		client: sbClient,
	}
}

// Insert เพิ่มข้อมูลอุปกรณ์เช่าใหม่ลงในตาราง item_tb
func (r *SupabaseItemRepository) Insert(ctx context.Context, item *domain.Item) (*domain.Item, error) {
	var items []domain.Item
	payload := map[string]interface{}{
		"user_id":     item.UserID,
		"item_name":   item.ItemName,
		"description": item.Description,
		"category":    item.Category,
		"price":       item.Price,
		"status":      item.Status,
		"type":        item.Type,
	}
	if item.ItemImageURL != nil {
		payload["item_image_url"] = item.ItemImageURL
	}

	err := r.client.DB.From("item_tb").Insert(payload).ExecuteWithContext(ctx, &items)
	if err != nil {
		return nil, fmt.Errorf("supabase insert failed: %w", err)
	}
	if len(items) == 0 {
		return nil, fmt.Errorf("supabase insert returned no item")
	}

	return &items[0], nil
}

// FindAll ดึงข้อมูลอุปกรณ์เช่าทั้งหมดจากตาราง item_tb
func (r *SupabaseItemRepository) FindAll(ctx context.Context) ([]domain.Item, error) {
	var items []domain.Item

	// ดึงข้อมูล ระบุตาราง "item_tb"
	err := r.client.DB.From("item_tb").Select("*").ExecuteWithContext(ctx, &items)
	if err != nil {
		return nil, fmt.Errorf("supabase find all failed: %w", err)
	}

	return items, nil
}

// FindByID ดึงข้อมูลอุปกรณ์เช่าตาม ID จากตาราง item_tb
func (r *SupabaseItemRepository) FindByID(ctx context.Context, id int64) (*domain.Item, error) {
	var items []domain.Item

	err := r.client.DB.From("item_tb").Select("*").Eq("id", strconv.FormatInt(id, 10)).ExecuteWithContext(ctx, &items)
	if err != nil {
		return nil, fmt.Errorf("supabase find by id failed: %w", err)
	}

	if len(items) == 0 {
		return nil, domain.ErrItemNotFound
	}

	return &items[0], nil
}

func (r *SupabaseItemRepository) Update(
	ctx context.Context,
	id int64,
	userID string,
	fields map[string]interface{},
) (*domain.Item, error) {
	var items []domain.Item

	err := r.client.DB.From("item_tb").
		Update(fields).
		Eq("id", strconv.FormatInt(id, 10)).
		Eq("user_id", userID).
		ExecuteWithContext(ctx, &items)
	if err != nil {
		return nil, fmt.Errorf("supabase update failed: %w", err)
	}
	if len(items) == 0 {
		return nil, domain.ErrItemNotFound
	}

	return &items[0], nil
}

func (r *SupabaseItemRepository) Delete(ctx context.Context, id int64, userID string) error {
	var ownedItems []domain.Item
	idValue := strconv.FormatInt(id, 10)

	err := r.client.DB.From("item_tb").
		Select("*").
		Eq("id", idValue).
		Eq("user_id", userID).
		ExecuteWithContext(ctx, &ownedItems)
	if err != nil {
		return fmt.Errorf("supabase find owned item failed: %w", err)
	}
	if len(ownedItems) == 0 {
		return domain.ErrItemNotFound
	}

	err = r.client.DB.From("item_tb").
		Delete().
		Eq("id", idValue).
		Eq("user_id", userID).
		ExecuteWithContext(ctx, nil)
	if err != nil {
		var requestErr *postgrest.RequestError
		if errors.As(err, &requestErr) && requestErr.Code == "23503" {
			return domain.ErrItemInUse
		}
		return fmt.Errorf("supabase delete failed: %w", err)
	}

	return nil
}
