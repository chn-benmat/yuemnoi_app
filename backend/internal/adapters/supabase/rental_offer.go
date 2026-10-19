package supabase

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

const bookingMetaTag = "[BOOKING_DATA:"

func (r *supabaseRentalRepository) ConfirmRental(ctx context.Context, userID string, rentalID int64, offerMessageID string) (*domain.RentalOrder, error) {
	if rentalID <= 0 || strings.TrimSpace(offerMessageID) == "" {
		return nil, domain.ErrInvalidRental
	}
	var bookings []domain.RentalOrder
	if err := r.client.DB.From("booking_tb").Select("*").Eq("id", strconv.FormatInt(rentalID, 10)).ExecuteWithContext(ctx, &bookings); err != nil {
		return nil, fmt.Errorf("load rental to confirm: %w", err)
	}
	if len(bookings) != 1 {
		return nil, domain.ErrRentalNotFound
	}
	rental := bookings[0]
	if rental.UserID != userID {
		return nil, domain.ErrRentalForbidden
	}
	rentalType := rental.RentalType
	switch rentalType {
	case "day", "รายวัน":
		rentalType = "daily"
	case "hour", "รายชั่วโมง":
		rentalType = "hourly"
	}
	// ใช้เงื่อนไขจากรายการที่บันทึกไว้ และตรวจซ้ำกับข้อเสนอของเจ้าของก่อนยืนยัน
	return r.processChatOffer(ctx, userID, domain.CreateRentalRequest{
		ItemID: rental.ItemID, StartAt: rental.StartAt, EndAt: rental.EndAt,
		RentalType: rentalType, PickupLocation: rental.PickupLocation,
		OfferMessageID: strings.TrimSpace(offerMessageID), BookingID: rentalID,
	}, true)
}

func (r *supabaseRentalRepository) processChatOffer(ctx context.Context, userID string, request domain.CreateRentalRequest, confirm bool) (*domain.RentalOrder, error) {
	if id, err := strconv.ParseInt(request.OfferMessageID, 10, 64); err != nil || id <= 0 {
		return nil, domain.ErrInvalidRental
	}
	var messages []struct {
		ID             int64  `json:"id"`
		ConversationID string `json:"conversation_id"`
		SenderID       string `json:"sender_id"`
		Message        string `json:"message"`
	}
	if err := r.client.DB.From("chat_message_tb").Select("id,conversation_id,sender_id,message").Eq("id", request.OfferMessageID).ExecuteWithContext(ctx, &messages); err != nil {
		return nil, fmt.Errorf("load rental offer: %w", err)
	}
	if len(messages) != 1 {
		return nil, domain.ErrRentalNotFound
	}
	message := messages[0]
	start := strings.Index(message.Message, bookingMetaTag)
	end := strings.LastIndex(message.Message, "]")
	if start < 0 || end <= start {
		return nil, domain.ErrInvalidRental
	}
	var meta map[string]json.RawMessage
	if err := json.Unmarshal([]byte(message.Message[start+len(bookingMetaTag):end]), &meta); err != nil {
		return nil, domain.ErrInvalidRental
	}
	var offer struct {
		ItemID      int64  `json:"itemId"`
		RentalType  string `json:"rentalType"`
		StartDate   string `json:"startDate"`
		EndDate     string `json:"endDate"`
		StartHour   int    `json:"startHour"`
		StartMinute int    `json:"startMinute"`
		EndHour     int    `json:"endHour"`
		EndMinute   int    `json:"endMinute"`
		Location    string `json:"location"`
		BookingID   int64  `json:"bookingId"`
	}
	payload, _ := json.Marshal(meta)
	if json.Unmarshal(payload, &offer) != nil || offer.ItemID != request.ItemID {
		return nil, domain.ErrInvalidRental
	}
	var conversations []struct {
		RenterID string `json:"renter_id"`
		OwnerID  string `json:"owner_id"`
	}
	if err := r.client.DB.From("conversation_tb").Select("renter_id,owner_id").Eq("id", message.ConversationID).ExecuteWithContext(ctx, &conversations); err != nil {
		return nil, fmt.Errorf("load offer participants: %w", err)
	}
	var items []struct {
		UserID string `json:"user_id"`
	}
	if err := r.client.DB.From("item_tb").Select("user_id").Eq("id", strconv.FormatInt(offer.ItemID, 10)).ExecuteWithContext(ctx, &items); err != nil {
		return nil, fmt.Errorf("load offer owner: %w", err)
	}
	// ตรวจเจ้าของสินค้าจริงและคู่สนทนา แทนการเชื่อ ownerId ที่ client ใส่ในข้อความ
	if len(items) != 1 || len(conversations) != 1 || items[0].UserID != message.SenderID || userID == message.SenderID {
		return nil, domain.ErrRentalForbidden
	}
	conv := conversations[0]
	if !((conv.RenterID == userID && conv.OwnerID == message.SenderID) || (conv.OwnerID == userID && conv.RenterID == message.SenderID)) {
		return nil, domain.ErrRentalForbidden
	}
	startAt, err := offerTime(offer.StartDate, offer.StartHour, offer.StartMinute)
	if err != nil {
		return nil, domain.ErrInvalidRental
	}
	endHour, endMinute := offer.EndHour, offer.EndMinute
	if offer.RentalType == "daily" {
		endHour, endMinute = offer.StartHour, offer.StartMinute
	}
	endAt, err := offerTime(offer.EndDate, endHour, endMinute)
	if err != nil || !startAt.Equal(request.StartAt) || !endAt.Equal(request.EndAt) || request.RentalType != offer.RentalType || strings.TrimSpace(request.PickupLocation) != strings.TrimSpace(offer.Location) {
		return nil, domain.ErrInvalidRental
	}

	var rental *domain.RentalOrder
	// ปุ่มยืนยันใช้ได้เฉพาะรายการที่ผูกกับข้อเสนอนี้แล้ว ห้ามสร้างหรือสลับเลขรายการในขั้นนี้
	if (confirm && (offer.BookingID <= 0 || offer.BookingID != request.BookingID)) ||
		(offer.BookingID > 0 && request.BookingID > 0 && offer.BookingID != request.BookingID) {
		return nil, domain.ErrInvalidRental
	}
	if offer.BookingID == 0 && request.BookingID > 0 {
		// รองรับรายการเก่าที่บันทึกเลขจองเฉพาะในเครื่อง โดยยังตรวจผู้เช่าและเงื่อนไขจาก DB
		offer.BookingID = request.BookingID
	}
	if offer.BookingID > 0 {
		var bookings []domain.RentalOrder
		if err := r.client.DB.From("booking_tb").Select("*").Eq("id", strconv.FormatInt(offer.BookingID, 10)).ExecuteWithContext(ctx, &bookings); err != nil {
			return nil, fmt.Errorf("load accepted offer: %w", err)
		}
		if len(bookings) != 1 || bookings[0].UserID != userID || bookings[0].ItemID != request.ItemID {
			return nil, domain.ErrRentalForbidden
		}
		rental = &bookings[0]
		if !rental.StartAt.Equal(request.StartAt) || !rental.EndAt.Equal(request.EndAt) || strings.TrimSpace(rental.PickupLocation) != strings.TrimSpace(request.PickupLocation) {
			return nil, domain.ErrInvalidRental
		}
		typeMatches := (request.RentalType == "daily" && (rental.RentalType == "daily" || rental.RentalType == "day" || rental.RentalType == "รายวัน")) ||
			(request.RentalType == "hourly" && (rental.RentalType == "hourly" || rental.RentalType == "hour" || rental.RentalType == "รายชั่วโมง"))
		if !typeMatches {
			return nil, domain.ErrInvalidRental
		}
	} else {
		rental, err = r.createRental(ctx, userID, request)
		if err != nil {
			return nil, err
		}
		meta["bookingId"] = json.RawMessage(strconv.FormatInt(rental.ID, 10))
		meta["status"] = json.RawMessage(`"pending"`)
		// ผูกเลขรายการก่อนเปลี่ยนสถานะ เพื่อให้ retry กลับมาทำรายการเดิมได้
		updatedMessage, publishErr := r.saveOfferMetadata(ctx, request.OfferMessageID, message.Message, meta)
		if publishErr != nil {
			var deleted []domain.RentalOrder
			_ = r.client.DB.From("booking_tb").Delete().Eq("id", strconv.FormatInt(rental.ID, 10)).Eq("status", "pending").ExecuteWithContext(ctx, &deleted)
			return nil, publishErr
		}
		message.Message = updatedMessage
	}
	if confirm && rental.Status == "pending" {
		var updated []domain.RentalOrder
		if err := r.client.DB.From("booking_tb").Update(map[string]any{"status": "confirmed", "updated_at": time.Now().UTC(), "notification_actor_id": userID}).Eq("id", strconv.FormatInt(rental.ID, 10)).Eq("status", "pending").ExecuteWithContext(ctx, &updated); err != nil {
			return nil, fmt.Errorf("confirm accepted offer: %w", err)
		}
		if len(updated) != 1 {
			return nil, domain.ErrRentalStatusTransition
		}
		rental = &updated[0]
	}
	if rental.Status != "pending" && rental.Status != "confirmed" && rental.Status != "active" && rental.Status != "completed" {
		return nil, domain.ErrRentalStatusTransition
	}
	meta["bookingId"] = json.RawMessage(strconv.FormatInt(rental.ID, 10))
	meta["status"], _ = json.Marshal(rental.Status)
	if _, err := r.saveOfferMetadata(ctx, request.OfferMessageID, message.Message, meta); err != nil {
		return nil, err
	}
	return rental, nil
}

func (r *supabaseRentalRepository) saveOfferMetadata(ctx context.Context, messageID, original string, meta map[string]json.RawMessage) (string, error) {
	start, end := strings.Index(original, bookingMetaTag), strings.LastIndex(original, "]")
	payload, err := json.Marshal(meta)
	if err != nil {
		return "", err
	}
	text := original[:start+len(bookingMetaTag)] + string(payload) + original[end:]
	var updated []map[string]any
	// หยุดถ้าเจ้าของแก้ข้อเสนอไปแล้วระหว่างยืนยัน ไม่เขียนทับข้อเสนอใหม่
	// SDK รุ่นนี้ถอด URL encoding ก่อนส่ง จึงต้องเข้ารหัส filter ข้อความไว้เองอีกชั้น
	// eq ใช้ข้อความตรงตัว การครอบอัญประกาศจะทำให้ค้นข้อความเดิมไม่พบ
	filter := url.QueryEscape(original)
	if err := r.client.DB.From("chat_message_tb").Update(map[string]any{"message": text}).Eq("id", messageID).Filter("message", "eq", filter).ExecuteWithContext(ctx, &updated); err != nil {
		return "", fmt.Errorf("publish accepted offer: %w", err)
	}
	if len(updated) != 1 {
		return "", domain.ErrInvalidRental
	}
	saved, ok := updated[0]["message"].(string)
	if !ok {
		return "", domain.ErrInvalidRental
	}
	return saved, nil
}

func offerTime(raw string, hour, minute int) (time.Time, error) {
	if len(raw) < 10 || hour < 0 || hour > 23 || minute < 0 || minute > 59 {
		return time.Time{}, domain.ErrInvalidRental
	}
	zone := time.FixedZone("Asia/Bangkok", 7*60*60)
	day, err := time.ParseInLocation("2006-01-02", raw[:10], zone)
	if err != nil {
		return time.Time{}, err
	}
	return day.Add(time.Duration(hour)*time.Hour + time.Duration(minute)*time.Minute), nil
}
