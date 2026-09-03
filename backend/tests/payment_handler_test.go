package tests

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	stripeadapter "github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/stripe"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	"github.com/gin-gonic/gin"
	stripeapi "github.com/stripe/stripe-go/v84"
	"github.com/stripe/stripe-go/v84/webhook"
)

const paymentTestUserID = "6df692ac-40b7-4f6d-9ca1-081cf31888c9"

type paymentRepositoryMock struct {
	rental         *domain.RentalOrder
	payment        *domain.PaymentOrder
	processedEvent *domain.PaymentEvent
	processed      bool
}

func (m *paymentRepositoryMock) CreateRental(_ context.Context, userID string, request domain.CreateRentalRequest) (*domain.RentalOrder, error) {
	if m.rental == nil {
		return nil, domain.ErrRentalUnavailable
	}
	m.rental.UserID = userID
	m.rental.ItemID = request.ItemID
	return m.rental, nil
}

func (m *paymentRepositoryMock) FindRentalForUser(_ context.Context, rentalID int64, userID string) (*domain.RentalOrder, error) {
	if m.rental == nil || m.rental.ID != rentalID || m.rental.UserID != userID {
		return nil, domain.ErrRentalNotFound
	}
	return m.rental, nil
}

func (m *paymentRepositoryMock) CreateOrGetPayment(_ context.Context, _ *domain.RentalOrder, _ string) (*domain.PaymentOrder, error) {
	if m.payment == nil {
		return nil, domain.ErrPaymentNotFound
	}
	return m.payment, nil
}

func (*paymentRepositoryMock) AttachCheckoutSession(context.Context, string, string, bool) error {
	return nil
}

func (m *paymentRepositoryMock) FindPaymentForRental(_ context.Context, rentalID int64, userID string) (*domain.PaymentOrder, error) {
	if m.payment == nil || m.payment.BookingID != rentalID || m.payment.UserID != userID {
		return nil, domain.ErrPaymentNotFound
	}
	return m.payment, nil
}

func (m *paymentRepositoryMock) ProcessEvent(_ context.Context, event domain.PaymentEvent) (bool, error) {
	m.processedEvent = &event
	return m.processed, nil
}

type paymentGatewayMock struct {
	session    *domain.CheckoutSession
	event      *domain.PaymentEvent
	parseError error
}

func (m *paymentGatewayMock) CreateCheckoutSession(context.Context, domain.CheckoutRequest) (*domain.CheckoutSession, error) {
	if m.session == nil {
		return nil, domain.ErrPaymentConfiguration
	}
	return m.session, nil
}

func (m *paymentGatewayMock) ParseWebhook([]byte, string) (*domain.PaymentEvent, error) {
	return m.event, m.parseError
}

type paymentItemRepositoryMock struct {
	item *domain.Item
}

func (*paymentItemRepositoryMock) Insert(context.Context, *domain.Item, []domain.ItemImage) (*domain.Item, error) {
	return nil, errors.New("not implemented")
}
func (*paymentItemRepositoryMock) FindAll(context.Context) ([]domain.Item, error) {
	return nil, errors.New("not implemented")
}
func (m *paymentItemRepositoryMock) FindByID(context.Context, int64) (*domain.Item, error) {
	if m.item == nil {
		return nil, domain.ErrItemNotFound
	}
	return m.item, nil
}
func (*paymentItemRepositoryMock) Update(context.Context, int64, string, map[string]interface{}) (*domain.Item, error) {
	return nil, errors.New("not implemented")
}
func (*paymentItemRepositoryMock) Delete(context.Context, int64, string) error {
	return errors.New("not implemented")
}

type paymentTokenVerifier struct{}

func (paymentTokenVerifier) UserIDFromToken(context.Context, string) (string, error) {
	return paymentTestUserID, nil
}

func newPaymentHandler(repository *paymentRepositoryMock, gateway *paymentGatewayMock) *ports.RentalHandler {
	return ports.NewRentalHandler(
		repository,
		gateway,
		&paymentItemRepositoryMock{item: &domain.Item{ID: 7, ItemName: "กล้อง"}},
		paymentTokenVerifier{},
	)
}

func TestCreateRentalUsesAuthenticatedUserAndServerAmount(t *testing.T) {
	gin.SetMode(gin.TestMode)
	repository := &paymentRepositoryMock{rental: &domain.RentalOrder{
		ID: 21, TotalAmountSatang: 150000, Currency: "thb",
	}}
	router := gin.New()
	router.POST("/api/v1/rentals", newPaymentHandler(repository, &paymentGatewayMock{}).CreateRentalOrder)

	body := []byte(`{"item_id":7,"start_at":"2026-09-05T02:00:00Z","end_at":"2026-09-06T02:00:00Z","rental_type":"daily","pickup_location":"บางแค","total_price":1}`)
	request := httptest.NewRequest(http.MethodPost, "/api/v1/rentals", bytes.NewReader(body))
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Authorization", "Bearer valid-token")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	if response.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", response.Code, response.Body.String())
	}
	var rental domain.RentalOrder
	if err := json.Unmarshal(response.Body.Bytes(), &rental); err != nil {
		t.Fatal(err)
	}
	if rental.UserID != paymentTestUserID || rental.TotalAmountSatang != 150000 {
		t.Fatalf("unexpected rental response: %#v", rental)
	}
}

func TestCreateCheckoutReturnsOnlyHostedURLAndIdentifiers(t *testing.T) {
	gin.SetMode(gin.TestMode)
	repository := &paymentRepositoryMock{
		rental: &domain.RentalOrder{
			ID: 21, UserID: paymentTestUserID, ItemID: 7,
			TotalAmountSatang: 150000, Currency: "thb", PaymentStatus: "unpaid",
		},
		payment: &domain.PaymentOrder{
			ID: "11111111-1111-4111-8111-111111111111", BookingID: 21,
			UserID: paymentTestUserID, AmountSatang: 150000, Currency: "thb",
			IdempotencyKey: "checkout-key",
		},
	}
	gateway := &paymentGatewayMock{session: &domain.CheckoutSession{
		ID: "cs_test_123", URL: "https://checkout.stripe.com/test", Livemode: false,
	}}
	router := gin.New()
	router.POST("/api/v1/rentals/:id/checkout-session", newPaymentHandler(repository, gateway).CreateCheckoutSession)

	request := httptest.NewRequest(http.MethodPost, "/api/v1/rentals/21/checkout-session", nil)
	request.Header.Set("Authorization", "Bearer valid-token")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	if response.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", response.Code, response.Body.String())
	}
	if bytes.Contains(response.Body.Bytes(), []byte("secret")) {
		t.Fatalf("response must not expose a secret: %s", response.Body.String())
	}
}

func TestStripeWebhookRejectsInvalidSignature(t *testing.T) {
	gin.SetMode(gin.TestMode)
	handler := newPaymentHandler(
		&paymentRepositoryMock{},
		&paymentGatewayMock{parseError: errors.New("invalid signature")},
	)
	router := gin.New()
	router.POST("/api/v1/webhooks/stripe", handler.HandleStripeWebhook)

	request := httptest.NewRequest(http.MethodPost, "/api/v1/webhooks/stripe", bytes.NewReader([]byte("{}")))
	request.Header.Set("Stripe-Signature", "invalid")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	if response.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", response.Code)
	}
}

func TestStripeGatewayVerifiesAndMapsPaidCheckout(t *testing.T) {
	const secret = "whsec_test"
	payload := []byte(`{
  "id":"evt_test_paid","object":"event","api_version":"` + stripeapi.APIVersion + `","created":1,"livemode":false,
  "type":"checkout.session.completed","data":{"object":{
    "id":"cs_test_123","object":"checkout.session","amount_total":150000,"currency":"thb","payment_status":"paid",
    "metadata":{"payment_order_id":"11111111-1111-4111-8111-111111111111"},"payment_intent":"pi_test_123"
  }}
}`)
	signed := webhook.GenerateTestSignedPayload(&webhook.UnsignedPayload{
		Payload: payload, Secret: secret, Timestamp: time.Now(),
	})
	gateway := stripeadapter.NewPaymentGateway("", secret, "", "")

	event, err := gateway.ParseWebhook(payload, signed.Header)
	if err != nil {
		t.Fatal(err)
	}
	if event == nil || event.NextStatus != domain.PaymentStatusPaid || event.AmountSatang != 150000 {
		t.Fatalf("unexpected mapped event: %#v", event)
	}
}
