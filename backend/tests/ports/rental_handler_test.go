package ports_test

import (
	"context"
	"encoding/json"
	"errors"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	ports "github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
)

type rentalConfirmationVerifier struct{}

func (rentalConfirmationVerifier) UserIDFromToken(_ context.Context, token string) (string, error) {
	if token != "renter-token" {
		return "", errors.New("invalid token")
	}
	return "renter", nil
}

type rentalConfirmationRepository struct {
	domain.RentalRepository
	calls int
	err   error
}

func (r *rentalConfirmationRepository) ConfirmRental(_ context.Context, userID string, id int64, messageID string) (*domain.RentalOrder, error) {
	r.calls++
	if userID != "renter" || id != 25 || messageID != "11" {
		return nil, domain.ErrInvalidRental
	}
	if r.err != nil {
		return nil, r.err
	}
	return &domain.RentalOrder{ID: id, Status: "confirmed"}, nil
}

func TestFinalRentalConfirmationHTTPContract(t *testing.T) {
	for _, tc := range []struct {
		name, path, body, token string
		err                     error
		status, calls           int
	}{
		{"confirm", "/api/rentals/25/confirm", `{"offer_message_id":" 11 "}`, "renter-token", nil, 200, 1},
		{"missing auth", "/api/rentals/25/confirm", `{"offer_message_id":"11"}`, "", nil, 401, 0},
		{"invalid token", "/api/rentals/25/confirm", `{"offer_message_id":"11"}`, "invalid", nil, 401, 0},
		{"invalid id", "/api/rentals/0/confirm", `{"offer_message_id":"11"}`, "renter-token", nil, 400, 0},
		{"missing offer", "/api/rentals/25/confirm", `{}`, "renter-token", nil, 400, 0},
		{"blank offer", "/api/rentals/25/confirm", `{"offer_message_id":" "}`, "renter-token", nil, 400, 0},
		{"forbidden", "/api/rentals/25/confirm", `{"offer_message_id":"11"}`, "renter-token", domain.ErrRentalForbidden, 403, 1},
		{"changed offer", "/api/rentals/25/confirm", `{"offer_message_id":"11"}`, "renter-token", domain.ErrInvalidRental, 400, 1},
		{"cancelled", "/api/rentals/25/confirm", `{"offer_message_id":"11"}`, "renter-token", domain.ErrRentalStatusTransition, 409, 1},
	} {
		t.Run(tc.name, func(t *testing.T) {
			repository := &rentalConfirmationRepository{err: tc.err}
			app := ports.NewHTTPApp()
			defer app.Shutdown()
			app.Post("/api/rentals/:id/confirm", ports.NewRentalHandler(repository, rentalConfirmationVerifier{}).ConfirmRentalOrder)
			request := httptest.NewRequest("POST", tc.path, strings.NewReader(tc.body))
			request.Header.Set("Content-Type", "application/json")
			if tc.token != "" {
				request.Header.Set("Authorization", "Bearer "+tc.token)
			}
			response, err := app.Test(request)
			if err != nil {
				t.Fatal(err)
			}
			defer response.Body.Close()
			if response.StatusCode != tc.status || repository.calls != tc.calls {
				t.Fatalf("status=%d want=%d calls=%d want=%d", response.StatusCode, tc.status, repository.calls, tc.calls)
			}
			if tc.status == 200 {
				var result domain.RentalOrder
				if err := json.NewDecoder(response.Body).Decode(&result); err != nil || result.ID != 25 || result.Status != "confirmed" {
					t.Fatalf("result=%v err=%v", result, err)
				}
			}
		})
	}
}
