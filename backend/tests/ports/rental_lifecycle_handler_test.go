package ports_test

import (
	"bytes"
	"context"
	"image"
	"image/color"
	"image/jpeg"
	"mime/multipart"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	ports "github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
)

type lifecycleRepository struct {
	domain.RentalRepository
	completeCalls int
	receiptCalls  int
	evidence      []domain.ItemImage
}

func (r *lifecycleRepository) SubmitRentalEvidence(_ context.Context, _ string, id int64, images []domain.ItemImage, _ map[string]bool) (*domain.RentalOrder, error) {
	r.evidence = images
	return &domain.RentalOrder{ID: id, Status: "awaiting_return"}, nil
}

func (r *lifecycleRepository) CompleteRentalReturn(_ context.Context, user string, id int64, token string) (*domain.RentalOrder, error) {
	r.completeCalls++
	return nil, domain.ErrRentalReturnToken
}

func (r *lifecycleRepository) ConfirmRentalReceipt(_ context.Context, user string, id int64) (*domain.RentalOrder, error) {
	r.receiptCalls++
	if user != "renter" || id != 25 {
		return nil, domain.ErrInvalidRental
	}
	return nil, domain.ErrRentalForbidden
}

func TestRentalReceiptRequiresCheckAndDelegatesAuthorization(t *testing.T) {
	repo := &lifecycleRepository{}
	app := ports.NewHTTPApp()
	defer app.Shutdown()
	app.Post("/rentals/:id/return-confirmation", ports.NewRentalHandler(repo, rentalConfirmationVerifier{}).ConfirmRentalReceipt)
	for _, tc := range []struct {
		body   string
		status int
		calls  int
	}{
		{body: `{"checked":false}`, status: 400, calls: 0},
		{body: `{"checked":true,"user_id":"owner"}`, status: 403, calls: 1},
	} {
		request := httptest.NewRequest("POST", "/rentals/25/return-confirmation", strings.NewReader(tc.body))
		request.Header.Set("Content-Type", "application/json")
		request.Header.Set("Authorization", "Bearer renter-token")
		response, err := app.Test(request)
		if err != nil {
			t.Fatal(err)
		}
		response.Body.Close()
		if response.StatusCode != tc.status || repo.receiptCalls != tc.calls {
			t.Fatalf("body=%s status=%d calls=%d", tc.body, response.StatusCode, repo.receiptCalls)
		}
	}
}

func TestLegacyReturnCannotCompleteWithoutServerIssuedCode(t *testing.T) {
	for _, body := range []string{``, `{}`, `{"token_or_otp":""}`, `{"token_or_otp":"123456"}`} {
		repo := &lifecycleRepository{}
		app := ports.NewHTTPApp()
		app.Post("/rentals/:id/return", ports.NewRentalHandler(repo, rentalConfirmationVerifier{}).ReturnRental)
		request := httptest.NewRequest("POST", "/rentals/25/return", strings.NewReader(body))
		request.Header.Set("Content-Type", "application/json")
		request.Header.Set("Authorization", "Bearer renter-token")
		response, err := app.Test(request)
		if err != nil {
			t.Fatal(err)
		}
		if response.StatusCode != 400 {
			t.Fatalf("body=%s status=%d", body, response.StatusCode)
		}
		if body != `{"token_or_otp":"123456"}` && repo.completeCalls != 0 {
			t.Fatal("missing token reached repository")
		}
		response.Body.Close()
		app.Shutdown()
	}
}

func TestRentalEvidenceStripsMetadataAndRejectsInvalidImages(t *testing.T) {
	for _, valid := range []bool{false, true} {
		var body bytes.Buffer
		form := multipart.NewWriter(&body)
		for range 3 {
			photo, _ := form.CreateFormFile("photos", "evidence.jpg")
			if valid {
				img := image.NewRGBA(image.Rect(0, 0, 1, 1))
				img.Set(0, 0, color.White)
				jpeg.Encode(photo, img, nil)
				photo.Write([]byte("private trailing metadata"))
			} else {
				photo.Write([]byte("not an image"))
			}
		}
		form.WriteField("checklist", `{"power_on":true,"no_new_cracks":true,"accessories_complete":true}`)
		form.Close()
		app := ports.NewHTTPApp()
		repo := &lifecycleRepository{}
		app.Post("/rentals/:id/return-evidence", ports.NewRentalHandler(repo, rentalConfirmationVerifier{}).SubmitRentalReturnEvidence)
		req := httptest.NewRequest("POST", "/rentals/25/return-evidence", &body)
		req.Header.Set("Authorization", "Bearer renter-token")
		req.Header.Set("Content-Type", form.FormDataContentType())
		response, err := app.Test(req)
		if err != nil {
			t.Fatal(err)
		}
		expected := 400
		if valid {
			expected = 200
		}
		if response.StatusCode != expected {
			t.Fatalf("got %d expected %d", response.StatusCode, expected)
		}
		if valid {
			if len(repo.evidence) != 3 {
				t.Fatalf("evidence count=%d", len(repo.evidence))
			}
			for _, photo := range repo.evidence {
				if bytes.Contains(photo.Data, []byte("private trailing metadata")) {
					t.Error("metadata retained")
				}
			}
		} else if len(repo.evidence) != 0 {
			t.Error("invalid image reached repository")
		}
		response.Body.Close()
		app.Shutdown()
	}
}
