package ports_test

import (
	"context"
	"encoding/json"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
)

type rentalVerificationGateway struct{ domain.AuthGateway }

func (rentalVerificationGateway) AppUserIDFromToken(ctx context.Context, token string) (string, error) {
	return rentalConfirmationVerifier{}.UserIDFromToken(ctx, token)
}

type rentalVerificationStore struct {
	domain.OperationsStore
	t   *testing.T
	raw string
}

func (s rentalVerificationStore) RPC(_ context.Context, name string, args map[string]any) (json.RawMessage, error) {
	s.t.Helper()
	if name != "identity_status" || args["p_actor"] != "renter" {
		s.t.Fatalf("unexpected call %s %v", name, args)
	}
	return json.RawMessage(s.raw), nil
}

func TestNewRentalListingsRequireCardAndContactPhone(t *testing.T) {
	for _, tc := range []struct {
		name, status, code string
		wantStatus         int
		wantVerification   string
	}{
		{"both missing despite disabled setting", `{"enforcement":false,"rental_verification":{"id_card_approved":false,"contact_phone_saved":false,"identity_pending":false}}`, "rental_verification_required", 403, `{"id_card_approved":false,"contact_phone_saved":false,"identity_pending":false}`},
		{"card pending", `{"rental_verification":{"id_card_approved":false,"contact_phone_saved":true,"identity_pending":true}}`, "rental_verification_required", 403, `{"id_card_approved":false,"contact_phone_saved":true,"identity_pending":true}`},
		{"phone missing", `{"rental_verification":{"id_card_approved":true,"contact_phone_saved":false,"identity_pending":false}}`, "rental_verification_required", 403, `{"id_card_approved":true,"contact_phone_saved":false,"identity_pending":false}`},
		{"suspended", `{"control":{"suspended":true},"rental_verification":{"id_card_approved":true,"contact_phone_saved":true}}`, "transaction_restricted", 403, ""},
		{"outdated schema", `{"can_list":true}`, "operations_unavailable", 503, ""},
		{"operations disabled", "", "operations_unavailable", 503, ""},
		{"both complete reaches request validation", `{"rental_verification":{"id_card_approved":true,"contact_phone_saved":true}}`, "", 400, ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			options := domain.OperationsOptions{}
			if tc.status != "" {
				options.Store = rentalVerificationStore{t: t, raw: tc.status}
			}
			app := ports.SetupRouterWithOperations(options, nil, rentalVerificationGateway{}, nil, nil, nil, "test-secret")
			defer app.Shutdown()
			req := httptest.NewRequest("POST", "/api/items", strings.NewReader(`{}`))
			req.Header.Set("Authorization", "Bearer renter-token")
			req.Header.Set("Content-Type", "application/json")
			req.Header.Set("X-App-Secret", "test-secret")
			response, err := app.Test(req)
			if err != nil {
				t.Fatal(err)
			}
			defer response.Body.Close()
			var result struct {
				Code         string          `json:"code"`
				Verification json.RawMessage `json:"rental_verification"`
			}
			if err := json.NewDecoder(response.Body).Decode(&result); err != nil {
				t.Fatal(err)
			}
			if response.StatusCode != tc.wantStatus || result.Code != tc.code || string(result.Verification) != tc.wantVerification {
				t.Fatalf("status=%d code=%q verification=%s", response.StatusCode, result.Code, result.Verification)
			}
		})
	}
}

type existingRentalVerificationRepository struct {
	domain.RentalRepository
	t *testing.T
}

func (r existingRentalVerificationRepository) CreateRental(_ context.Context, userID string, req domain.CreateRentalRequest) (*domain.RentalOrder, error) {
	r.t.Helper()
	if userID != "renter" || req.OfferMessageID != "11" || req.BookingID != 25 {
		r.t.Fatalf("unexpected rental request: %+v", req)
	}
	return &domain.RentalOrder{ID: 25, Status: "pending"}, nil
}

func TestRentalSubmissionCanResumeAnExistingOfferWithIncompleteVerification(t *testing.T) {
	options := domain.OperationsOptions{Store: rentalVerificationStore{
		t: t, raw: `{"rental_verification":{"id_card_approved":false,"contact_phone_saved":false,"identity_pending":false}}`,
	}}
	app := ports.SetupRouterWithOperations(options, nil, rentalVerificationGateway{}, nil, existingRentalVerificationRepository{t: t}, nil, "test-secret")
	defer app.Shutdown()
	req := httptest.NewRequest("POST", "/api/rentals", strings.NewReader(
		`{"item_id":7,"start_at":"2026-11-27T02:00:00Z","end_at":"2026-11-27T03:00:00Z","rental_type":"hourly","pickup_location":"Pickup","offer_message_id":"11","booking_id":25}`,
	))
	req.Header.Set("Authorization", "Bearer renter-token")
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-App-Secret", "test-secret")
	response, err := app.Test(req)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	var rental domain.RentalOrder
	if err := json.NewDecoder(response.Body).Decode(&rental); err != nil || response.StatusCode != 201 || rental.ID != 25 || rental.Status != "pending" {
		t.Fatalf("status=%d booking=%+v err=%v", response.StatusCode, rental, err)
	}
}
