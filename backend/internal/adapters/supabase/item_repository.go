package supabase

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/Chanachai04/yuemnoi_app/backend/internal/domain"
	"github.com/nedpals/supabase-go"
	postgrest "github.com/nedpals/supabase-go/postgrest/pkg"
)

const itemBucket = "item_bk"

// เป็นตัวแทนในการทำงานกับตาราง item_tb และ review_tb
type supabaseItemRepository struct {
	client *supabase.Client
}

func NewSupabaseItemRepository(sbClient *supabase.Client) domain.ItemRepository {
	return &supabaseItemRepository{
		client: sbClient,
	}
}

// Insert เพิ่มข้อมูลอุปกรณ์เช่าใหม่ลงในตาราง item_tb
func (r *supabaseItemRepository) Insert(ctx context.Context, item *domain.Item, images []domain.ItemImage) (*domain.Item, error) {
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

	created := &items[0]
	if len(images) == 0 {
		return created, nil
	}

	paths := make([]string, 0, len(images))
	urls := make([]string, 0, len(images))
	for index, image := range images {
		objectPath := fmt.Sprintf("%d/%d-%d%s", created.ID, time.Now().UnixNano(), index, image.Extension)
		if err := r.uploadItemImage(objectPath, image); err != nil {
			r.rollbackCreatedItem(created, paths)
			return nil, err
		}
		paths = append(paths, objectPath)
		urls = append(urls, r.client.Storage.From(itemBucket).GetPublicUrl(objectPath).SignedUrl)
	}

	updated, err := r.Update(ctx, created.ID, created.UserID, map[string]interface{}{
		"item_image_url": urls,
		"updated_at":     time.Now().UTC(),
	})
	if err != nil {
		r.rollbackCreatedItem(created, paths)
		return nil, fmt.Errorf("save item image URLs failed: %w", err)
	}
	return updated, nil
}

func (r *supabaseItemRepository) uploadItemImage(path string, image domain.ItemImage) (err error) {
	defer func() {
		if recovered := recover(); recovered != nil {
			err = fmt.Errorf("item image upload failed: %v", recovered)
		}
	}()

	response := r.client.Storage.From(itemBucket).Upload(
		path,
		bytes.NewReader(image.Data),
		&supabase.FileUploadOptions{
			CacheControl: "3600",
			ContentType:  image.ContentType,
			MimeType:     image.ContentType,
		},
	)
	if response.Key == "" {
		return fmt.Errorf("item image upload failed: %s", response.Message)
	}
	return nil
}

func (r *supabaseItemRepository) rollbackCreatedItem(item *domain.Item, paths []string) {
	if len(paths) > 0 {
		func() {
			defer func() {
				_ = recover()
			}()
			r.client.Storage.From(itemBucket).Remove(paths)
		}()
	}
	_ = r.Delete(context.Background(), item.ID, item.UserID)
}

// FindAll ดึงข้อมูลอุปกรณ์เช่าทั้งหมดจากตาราง item_tb พร้อมข้อมูลเจ้าของ
func (r *supabaseItemRepository) FindAll(ctx context.Context) ([]domain.Item, error) {
	var items []domain.Item

	// ดึงข้อมูล ระบุตาราง "item_tb"
	err := r.client.DB.From("item_tb").Select("*").ExecuteWithContext(ctx, &items)
	if err != nil {
		return nil, fmt.Errorf("supabase find all failed: %w", err)
	}

	if len(items) > 0 {
		var profiles []struct {
			UserID       string `json:"user_id"`
			Email        string `json:"email"`
			UserImageURL string `json:"user_image_url"`
		}
		_ = r.client.DB.From("profile_tb").Select("user_id,email,user_image_url").ExecuteWithContext(ctx, &profiles)
		profilesMap := make(map[string]struct {
			Email        string
			UserImageURL string
		})
		for _, p := range profiles {
			profilesMap[p.UserID] = struct {
				Email        string
				UserImageURL string
			}{Email: p.Email, UserImageURL: p.UserImageURL}
		}

		for i := range items {
			if p, ok := profilesMap[items[i].UserID]; ok {
				ownerName := p.Email
				if idx := strings.Index(ownerName, "@"); idx != -1 {
					ownerName = ownerName[:idx]
				}
				if ownerName == "" {
					ownerName = "Yuemnoi Verified"
				}
				items[i].OwnerName = ownerName
				items[i].OwnerAvatarURL = p.UserImageURL
			} else {
				items[i].OwnerName = "Yuemnoi Verified"
			}
		}
	}

	return items, nil
}

// FindByID ดึงข้อมูลอุปกรณ์เช่าตาม ID จากตาราง item_tb พร้อมข้อมูลเจ้าของ
func (r *supabaseItemRepository) FindByID(ctx context.Context, id int64) (*domain.Item, error) {
	var items []domain.Item

	err := r.client.DB.From("item_tb").Select("*").Eq("id", strconv.FormatInt(id, 10)).ExecuteWithContext(ctx, &items)
	if err != nil {
		return nil, fmt.Errorf("supabase find by id failed: %w", err)
	}

	if len(items) == 0 {
		return nil, domain.ErrItemNotFound
	}

	item := &items[0]
	var profiles []struct {
		UserID       string `json:"user_id"`
		Email        string `json:"email"`
		UserImageURL string `json:"user_image_url"`
	}
	_ = r.client.DB.From("profile_tb").Select("user_id,email,user_image_url").Eq("user_id", item.UserID).ExecuteWithContext(ctx, &profiles)
	if len(profiles) > 0 {
		p := profiles[0]
		ownerName := p.Email
		if idx := strings.Index(ownerName, "@"); idx != -1 {
			ownerName = ownerName[:idx]
		}
		if ownerName == "" {
			ownerName = "Yuemnoi Verified"
		}
		item.OwnerName = ownerName
		item.OwnerAvatarURL = p.UserImageURL
	} else {
		item.OwnerName = "Yuemnoi Verified"
	}

	return item, nil
}

func (r *supabaseItemRepository) Update(
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

func (r *supabaseItemRepository) Delete(ctx context.Context, id int64, userID string) error {
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
