package stripe

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"strings"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	stripeapi "github.com/stripe/stripe-go/v84"
	"github.com/stripe/stripe-go/v84/webhook"
)

const paymentOrderMetadataKey = "payment_order_id"

type PaymentGateway struct {
	client        *stripeapi.Client
	webhookSecret string
	successURL    string
	cancelURL     string
}

func NewPaymentGateway(secretKey, webhookSecret, successURL, cancelURL string) *PaymentGateway {
	var client *stripeapi.Client
	if strings.TrimSpace(secretKey) != "" {
		client = stripeapi.NewClient(strings.TrimSpace(secretKey))
	}
	return &PaymentGateway{
		client:        client,
		webhookSecret: strings.TrimSpace(webhookSecret),
		successURL:    strings.TrimSpace(successURL),
		cancelURL:     strings.TrimSpace(cancelURL),
	}
}

func (g *PaymentGateway) CreateCheckoutSession(ctx context.Context, request domain.CheckoutRequest) (*domain.CheckoutSession, error) {
	if g.client == nil || !validReturnURL(g.successURL) || !validReturnURL(g.cancelURL) {
		return nil, domain.ErrPaymentConfiguration
	}
	successURL, err := checkoutReturnURL(g.successURL, request.BookingID, "success", true)
	if err != nil {
		return nil, domain.ErrPaymentConfiguration
	}
	cancelURL, err := checkoutReturnURL(g.cancelURL, request.BookingID, "cancel", false)
	if err != nil {
		return nil, domain.ErrPaymentConfiguration
	}

	metadata := map[string]string{
		paymentOrderMetadataKey: request.PaymentOrderID,
		"booking_id":            fmt.Sprintf("%d", request.BookingID),
	}
	params := &stripeapi.CheckoutSessionCreateParams{
		SuccessURL:        stripeapi.String(successURL),
		CancelURL:         stripeapi.String(cancelURL),
		ClientReferenceID: stripeapi.String(request.PaymentOrderID),
		Mode:              stripeapi.String(string(stripeapi.CheckoutSessionModePayment)),
		Locale:            stripeapi.String("th"),
		OriginContext:     stripeapi.String("mobile_app"),
		ExpiresAt:         stripeapi.Int64(time.Now().Add(30 * time.Minute).Unix()),
		Metadata:          metadata,
		PaymentIntentData: &stripeapi.CheckoutSessionCreatePaymentIntentDataParams{
			Metadata: metadata,
		},
		LineItems: []*stripeapi.CheckoutSessionCreateLineItemParams{
			{
				PriceData: &stripeapi.CheckoutSessionCreateLineItemPriceDataParams{
					Currency:   stripeapi.String(strings.ToLower(request.Currency)),
					UnitAmount: stripeapi.Int64(request.AmountSatang),
					ProductData: &stripeapi.CheckoutSessionCreateLineItemPriceDataProductDataParams{
						Name: stripeapi.String(request.ItemName),
					},
				},
				Quantity: stripeapi.Int64(1),
			},
		},
	}
	params.SetIdempotencyKey(request.IdempotencyKey)

	session, err := g.client.V1CheckoutSessions.Create(ctx, params)
	if err != nil {
		return nil, fmt.Errorf("create Stripe Checkout Session: %w", err)
	}
	if session.ID == "" || session.URL == "" {
		return nil, fmt.Errorf("create Stripe Checkout Session: missing session URL")
	}

	return &domain.CheckoutSession{
		ID:       session.ID,
		URL:      session.URL,
		Livemode: session.Livemode,
	}, nil
}

func (g *PaymentGateway) RetrieveCheckoutSession(ctx context.Context, sessionID string) (*domain.PaymentEvent, error) {
	if g.client == nil || strings.TrimSpace(sessionID) == "" {
		return nil, domain.ErrPaymentConfiguration
	}
	session, err := g.client.V1CheckoutSessions.Retrieve(ctx, strings.TrimSpace(sessionID), nil)
	if err != nil {
		return nil, fmt.Errorf("retrieve Stripe Checkout Session: %w", err)
	}
	status := domain.PaymentStatusCheckoutPending
	if session.PaymentStatus == stripeapi.CheckoutSessionPaymentStatusPaid {
		status = domain.PaymentStatusPaid
	} else if session.Status == stripeapi.CheckoutSessionStatusExpired {
		status = domain.PaymentStatusExpired
	}

	paymentIntentID := ""
	if session.PaymentIntent != nil {
		paymentIntentID = session.PaymentIntent.ID
	}

	paymentOrderID := session.ClientReferenceID
	if paymentOrderID == "" && session.Metadata != nil {
		paymentOrderID = session.Metadata[paymentOrderMetadataKey]
	}

	return &domain.PaymentEvent{
		ID:                      "retrieved_" + session.ID,
		Type:                    "checkout.session.completed",
		PaymentOrderID:          paymentOrderID,
		StripeCheckoutSessionID: session.ID,
		StripePaymentIntentID:   paymentIntentID,
		AmountSatang:            session.AmountTotal,
		Currency:                string(session.Currency),
		Livemode:                session.Livemode,
		NextStatus:              status,
	}, nil
}

func (g *PaymentGateway) ParseWebhook(payload []byte, signature string) (*domain.PaymentEvent, error) {
	if g.webhookSecret == "" {
		return nil, domain.ErrPaymentConfiguration
	}

	event, err := webhook.ConstructEvent(payload, signature, g.webhookSecret)
	if err != nil {
		return nil, fmt.Errorf("verify Stripe webhook: %w", err)
	}
	if event.Data == nil {
		return nil, fmt.Errorf("Stripe webhook has no data")
	}

	switch string(event.Type) {
	case "checkout.session.completed", "checkout.session.async_payment_succeeded",
		"checkout.session.async_payment_failed", "checkout.session.expired":
		return checkoutEvent(event)
	case "charge.refunded":
		return refundEvent(event)
	default:
		return nil, nil
	}
}

func checkoutEvent(event stripeapi.Event) (*domain.PaymentEvent, error) {
	var session stripeapi.CheckoutSession
	if err := json.Unmarshal(event.Data.Raw, &session); err != nil {
		return nil, fmt.Errorf("decode Checkout Session event: %w", err)
	}

	status := domain.PaymentStatusCheckoutPending
	switch string(event.Type) {
	case "checkout.session.completed", "checkout.session.async_payment_succeeded":
		if session.PaymentStatus == stripeapi.CheckoutSessionPaymentStatusPaid {
			status = domain.PaymentStatusPaid
		}
	case "checkout.session.async_payment_failed":
		status = domain.PaymentStatusFailed
	case "checkout.session.expired":
		status = domain.PaymentStatusExpired
	}

	paymentIntentID := ""
	if session.PaymentIntent != nil {
		paymentIntentID = session.PaymentIntent.ID
	}
	return &domain.PaymentEvent{
		ID:                      event.ID,
		Type:                    string(event.Type),
		PaymentOrderID:          session.Metadata[paymentOrderMetadataKey],
		StripeCheckoutSessionID: session.ID,
		StripePaymentIntentID:   paymentIntentID,
		AmountSatang:            session.AmountTotal,
		Currency:                string(session.Currency),
		Livemode:                event.Livemode,
		NextStatus:              status,
	}, nil
}

func refundEvent(event stripeapi.Event) (*domain.PaymentEvent, error) {
	var charge stripeapi.Charge
	if err := json.Unmarshal(event.Data.Raw, &charge); err != nil {
		return nil, fmt.Errorf("decode refunded charge event: %w", err)
	}
	status := domain.PaymentStatusPartiallyRefunded
	if charge.AmountRefunded >= charge.Amount {
		status = domain.PaymentStatusRefunded
	}
	paymentIntentID := ""
	if charge.PaymentIntent != nil {
		paymentIntentID = charge.PaymentIntent.ID
	}
	return &domain.PaymentEvent{
		ID:                    event.ID,
		Type:                  string(event.Type),
		PaymentOrderID:        charge.Metadata[paymentOrderMetadataKey],
		StripePaymentIntentID: paymentIntentID,
		AmountSatang:          charge.Amount,
		Currency:              string(charge.Currency),
		Livemode:              event.Livemode,
		NextStatus:            status,
	}, nil
}

func validReturnURL(value string) bool {
	parsed, err := url.ParseRequestURI(value)
	return err == nil && (parsed.Scheme == "https" || parsed.Scheme == "http") && parsed.Host != ""
}

func checkoutReturnURL(baseURL string, rentalID int64, result string, includeSession bool) (string, error) {
	parsed, err := url.Parse(baseURL)
	if err != nil {
		return "", err
	}
	query := parsed.Query()
	query.Set("rental_id", fmt.Sprintf("%d", rentalID))
	query.Set("result", result)
	if includeSession {
		query.Set("session_id", "{CHECKOUT_SESSION_ID}")
	}
	parsed.RawQuery = query.Encode()
	return strings.ReplaceAll(
		parsed.String(),
		"%7BCHECKOUT_SESSION_ID%7D",
		"{CHECKOUT_SESSION_ID}",
	), nil
}
