package supabase

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strconv"
	"strings"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/nedpals/supabase-go"
	postgrest "github.com/nedpals/supabase-go/postgrest/pkg"
)

const itemBucket = "item_bk"

// เป็นตัวแทนในการทำงานกับตาราง item_tb และ review_tb
type supabaseItemRepository struct {
	client  *supabase.Client
	storage *storageClient
}

func NewSupabaseItemRepository(sbClient *supabase.Client, serviceKey string) domain.ItemRepository {
	return &supabaseItemRepository{
		client:  sbClient,
		storage: newStorageClient(sbClient, serviceKey),
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
		objectPath := fmt.Sprintf("%s/%d/%d-%d%s", created.UserID, created.ID, time.Now().UnixNano(), index, image.Extension)
		if err := r.uploadItemImage(ctx, objectPath, image); err != nil {
			r.rollbackCreatedItem(ctx, created, paths)
			return nil, err
		}
		paths = append(paths, objectPath)
		urls = append(urls, r.storage.publicURL(itemBucket, objectPath))
	}

	updated, err := r.Update(ctx, created.ID, created.UserID, map[string]interface{}{
		"item_image_url": urls,
		"updated_at":     time.Now().UTC(),
	})
	if err != nil {
		r.rollbackCreatedItem(ctx, created, paths)
		return nil, fmt.Errorf("save item image URLs failed: %w", err)
	}
	return updated, nil
}

func (r *supabaseItemRepository) uploadItemImage(ctx context.Context, path string, image domain.ItemImage) error {
	if err := r.storage.upload(ctx, itemBucket, path, image.Data, image.ContentType); err != nil {
		return fmt.Errorf("item image upload failed: %w", err)
	}
	return nil
}

func (r *supabaseItemRepository) rollbackCreatedItem(ctx context.Context, item *domain.Item, paths []string) {
	cleanupCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), storageCleanupTimeout)
	defer cancel()
	// ลบแถวให้สำเร็จก่อน เพื่อไม่ให้ข้อมูลที่ยังอ้างอิงอยู่ชี้ไปยังไฟล์ที่ถูกลบ
	err := r.client.DB.From("item_tb").Delete().
		Eq("id", strconv.FormatInt(item.ID, 10)).Eq("user_id", item.UserID).
		ExecuteWithContext(cleanupCtx, nil)
	if err != nil {
		slog.Warn("ย้อนกลับรายการอุปกรณ์ที่สร้างไม่สำเร็จไม่ได้")
		return
	}
	if len(paths) > 0 {
		if err := r.storage.remove(cleanupCtx, itemBucket, paths); err != nil {
			slog.Warn("ลบรูปอุปกรณ์หลังบันทึกไม่สำเร็จไม่ได้")
		}
	}
}

// FindAll ดึงฟีดอุปกรณ์ที่จัดอันดับแล้ว พร้อมข้อมูลเจ้าของ
func (r *supabaseItemRepository) FindAll(ctx context.Context) ([]domain.RankedItem, error) {
	var items []domain.RankedItem

	// อ่านจาก view ที่คำนวณคะแนนฟีดและลำดับไว้แล้ว โดยไม่ส่งคะแนนภายในออก API
	err := r.client.DB.From("home_feed_ranked_v").
		Select(
			"id",
			"user_id",
			"item_name",
			"item_image_url",
			"description",
			"category",
			"price",
			"status",
			"type",
			"created_at",
			"updated_at",
			"rating",
			"review_count",
			"paid_booking_count",
		).
		OrderBy("rank_position", "asc").
		ExecuteWithContext(ctx, &items)
	if err != nil {
		return nil, fmt.Errorf("supabase find all failed: %w", err)
	}

	if len(items) > 0 {
		var profiles []struct {
			UserID       string `json:"user_id"`
			DisplayName  string `json:"display_name"`
			UserImageURL string `json:"user_image_url"`
			IsVerified   bool   `json:"is_verified"`
		}
		_ = r.client.DB.From("public_profile_v").Select("user_id,display_name,user_image_url,is_verified").ExecuteWithContext(ctx, &profiles)
		for i := range items {
			items[i].OwnerName = "ผู้ใช้งาน"
			for _, p := range profiles {
				if p.UserID == items[i].UserID {
					items[i].OwnerName = p.DisplayName
					items[i].OwnerAvatarURL = p.UserImageURL
					items[i].IsVerified = p.IsVerified
					break
				}
			}
		}
	}

	return items, nil
}

// FindByID ดึงข้อมูลอุปกรณ์เช่าตาม ID จากตาราง item_tb พร้อมข้อมูลเจ้าของ
func (r *supabaseItemRepository) FindByID(ctx context.Context, id int64) (*domain.Item, error) {
	var items []domain.Item

	err := r.client.DB.From("item_tb").Select("*").Eq("id", strconv.FormatInt(id, 10)).Eq("moderation_hidden", "false").ExecuteWithContext(ctx, &items)
	if err != nil {
		return nil, fmt.Errorf("supabase find by id failed: %w", err)
	}

	if len(items) == 0 {
		return nil, domain.ErrItemNotFound
	}

	item := &items[0]
	var profiles []struct {
		DisplayName  string `json:"display_name"`
		UserImageURL string `json:"user_image_url"`
		IsVerified   bool   `json:"is_verified"`
	}
	_ = r.client.DB.From("public_profile_v").Select("display_name,user_image_url,is_verified").Eq("user_id", item.UserID).ExecuteWithContext(ctx, &profiles)
	item.OwnerName = "ผู้ใช้งาน"
	if len(profiles) > 0 {
		item.OwnerName = profiles[0].DisplayName
		item.OwnerAvatarURL = profiles[0].UserImageURL
		item.IsVerified = profiles[0].IsVerified
	}

	return item, nil
}

func (r *supabaseItemRepository) HasRentalAccess(ctx context.Context, id int64, userID string) (bool, error) {
	var bookings []struct {
		ID int64 `json:"id"`
	}
	err := r.client.DB.From("booking_tb").Select("id").Limit(1).
		Eq("item_id", strconv.FormatInt(id, 10)).Eq("user_id", userID).
		ExecuteWithContext(ctx, &bookings)
	if err != nil {
		return false, fmt.Errorf("check item rental access failed: %w", err)
	}
	return len(bookings) > 0, nil
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

	// ลบไฟล์รูปภาพใน Storage (item_bk) หลังจากลบข้อมูลในฐานข้อมูลสำเร็จ
	if len(ownedItems[0].ItemImageURL) > 0 {
		var pathsToDelete []string
		for _, rawURL := range ownedItems[0].ItemImageURL {
			if idx := strings.Index(rawURL, "/item_bk/"); idx != -1 {
				pathsToDelete = append(pathsToDelete, rawURL[idx+len("/item_bk/"):])
			}
		}
		if len(pathsToDelete) > 0 {
			cleanupCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), storageCleanupTimeout)
			defer cancel()
			if err := r.storage.remove(cleanupCtx, itemBucket, pathsToDelete); err != nil {
				slog.Warn("ลบไฟล์รูปของอุปกรณ์ที่ลบแล้วไม่สำเร็จ")
			}
		}
	}

	return nil
}
