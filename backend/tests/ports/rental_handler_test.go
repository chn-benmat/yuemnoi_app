package ports_test

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
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

func (r *rentalConfirmationRepository) ConfirmRental(_ context.Context, userID string, id int64, messageID, paymentMethod string, _ int) (*domain.RentalOrder, error) {
	r.calls++
	if userID != "renter" || id != 25 || messageID != "11" {
		return nil, domain.ErrInvalidRental
	}
	if r.err != nil {
		return nil, r.err
	}
	return &domain.RentalOrder{ID: id, Status: "confirmed", PaymentMethod: paymentMethod}, nil
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
		{"unsupported payment method", "/api/rentals/25/confirm", `{"offer_message_id":"11","payment_method":"card"}`, "renter-token", nil, 400, 0},
		{"forbidden", "/api/rentals/25/confirm", `{"offer_message_id":"11"}`, "renter-token", domain.ErrRentalForbidden, 403, 1},
		{"changed offer", "/api/rentals/25/confirm", `{"offer_message_id":"11"}`, "renter-token", domain.ErrInvalidRental, 400, 1},
		{"cancelled", "/api/rentals/25/confirm", `{"offer_message_id":"11"}`, "renter-token", domain.ErrRentalStatusTransition, 409, 1},
		{"stale request", "/api/rentals/25/confirm", `{"offer_message_id":"11","request_revision":1}`, "renter-token", domain.ErrRentalRequestChanged, 409, 1},
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

type handoverPaymentVerifier struct{}

func (handoverPaymentVerifier) UserIDFromToken(_ context.Context, token string) (string, error) {
	switch token {
	case "owner", "renter":
		return token, nil
	default:
		return "", errors.New("invalid token")
	}
}

type handoverPaymentRepository struct {
	domain.RentalRepository
	domain.RentalHandoverRepository
	confirmed  bool
	phone      string
	nationalID string
}

func (r *handoverPaymentRepository) HandoverPayment(_ context.Context, userID string, rentalID int64, confirm bool) (domain.RentalHandoverPayment, error) {
	if rentalID != 25 {
		return domain.RentalHandoverPayment{}, domain.ErrRentalNotFound
	}
	if confirm {
		if userID != "owner" {
			return domain.RentalHandoverPayment{}, domain.ErrRentalForbidden
		}
		r.confirmed = true
	}
	payment := domain.RentalHandoverPayment{PaymentMethod: "promptpay", Status: "confirmed", PaymentConfirmed: r.confirmed, TotalSatang: 199950}
	if r.confirmed {
		payment.Status = "active"
	}
	if userID == "owner" && !r.confirmed {
		payment.CanCollectPayment = true
		payment.PromptPayPhone = r.phone
		payment.PromptPayNationalID = r.nationalID
	}
	return payment, nil
}

func (r *handoverPaymentRepository) SavePromptPayAccount(ctx context.Context, userID string, rentalID int64, phone, nationalID string) (domain.RentalHandoverPayment, error) {
	if userID != "owner" {
		return domain.RentalHandoverPayment{}, domain.ErrRentalForbidden
	}
	r.phone, r.nationalID = phone, nationalID
	return r.HandoverPayment(ctx, userID, rentalID, false)
}

func TestHandoverPaymentHTTPContract(t *testing.T) {
	repo := &handoverPaymentRepository{}
	handler := ports.NewRentalHandler(repo, handoverPaymentVerifier{})
	app := ports.NewHTTPApp()
	defer app.Shutdown()
	app.Get("/api/rentals/:id/handover-payment", handler.GetHandoverPayment)
	app.Post("/api/rentals/:id/handover-payment", handler.ConfirmHandoverPayment)
	for _, tc := range []struct {
		method, path, token string
		status              int
		confirmed           bool
	}{
		{http.MethodGet, "handover-payment", "", 401, false},
		{http.MethodGet, "handover-payment", "renter", 200, false},
		{http.MethodPost, "handover-payment", "renter", 403, false},
		{http.MethodPost, "handover-payment", "owner", 200, true},
		{http.MethodGet, "handover-payment", "renter", 200, true},
	} {
		request := httptest.NewRequest(tc.method, "/api/rentals/25/"+tc.path, nil)
		if tc.token != "" {
			request.Header.Set("Authorization", "Bearer "+tc.token)
		}
		response, err := app.Test(request)
		if err != nil {
			t.Fatal(err)
		}
		var payment domain.RentalHandoverPayment
		err = json.NewDecoder(response.Body).Decode(&payment)
		response.Body.Close()
		if response.StatusCode != tc.status {
			t.Fatalf("%s %s (%s): HTTP %d, want %d", tc.method, tc.path, tc.token, response.StatusCode, tc.status)
		}
		wantStatus := "confirmed"
		if tc.confirmed {
			wantStatus = "active"
		}
		if tc.status == 200 && (err != nil || payment.PaymentMethod != "promptpay" || payment.PaymentConfirmed != tc.confirmed || payment.Status != wantStatus) {
			t.Fatalf("%s (%s): unexpected payment %+v, %v", tc.method, tc.token, payment, err)
		}
	}
}

func TestHandoverPromptPayQR(t *testing.T) {
	const path = "/api/rentals/25/handover-payment"
	const phoneQR = "00020101021229370016A00000067701011101130066812345678530376454071999.505802TH63047EDE"
	const nationalIDQR = "00020101021229370016A00000067701011102131234567890121530376454071999.505802TH63046933"
	repo := &handoverPaymentRepository{}
	handler := ports.NewRentalHandler(repo, handoverPaymentVerifier{})
	app := ports.NewHTTPApp()
	defer app.Shutdown()
	app.Get("/api/rentals/:id/handover-payment", handler.GetHandoverPayment)
	app.Put("/api/rentals/:id/handover-payment", handler.SavePromptPayAccount)

	for _, tc := range []struct {
		method, actor, body string
		status              int
		qr, phone, kind     string
	}{
		{http.MethodGet, "owner", "", 200, "", "", ""},
		{http.MethodPut, "owner", `{"promptpay_phone":"08123456"}`, 400, "", "", ""},
		{http.MethodPut, "renter", `{"promptpay_phone":"0812345678"}`, 403, "", "", ""},
		{http.MethodPut, "owner", `{"promptpay_phone":" 0812345678 "}`, 200, phoneQR, "0812345678", "phone"},
		{http.MethodGet, "owner", "", 200, phoneQR, "0812345678", "phone"},
		{http.MethodPut, "owner", `{"promptpay_phone":"0812345678","promptpay_national_id":"1234567890121"}`, 400, "", "", ""},
		{http.MethodPut, "owner", `{"promptpay_national_id":"1234567890122"}`, 400, "", "", ""},
		{http.MethodPut, "owner", `{"promptpay_national_id":"12345"}`, 400, "", "", ""},
		{http.MethodPut, "renter", `{"promptpay_national_id":"1234567890121"}`, 403, "", "", ""},
		{http.MethodPut, "owner", `{"promptpay_national_id":"1234567890121"}`, 200, nationalIDQR, "", "national_id"},
		{http.MethodGet, "owner", "", 200, nationalIDQR, "", "national_id"},
		{http.MethodGet, "renter", "", 200, "", "", ""},
		{http.MethodPut, "owner", `{"promptpay_phone":"0812345678"}`, 200, phoneQR, "0812345678", "phone"},
	} {
		req := httptest.NewRequest(tc.method, path, strings.NewReader(tc.body))
		req.Header.Set("Authorization", "Bearer "+tc.actor)
		req.Header.Set("Content-Type", "application/json")
		res, err := app.Test(req)
		if err != nil {
			t.Fatal(err)
		}
		body, readErr := io.ReadAll(res.Body)
		res.Body.Close()
		if readErr != nil {
			t.Fatal(readErr)
		}
		var payment domain.RentalHandoverPayment
		decodeErr := json.Unmarshal(body, &payment)
		if res.StatusCode != tc.status {
			t.Fatalf("%s %s: status %d, want %d", tc.method, tc.actor, res.StatusCode, tc.status)
		}
		if tc.status != 200 {
			continue
		}
		if decodeErr != nil || payment.TotalSatang != 199950 {
			t.Fatalf("%s %s: unexpected payment %+v (%v)", tc.method, tc.actor, payment, decodeErr)
		}
		if payment.PromptPayQR != tc.qr || payment.PromptPayPhone != tc.phone || payment.PromptPayIDType != tc.kind {
			t.Fatalf("%s %s: unexpected PromptPay payment", tc.method, tc.actor)
		}
		var fields map[string]json.RawMessage
		if err := json.Unmarshal(body, &fields); err != nil {
			t.Fatal(err)
		}
		for field := range fields {
			if strings.Contains(strings.ReplaceAll(strings.ToLower(field), "_", ""), "nationalid") {
				t.Fatal("response exposes a separate national ID field")
			}
		}
	}
}
