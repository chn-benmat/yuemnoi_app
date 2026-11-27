package ports_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	"github.com/gofiber/fiber/v3"
)

type queueTestRepository struct {
	domain.RentalRepository
	actor   string
	request domain.RentalQueueRequest
}

func (r *queueTestRepository) RentalQueue(_ context.Context, actor string, request domain.RentalQueueRequest) (domain.RentalQueueResult, error) {
	r.actor, r.request = actor, request
	return domain.RentalQueueResult{MessageID: 35}, nil
}

func TestRentalQueueJoinRequiresAuthenticatedActorAndCard(t *testing.T) {
	const conversation = "260a480a-adf0-4e39-a444-63caa7ea1501"
	repo := &queueTestRepository{}
	h := ports.NewRentalHandler(repo, nil)
	app := fiber.New()
	app.Post("/queue", h.RentalQueue)
	req := httptest.NewRequest(http.MethodPost, "/queue", strings.NewReader(
		`{"conversation_id":"`+conversation+`","action":"join","message_id":35}`))
	req.Header.Set("Content-Type", "application/json")
	res, err := app.Test(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusUnauthorized || repo.actor != "" || repo.request.MessageID != 0 {
		t.Fatalf("unauthenticated join reached repository: %d, %#v", res.StatusCode, repo)
	}
}

func TestRentalQueueValidatesActionTargets(t *testing.T) {
	const conversation = "260a480a-adf0-4e39-a444-63caa7ea1501"
	for _, tc := range []struct {
		action, target string
		want           int
	}{
		{"request", `,"item_id":8`, http.StatusOK},
		{"invite", `,"item_id":8`, http.StatusBadRequest},
		{"request", "", http.StatusBadRequest},
		{"accept", `,"message_id":35`, http.StatusOK},
		{"accept", `,"item_id":8`, http.StatusBadRequest},
		{"request", `,"item_id":8,"message_id":35`, http.StatusBadRequest},
	} {
		t.Run(tc.action+tc.target, func(t *testing.T) {
			repo := &queueTestRepository{}
			app := ports.NewHTTPApp()
			app.Post("/queue", ports.NewRentalHandler(repo, rentalConfirmationVerifier{}).RentalQueue)
			req := httptest.NewRequest(http.MethodPost, "/queue", strings.NewReader(
				`{"conversation_id":"`+conversation+`","action":"`+tc.action+`"`+tc.target+`}`))
			req.Header.Set("Content-Type", "application/json")
			req.Header.Set("Authorization", "Bearer renter-token")
			res, err := app.Test(req)
			if err != nil {
				t.Fatal(err)
			}
			defer res.Body.Close()
			if res.StatusCode != tc.want {
				t.Fatalf("status = %d, want %d", res.StatusCode, tc.want)
			}
			if tc.want == http.StatusOK {
				if repo.actor != "renter" || repo.request.ConversationID != conversation || repo.request.Action != tc.action {
					t.Fatalf("wrong authenticated request: %#v", repo)
				}
			} else if repo.actor != "" {
				t.Fatalf("invalid action reached repository: %#v", repo)
			}
		})
	}
}
