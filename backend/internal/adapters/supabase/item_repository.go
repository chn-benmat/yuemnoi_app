package supabase

import (
	"context"
	"fmt"

	"github.com/Chanachai04/yuemnoi_app/backend/internal/domain"
	"github.com/nedpals/supabase-go"
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
func (r *SupabaseItemRepository) Insert(ctx context.Context, item *domain.Item) error {
	var result []map[string]interface{}

	err := r.client.DB.From("item_tb").Insert(item).Execute(&result)
	if err != nil {
		return fmt.Errorf("supabase insert failed: %w", err)
	}

	return nil
}

// FindAll ดึงข้อมูลอุปกรณ์เช่าทั้งหมดจากตาราง item_tb
func (r *SupabaseItemRepository) FindAll(ctx context.Context) ([]domain.Item, error) {
	var items []domain.Item

	// ดึงข้อมูล ระบุตาราง "item_tb"
	err := r.client.DB.From("item_tb").Select("*").Execute(&items)
	if err != nil {
		return nil, fmt.Errorf("supabase find all failed: %w", err)
	}

	return items, nil
}

// FindByID ดึงข้อมูลอุปกรณ์เช่าตาม ID จากตาราง item_tb
func (r *SupabaseItemRepository) FindByID(ctx context.Context, id string) (*domain.Item, error) {
	var items []domain.Item

	// ดึงข้อมูล ระบุตาราง "item_tb" และเงื่อนไข Where id = ?
	err := r.client.DB.From("item_tb").Select("*").Eq("id", id).Execute(&items)
	if err != nil {
		return nil, fmt.Errorf("supabase find by id failed: %w", err)
	}

	if len(items) == 0 {
		return nil, fmt.Errorf("item with ID %s not found", id)
	}

	return &items[0], nil
}
