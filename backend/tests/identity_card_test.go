package tests

import (
	"bytes"
	"context"
	"encoding/json"
	"image"
	"image/jpeg"
	"log/slog"
	"mime/multipart"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	"github.com/gofiber/fiber/v3"
	"github.com/stretchr/testify/require"
)

func TestCardReadingLeavesUncertainValuesBlank(t *testing.T) {
	block := func(text string, y float64) domain.OCRBlock {
		return domain.OCRBlock{Text: text, Confidence: 0.95, Y: y, Width: 0.7, Height: 0.03}
	}
	cases := []struct {
		name   string
		blocks []domain.OCRBlock
		want   map[string]string
	}{
		{"Thai fields and Buddhist dates", []domain.OCRBlock{block("0 0000 00000 00 1", 0.1), block("ชื่อ ทดสอบ ระบบ", 0.2), block("วันเกิด 1 ม.ค. 2543", 0.3), block("วันหมดอายุ 1 Jan. 2035", 0.4)}, map[string]string{"citizen_id": "0000000000001", "legal_name": "ทดสอบ ระบบ", "birth_date": "2000-01-01", "expires_on": "2035-01-01"}},
		{"not a card", []domain.OCRBlock{block("SYNTHETIC TEST NO REAL ID", 0.1)}, map[string]string{}},
		{"invalid date and checksum", []domain.OCRBlock{block("0000000000002", 0.1), block("วันเกิด 31 ก.พ. 2543", 0.3)}, map[string]string{}},
		{"lifetime", []domain.OCRBlock{block("วันหมดอายุ ตลอดชีพ", 0.3)}, map[string]string{"lifetime": "true"}},
		{"conflicting birth dates", []domain.OCRBlock{block("วันเกิด 1 ม.ค. 2543", 0.2), block("Date of Birth 2 Jan 2000", 0.3)}, map[string]string{}},
		{"low confidence", []domain.OCRBlock{{Text: "0000000000001", Height: 0.02, Confidence: 0.1}}, map[string]string{}},
		{"joined Thai date and labelled ID", []domain.OCRBlock{block("เลขประจำตัวประชาชน 0 0000 00000 00 1", 0.1), block("วันเกิด 1ม.ค.2543", 0.2)}, map[string]string{"citizen_id": "0000000000001", "birth_date": "2000-01-01"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			require.Equal(t, tc.want, domain.IdentityCardFields(&domain.IdentityOCR{Blocks: tc.blocks}, 0.55))
		})
	}
}

type cardAnalyzer struct{ calls int }

func (a *cardAnalyzer) AnalyzeIdentity(context.Context, []byte, []byte) (*domain.IdentityAnalysis, error) {
	return nil, nil
}
func (a *cardAnalyzer) ReadIdentityCard(context.Context, []byte) (*domain.IdentityOCR, error) {
	a.calls++
	return &domain.IdentityOCR{Blocks: []domain.OCRBlock{{Text: "0000000000001", Confidence: 0.9, Height: 0.03}}}, nil
}
func TestReadCardUsesOwnedActiveSessionAndDoesNotStoreEvidence(t *testing.T) {
	id := "00000000-0000-4000-8000-000000000002"
	for _, tc := range []struct {
		name, owner, status string
		suspended, minor    bool
		until               time.Time
		http                int
	}{
		{"active", id, "capture", false, false, time.Now().Add(time.Minute), 200},
		{"another session", "00000000-0000-4000-8000-000000000003", "capture", false, false, time.Now().Add(time.Minute), 409},
		{"already submitted", id, "pending", false, false, time.Now().Add(time.Minute), 409},
		{"expired", id, "capture", false, false, time.Now().Add(-time.Minute), 409},
		{"suspended", id, "capture", true, false, time.Now().Add(time.Minute), 403},
		{"guardian revoked", id, "capture", false, true, time.Now().Add(time.Minute), 409},
	} {
		t.Run(tc.name, func(t *testing.T) {
			store := &opsStore{call: func(name string, args map[string]any) (json.RawMessage, error) {
				require.Equal(t, "identity_status", name)
				require.Equal(t, "00000000-0000-4000-8000-000000000001", args["p_actor"])
				return json.Marshal(map[string]any{"control": map[string]any{"suspended": tc.suspended}, "request": map[string]any{"id": tc.owner, "status": tc.status, "capture_until": tc.until, "is_minor": tc.minor}})
			}}
			analyzer := &cardAnalyzer{}
			handler := ports.NewOperationsHandler(domain.OperationsOptions{Store: store, Analyzer: analyzer, OCRMinConfidence: 0.55}, opsVerifier{})
			app := fiber.New()
			app.Post("/identity/:id", handler.ReadCard)
			var picture, body bytes.Buffer
			require.NoError(t, jpeg.Encode(&picture, image.NewRGBA(image.Rect(0, 0, 16, 16)), nil))
			writer := multipart.NewWriter(&body)
			part, err := writer.CreateFormFile("card", "fixture.jpg")
			require.NoError(t, err)
			_, err = part.Write(picture.Bytes())
			require.NoError(t, err)
			require.NoError(t, writer.Close())
			req := httptest.NewRequest("POST", "/identity/"+id, &body)
			req.Header.Set("Authorization", "Bearer test-token")
			req.Header.Set("Content-Type", writer.FormDataContentType())
			res, err := app.Test(req)
			require.NoError(t, err)
			defer res.Body.Close()
			require.Equal(t, tc.http, res.StatusCode)
			require.Contains(t, res.Header.Get("Cache-Control"), "no-store")
			require.Equal(t, []string{"identity_status"}, store.events)
			if tc.http == 200 {
				require.Equal(t, 1, analyzer.calls)
			} else {
				require.Zero(t, analyzer.calls)
			}
		})
	}
}
func TestIdentityResponseBodyIsNeverLogged(t *testing.T) {
	var logs bytes.Buffer
	previous := slog.Default()
	slog.SetDefault(slog.New(slog.NewJSONHandler(&logs, nil)))
	t.Cleanup(func() { slog.SetDefault(previous) })
	app := fiber.New()
	app.Use(ports.ResponseLoggingMiddleware())
	app.Get("/api/identity/fixture", func(c fiber.Ctx) error {
		return c.JSON(fiber.Map{"citizen_id": "sensitive-fixture", "legal_name": "private-fixture"})
	})
	res, err := app.Test(httptest.NewRequest("GET", "/api/identity/fixture", nil))
	require.NoError(t, err)
	res.Body.Close()
	require.NotContains(t, logs.String(), "sensitive-fixture")
	require.NotContains(t, logs.String(), "private-fixture")
	require.Contains(t, logs.String(), "identity data omitted")
}
