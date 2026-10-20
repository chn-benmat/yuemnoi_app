package supabase_test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	supabase "github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	supabaseclient "github.com/nedpals/supabase-go"
)

func TestOwnerOfferStaysPendingUntilExplicitConfirmation(t *testing.T) {
	var sharedMessage string
	createCalls := 0
	persistedStatus := "pending"
	originalMessage := `รายละเอียดคำขอเช่า
[BOOKING_DATA:{"itemId":7,"rentalType":"daily","startDate":"2026-10-18T00:00:00.000","endDate":"2026-10-19T00:00:00.000","startHour":9,"startMinute":0,"endHour":17,"endMinute":0,"location":"Pickup"}]`
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		wantSchema := "public"
		if r.URL.Path == "/rest/v1/chat_message_tb" || r.URL.Path == "/rest/v1/conversation_tb" {
			wantSchema = "messaging"
		}
		for _, header := range []string{"Accept-Profile", "Content-Profile"} {
			if got := r.Header.Get(header); got != wantSchema {
				t.Errorf("%s %s %s = %q, want %q", r.Method, r.URL.Path, header, got, wantSchema)
			}
		}
		switch {
		case r.URL.Path == "/rest/v1/rpc/create_rental_request":
			createCalls++
			var request map[string]any
			if err := json.NewDecoder(r.Body).Decode(&request); err != nil || request["p_offer_message_id"] != "11" {
				t.Errorf("missing authoritative offer snapshot: %v (%v)", request, err)
			}
			fmt.Fprint(w, `{"id":25,"user_id":"renter","item_id":7,"status":"pending"}`)
		case r.URL.Path == "/rest/v1/chat_message_tb" && r.Method == http.MethodGet:
			payload := originalMessage
			if sharedMessage != "" {
				payload = sharedMessage
			}
			json.NewEncoder(w).Encode([]any{map[string]any{"id": 11, "conversation_id": "77777777-7777-4777-8777-777777777777", "sender_id": "owner", "message": payload}})
		case r.URL.Path == "/rest/v1/conversation_tb":
			fmt.Fprint(w, `[{"renter_id":"renter","owner_id":"owner"}]`)
		case r.URL.Path == "/rest/v1/item_tb":
			fmt.Fprint(w, `[{"id":7,"user_id":"owner"}]`)
		case r.URL.Path == "/rest/v1/booking_tb" && r.Method == http.MethodPatch:
			var data map[string]any
			json.NewDecoder(r.Body).Decode(&data)
			if data["status"] != "confirmed" {
				t.Errorf("persisted status = %v", data["status"])
			}
			persistedStatus = "confirmed"
			fmt.Fprint(w, `[{"id":25,"user_id":"renter","item_id":7,"status":"confirmed"}]`)
		case r.URL.Path == "/rest/v1/chat_message_tb" && r.Method == http.MethodPatch:
			currentMessage := sharedMessage
			if currentMessage == "" {
				currentMessage = originalMessage
			}
			// eq เปรียบเทียบกับข้อความจริงทั้งก้อน รวมภาษาไทย บรรทัดใหม่ และเครื่องหมายใน JSON
			if r.URL.Query().Get("message") != "eq."+currentMessage {
				fmt.Fprint(w, `[]`)
				return
			}
			var data map[string]any
			json.NewDecoder(r.Body).Decode(&data)
			sharedMessage, _ = data["message"].(string)
			// จำลอง trigger จัดรูปแบบข้อความใหม่ ต้องใช้ผลที่ DB คืนมาสำหรับ CAS ครั้งถัดไป
			sharedMessage += " "
			json.NewEncoder(w).Encode([]any{map[string]any{"id": 11, "message": sharedMessage}})
		case r.URL.Path == "/rest/v1/booking_tb" && r.Method == http.MethodGet:
			fmt.Fprintf(w, `[{"id":25,"user_id":"renter","item_id":7,"status":%q,"type":"รายวัน","start_at":"2026-10-18T02:00:00Z","end_at":"2026-10-19T02:00:00Z","pickup_location":"Pickup"}]`, persistedStatus)
		case r.URL.Path == "/rest/v1/booking_tb" && r.Method == http.MethodDelete:
			fmt.Fprint(w, `[]`)
		default:
			t.Errorf("unexpected request: %s %s", r.Method, r.URL.Path)
			w.WriteHeader(500)
		}
	}))
	defer server.Close()
	repository := supabase.NewSupabaseRentalRepository(supabaseclient.CreateClient(server.URL, "test-key"))
	var request domain.CreateRentalRequest
	json.Unmarshal([]byte(`{"item_id":7,"rental_type":"daily","pickup_location":"Pickup","offer_message_id":"11"}`), &request)
	request.StartAt = time.Date(2026, 10, 18, 2, 0, 0, 0, time.UTC)
	request.EndAt = time.Date(2026, 10, 19, 2, 0, 0, 0, time.UTC)
	result, err := repository.CreateRental(context.Background(), "renter", request)
	if err != nil {
		t.Fatal(err)
	}
	if result.Status != "pending" || persistedStatus != "pending" {
		t.Errorf("before final confirmation: response=%s database=%s, want pending", result.Status, persistedStatus)
	}
	if !strings.Contains(sharedMessage, `"bookingId":25`) || !strings.Contains(sharedMessage, `"status":"pending"`) {
		t.Errorf("offer must stay pending before final confirmation: %q", sharedMessage)
	}
	result, err = repository.CreateRental(context.Background(), "renter", request)
	if err != nil || result.ID != 25 || createCalls != 1 {
		t.Fatalf("retry created another booking: result=%v err=%v calls=%d", result, err, createCalls)
	}
	if result.Status != "pending" {
		t.Fatalf("reopening the summary confirmed the booking: %s", result.Status)
	}
	for range 2 {
		result, err = repository.ConfirmRental(context.Background(), "renter", 25, "11")
		if err != nil || result.Status != "confirmed" || persistedStatus != "confirmed" || createCalls != 1 {
			t.Fatalf("explicit confirmation/retry: result=%v err=%v status=%s creates=%d", result, err, persistedStatus, createCalls)
		}
		if !strings.Contains(sharedMessage, `"status":"confirmed"`) {
			t.Fatalf("owner did not receive confirmed status: %q", sharedMessage)
		}
	}
	sharedMessage, persistedStatus = "", "pending"
	request.BookingID = 25
	result, err = repository.CreateRental(context.Background(), "renter", request)
	if err != nil || result.ID != 25 || result.Status != "pending" || createCalls != 1 {
		t.Fatalf("legacy booking must stay pending without duplication: result=%v err=%v creates=%d", result, err, createCalls)
	}
}

func TestChatOfferRejectsUnauthorizedOrChangedTermsBeforeCreatingBooking(t *testing.T) {
	for _, tc := range []struct {
		name, caller, sender, location string
		want                           error
	}{
		{"renter cannot originate offer", "renter", "renter", "Pickup", domain.ErrRentalForbidden},
		{"outsider cannot accept offer", "outsider", "owner", "Pickup", domain.ErrRentalForbidden},
		{"owner cannot accept own offer", "owner", "owner", "Pickup", domain.ErrRentalForbidden},
		{"renter cannot change pickup", "renter", "owner", "Changed", domain.ErrInvalidRental},
	} {
		t.Run(tc.name, func(t *testing.T) {
			created := false
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				switch r.URL.Path {
				case "/rest/v1/chat_message_tb":
					payload := `รายละเอียดคำขอเช่า [BOOKING_DATA:{"itemId":7,"rentalType":"daily","startDate":"2026-10-18","endDate":"2026-10-19","startHour":9,"startMinute":0,"endHour":17,"endMinute":0,"location":"Pickup"}]`
					json.NewEncoder(w).Encode([]any{map[string]any{"id": 11, "conversation_id": "77777777-7777-4777-8777-777777777777", "sender_id": tc.sender, "message": payload}})
				case "/rest/v1/conversation_tb":
					fmt.Fprint(w, `[{"renter_id":"renter","owner_id":"owner"}]`)
				case "/rest/v1/item_tb":
					fmt.Fprint(w, `[{"id":7,"user_id":"owner"}]`)
				default:
					created = true
					w.WriteHeader(500)
					fmt.Fprint(w, `{"message":"unexpected mutation"}`)
				}
			}))
			defer server.Close()
			repository := supabase.NewSupabaseRentalRepository(supabaseclient.CreateClient(server.URL, "test-key"))
			request := domain.CreateRentalRequest{ItemID: 7, OfferMessageID: "11", RentalType: "daily", PickupLocation: tc.location,
				StartAt: time.Date(2026, 10, 18, 2, 0, 0, 0, time.UTC), EndAt: time.Date(2026, 10, 19, 2, 0, 0, 0, time.UTC)}
			_, err := repository.CreateRental(context.Background(), tc.caller, request)
			if !errors.Is(err, tc.want) || created {
				t.Fatalf("error=%v, want=%v; mutation=%v", err, tc.want, created)
			}
		})
	}
}

func TestConfirmRentalRejectsWrongParticipantOfferOrStatus(t *testing.T) {
	for _, tc := range []struct {
		name, caller, status, location string
		offerBookingID                 int64
		want                           error
	}{
		{"owner cannot confirm", "owner", "pending", "Pickup", 25, domain.ErrRentalForbidden},
		{"outsider cannot confirm", "outsider", "pending", "Pickup", 25, domain.ErrRentalForbidden},
		{"offer must already link the pending booking", "renter", "pending", "Pickup", 0, domain.ErrInvalidRental},
		{"different booking cannot be confirmed", "renter", "pending", "Pickup", 26, domain.ErrInvalidRental},
		{"changed offer requires review", "renter", "pending", "Changed", 25, domain.ErrInvalidRental},
		{"cancelled cannot be confirmed", "renter", "cancelled", "Pickup", 25, domain.ErrRentalStatusTransition},
	} {
		t.Run(tc.name, func(t *testing.T) {
			mutated := false
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				if r.Method != http.MethodGet {
					mutated = true
					w.WriteHeader(500)
					return
				}
				switch r.URL.Path {
				case "/rest/v1/booking_tb":
					fmt.Fprintf(w, `[{"id":25,"user_id":"renter","item_id":7,"status":%q,"type":"รายวัน","start_at":"2026-10-18T02:00:00Z","end_at":"2026-10-19T02:00:00Z","pickup_location":"Pickup"}]`, tc.status)
				case "/rest/v1/chat_message_tb":
					payload := fmt.Sprintf(`รายละเอียดคำขอเช่า [BOOKING_DATA:{"itemId":7,"rentalType":"daily","startDate":"2026-10-18","endDate":"2026-10-19","startHour":9,"startMinute":0,"location":%q,"bookingId":%d}]`, tc.location, tc.offerBookingID)
					json.NewEncoder(w).Encode([]any{map[string]any{"id": 11, "conversation_id": "77777777-7777-4777-8777-777777777777", "sender_id": "owner", "message": payload}})
				case "/rest/v1/conversation_tb":
					fmt.Fprint(w, `[{"renter_id":"renter","owner_id":"owner"}]`)
				case "/rest/v1/item_tb":
					fmt.Fprint(w, `[{"user_id":"owner"}]`)
				default:
					t.Errorf("unexpected request: %s", r.URL.Path)
					w.WriteHeader(500)
				}
			}))
			defer server.Close()
			repository := supabase.NewSupabaseRentalRepository(supabaseclient.CreateClient(server.URL, "test-key"))
			_, err := repository.ConfirmRental(context.Background(), tc.caller, 25, "11")
			if !errors.Is(err, tc.want) || mutated {
				t.Fatalf("error=%v want=%v mutated=%v", err, tc.want, mutated)
			}
		})
	}
}
