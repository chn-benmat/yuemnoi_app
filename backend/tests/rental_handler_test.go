package tests

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	"github.com/gofiber/fiber/v3"
)

const rentalTestUserID = "6df692ac-40b7-4f6d-9ca1-081cf31888c9"

type rentalRepositoryMock struct {
	rental           *domain.RentalOrder
	err              error
	receivedUserID   string
	received         domain.CreateRentalRequest
	receivedRentalID int64
	receivedStatus   string
}

func (m *rentalRepositoryMock) CreateRental(
	_ context.Context,
	userID string,
	request domain.CreateRentalRequest,
) (*domain.RentalOrder, error) {
	m.receivedUserID = userID
	m.received = request
	if m.err != nil {
		return nil, m.err
	}
	return m.rental, nil
}

func (m *rentalRepositoryMock) UpdateRentalStatus(
	_ context.Context,
	userID string,
	rentalID int64,
	targetStatus string,
) (*domain.RentalOrder, error) {
	m.receivedUserID = userID
	m.receivedRentalID = rentalID
	m.receivedStatus = targetStatus
	if m.err != nil {
		return nil, m.err
	}
	return m.rental, nil
}

type rentalTokenVerifier struct {
	err error
}

func (v rentalTokenVerifier) UserIDFromToken(context.Context, string) (string, error) {
	if v.err != nil {
		return "", v.err
	}
	return rentalTestUserID, nil
}

func newRentalRouter(repository *rentalRepositoryMock, verifier rentalTokenVerifier) *fiber.App {

	router := ports.NewHTTPApp()
	handler := ports.NewRentalHandler(repository, verifier)
	router.Post("/api/rentals", handler.CreateRentalOrder)
	router.Post("/api/rentals/:id/handover", handler.HandoverRental)
	router.Post("/api/rentals/:id/return", handler.ReturnRental)
	return router
}

func validRentalRequest() []byte {
	return []byte(`{"item_id":7,"start_at":"2026-09-05T02:00:00Z","end_at":"2026-09-06T02:00:00Z","rental_type":"daily","pickup_location":" บางแค ","total_price":1}`)
}

func performRentalRequest(t *testing.T, router *fiber.App, body []byte, withToken bool) *httptest.ResponseRecorder {
	request := httptest.NewRequest(http.MethodPost, "/api/rentals", bytes.NewReader(body))
	request.Header.Set("Content-Type", "application/json")
	if withToken {
		request.Header.Set("Authorization", "Bearer valid-token")
	}
	response := httptest.NewRecorder()
	performFiberRequest(t, router, response, request)
	return response
}

func TestCreateRentalRequestUsesAuthenticatedUserAndServerResult(t *testing.T) {
	repository := &rentalRepositoryMock{rental: &domain.RentalOrder{
		ID: 21, UserID: rentalTestUserID, ItemID: 7, TotalPrice: 1500, Status: "pending",
	}}
	response := performRentalRequest(t,
		newRentalRouter(repository, rentalTokenVerifier{}),
		validRentalRequest(),
		true,
	)

	if response.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", response.Code, response.Body.String())
	}
	var rental domain.RentalOrder
	if err := json.Unmarshal(response.Body.Bytes(), &rental); err != nil {
		t.Fatal(err)
	}
	if repository.receivedUserID != rentalTestUserID {
		t.Fatalf("unexpected authenticated user: %s", repository.receivedUserID)
	}
	if repository.received.PickupLocation != "บางแค" {
		t.Fatalf("pickup location was not trimmed: %q", repository.received.PickupLocation)
	}
	if rental.TotalPrice != 1500 || rental.Status != "pending" {
		t.Fatalf("unexpected rental response: %#v", rental)
	}
}

func TestCreateRentalRequestRejectsInvalidPeriod(t *testing.T) {
	repository := &rentalRepositoryMock{}
	body := []byte(`{"item_id":7,"start_at":"2026-09-06T02:00:00Z","end_at":"2026-09-05T02:00:00Z","rental_type":"daily","pickup_location":"บางแค"}`)
	response := performRentalRequest(t,
		newRentalRouter(repository, rentalTokenVerifier{}),
		body,
		true,
	)

	if response.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", response.Code, response.Body.String())
	}
}

func TestCreateRentalRequestMapsUnavailablePeriod(t *testing.T) {
	repository := &rentalRepositoryMock{err: domain.ErrRentalUnavailable}
	response := performRentalRequest(t,
		newRentalRouter(repository, rentalTokenVerifier{}),
		validRentalRequest(),
		true,
	)

	if response.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d: %s", response.Code, response.Body.String())
	}
}

func TestCreateRentalRequestRequiresAuthentication(t *testing.T) {
	repository := &rentalRepositoryMock{}
	response := performRentalRequest(t,
		newRentalRouter(repository, rentalTokenVerifier{err: errors.New("invalid token")}),
		validRentalRequest(),
		false,
	)

	if response.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d: %s", response.Code, response.Body.String())
	}
}

func TestHandoverRentalUpdatesStatusToActive(t *testing.T) {
	repository := &rentalRepositoryMock{rental: &domain.RentalOrder{
		ID: 21, UserID: rentalTestUserID, ItemID: 7, TotalPrice: 1500, Status: "active",
	}}
	router := newRentalRouter(repository, rentalTokenVerifier{})

	request := httptest.NewRequest(http.MethodPost, "/api/rentals/21/handover", nil)
	request.Header.Set("Authorization", "Bearer valid-token")
	response := httptest.NewRecorder()
	performFiberRequest(t, router, response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", response.Code, response.Body.String())
	}
	if repository.receivedUserID != rentalTestUserID || repository.receivedRentalID != 21 || repository.receivedStatus != "active" {
		t.Fatalf("unexpected parameters: userID=%s, rentalID=%d, status=%s", repository.receivedUserID, repository.receivedRentalID, repository.receivedStatus)
	}
}

func TestReturnRentalUpdatesStatusToCompleted(t *testing.T) {
	repository := &rentalRepositoryMock{rental: &domain.RentalOrder{
		ID: 21, UserID: rentalTestUserID, ItemID: 7, TotalPrice: 1500, Status: "completed",
	}}
	router := newRentalRouter(repository, rentalTokenVerifier{})

	request := httptest.NewRequest(http.MethodPost, "/api/rentals/21/return", nil)
	request.Header.Set("Authorization", "Bearer valid-token")
	response := httptest.NewRecorder()
	performFiberRequest(t, router, response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", response.Code, response.Body.String())
	}
	if repository.receivedUserID != rentalTestUserID || repository.receivedRentalID != 21 || repository.receivedStatus != "completed" {
		t.Fatalf("unexpected parameters: userID=%s, rentalID=%d, status=%s", repository.receivedUserID, repository.receivedRentalID, repository.receivedStatus)
	}
}

func TestUpdateRentalStatusErrorMappings(t *testing.T) {
	tests := []struct {
		name         string
		repoErr      error
		expectedCode int
	}{
		{"not found", domain.ErrRentalNotFound, http.StatusNotFound},
		{"forbidden", domain.ErrRentalForbidden, http.StatusForbidden},
		{"invalid transition", domain.ErrRentalStatusTransition, http.StatusConflict},
		{"internal error", errors.New("db error"), http.StatusInternalServerError},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			repository := &rentalRepositoryMock{err: tc.repoErr}
			router := newRentalRouter(repository, rentalTokenVerifier{})

			request := httptest.NewRequest(http.MethodPost, "/api/rentals/21/handover", nil)
			request.Header.Set("Authorization", "Bearer valid-token")
			response := httptest.NewRecorder()
			performFiberRequest(t, router, response, request)

			if response.Code != tc.expectedCode {
				t.Fatalf("expected %d, got %d: %s", tc.expectedCode, response.Code, response.Body.String())
			}
		})
	}
}
