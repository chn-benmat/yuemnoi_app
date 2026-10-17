package supabase

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/nedpals/supabase-go"
	postgrest "github.com/nedpals/supabase-go/postgrest/pkg"
)

type supabaseRentalRepository struct {
	client *supabase.Client
}

func NewSupabaseRentalRepository(sbClient *supabase.Client) domain.RentalRepository {
	return &supabaseRentalRepository{client: sbClient}
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
	err := r.client.DB.Rpc("create_rental_request", map[string]interface{}{
		"p_user_id":         userID,
		"p_item_id":         request.ItemID,
		"p_start_at":        request.StartAt.UTC(),
		"p_end_at":          request.EndAt.UTC(),
		"p_rental_type":     request.RentalType,
		"p_pickup_location": strings.TrimSpace(request.PickupLocation),
	}).ExecuteWithContext(ctx, &rental)
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
	// 1. ตรวจสอบข้อมูลการจองใน booking_tb
	var bookings []struct {
		ID         int64  `json:"id"`
		UserID     string `json:"user_id"`
		ItemID     int64  `json:"item_id"`
		Status     string `json:"status"`
		TotalPrice int64  `json:"total_price"`
	}

	idStr := strconv.FormatInt(rentalID, 10)
	err := r.client.DB.From("booking_tb").
		Select("id,user_id,item_id,status,total_price").
		Eq("id", idStr).
		ExecuteWithContext(ctx, &bookings)
	if err != nil {
		return nil, fmt.Errorf("load booking failed: %w", err)
	}
	if len(bookings) == 0 {
		return nil, domain.ErrRentalNotFound
	}
	booking := bookings[0]

	// 2. ค้นหาเจ้าของอุปกรณ์
	var items []struct {
		UserID string `json:"user_id"`
	}
	err = r.client.DB.From("item_tb").
		Select("user_id").
		Eq("id", strconv.FormatInt(booking.ItemID, 10)).
		ExecuteWithContext(ctx, &items)
	if err != nil || len(items) == 0 {
		return nil, domain.ErrItemNotFound
	}
	ownerID := items[0].UserID

	// อนุญาตเฉพาะคู่สัญญา (ผู้เช่า หรือเจ้าของอุปกรณ์)
	isRenter := (booking.UserID == userID)
	isOwner := (ownerID == userID)
	if !isRenter && !isOwner {
		return nil, domain.ErrRentalForbidden
	}

	// 3. ตรวจสอบการเปลี่ยนผ่านสถานะ (State Transition Validation)
	// targetStatus "active" (Handover) หรือ "completed" (Return)
	switch targetStatus {
	case "active":
		if booking.Status == "active" || booking.Status == "completed" || booking.Status == "cancelled" {
			return nil, domain.ErrRentalStatusTransition
		}
	case "completed":
		if booking.Status != "active" {
			return nil, domain.ErrRentalStatusTransition
		}
	default:
		return nil, domain.ErrRentalStatusTransition
	}

	// 4. บันทึกสถานะใหม่ลง booking_tb ผ่านสิทธิ์ Backend Service Role
	var updated []domain.RentalOrder
	err = r.client.DB.From("booking_tb").
		Update(map[string]interface{}{
			"status":     targetStatus,
			"updated_at": time.Now().UTC(),
		}).
		Eq("id", idStr).
		ExecuteWithContext(ctx, &updated)
	if err != nil {
		return nil, fmt.Errorf("update booking status failed: %w", err)
	}
	if len(updated) == 0 {
		return nil, domain.ErrRentalNotFound
	}

	return &updated[0], nil
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
