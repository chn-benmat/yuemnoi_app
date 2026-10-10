package tests

import (
	"bytes"
	"context"
	"encoding/json"
	"image"
	"image/jpeg"
	"log/slog"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/aiservice"
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

func TestCardReadingKeepsFieldsWhenOCRSplitsPrintedLines(t *testing.T) {
	block := func(text string, x, y, width float64) domain.OCRBlock {
		return domain.OCRBlock{Text: text, Confidence: 0.95, X: x, Y: y, Width: width, Height: 0.035}
	}
	cases := []struct {
		name   string
		blocks []domain.OCRBlock
		want   map[string]string
	}{
		{"separate Thai given name and surname", []domain.OCRBlock{
			block("ชื่อตัวและชื่อสกุล", 0.05, 0.20, 0.24), block("นายทดสอบ", 0.31, 0.20, 0.30),
			block("นามสกุล", 0.05, 0.25, 0.16), block("ระบบ", 0.31, 0.25, 0.25),
		}, map[string]string{"legal_name": "นายทดสอบ ระบบ"}},
		{"birth label above Thai and English dates", []domain.OCRBlock{
			block("เกิดวันที่", 0.05, 0.40, 0.20),
			block("1 ม.ค. 2543", 0.05, 0.45, 0.35),
			block("Date of Birth", 0.05, 0.50, 0.25),
			block("1 Jan. 2000", 0.05, 0.55, 0.35),
		}, map[string]string{"birth_date": "2000-01-01"}},
		{"split date tokens beside label", []domain.OCRBlock{
			block("วันเกิด", 0.05, 0.40, 0.16), block("1", 0.23, 0.40, 0.04),
			block("ม.ค.", 0.29, 0.40, 0.12), block("2543", 0.43, 0.40, 0.15),
		}, map[string]string{"birth_date": "2000-01-01"}},
		{"expiry does not use adjacent issue date", []domain.OCRBlock{
			block("1 ม.ค. 2565", 0.05, 0.80, 0.30), block("1 ม.ค. 2575", 0.57, 0.80, 0.30),
			block("วันออกบัตร", 0.05, 0.85, 0.24), block("วันบัตรหมดอายุ", 0.57, 0.85, 0.30),
		}, map[string]string{"expires_on": "2032-01-01"}},
		{"surname label and value on separate rows", []domain.OCRBlock{
			block("ชื่อตัวและชื่อสกุล นายทดสอบ", 0.05, 0.20, 0.6),
			block("นามสกุล", 0.05, 0.25, 0.20), block("ระบบ", 0.05, 0.30, 0.25),
		}, map[string]string{"legal_name": "นายทดสอบ ระบบ"}},
		{"spacing inside Thai labels and month abbreviation", []domain.OCRBlock{
			block("ชื่อตัว และ ชื่อสกุล นายทดสอบ ระบบ", 0.05, 0.20, 0.8),
			block("วัน บัตร หมด อายุ 1 ม. ค. 2575", 0.05, 0.85, 0.8),
		}, map[string]string{"legal_name": "นายทดสอบ ระบบ", "expires_on": "2032-01-01"}},
		{"label is not mistaken for a name", []domain.OCRBlock{
			block("ชื่อตัวและชื่อสกุล", 0.05, 0.20, 0.6), block("นามสกุล", 0.05, 0.25, 0.20),
			block("เกิดวันที่ 1 ม.ค. 2543", 0.05, 0.30, 0.5),
		}, map[string]string{"birth_date": "2000-01-01"}},
		{"missing Thai marks only in labels", []domain.OCRBlock{
			block("ชือตัวและชื่อสกุล นายทดสอบ", 0.05, 0.20, 0.6), block("นามสกล ระบบ", 0.05, 0.25, 0.6),
		}, map[string]string{"legal_name": "นายทดสอบ ระบบ"}},
		{"split expiry tokens above the label", []domain.OCRBlock{
			block("1", 0.57, 0.80, 0.03), block("ม.ค.", 0.62, 0.80, 0.09), block("2575", 0.73, 0.80, 0.12),
			block("วันบัตรหมดอายุ", 0.57, 0.85, 0.30),
		}, map[string]string{"expires_on": "2032-01-01"}},
		{"inline dates in two columns", []domain.OCRBlock{
			block("วันออกบัตร 1 ม.ค. 2565", 0.02, 0.80, 0.38),
			block("วันบัตรหมดอายุ 1 ม.ค. 2575", 0.57, 0.80, 0.40),
		}, map[string]string{"expires_on": "2032-01-01"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			require.Equal(t, tc.want, domain.IdentityCardFields(&domain.IdentityOCR{Blocks: tc.blocks}, 0.55))
		})
	}
}

func TestCardReadingCombinesIndependentOCRPassesConservatively(t *testing.T) {
	block := func(text string) domain.OCRBlock {
		return domain.OCRBlock{Text: text, Confidence: 0.95, Width: 0.8, Height: 0.03}
	}
	cases := []struct {
		name                 string
		primary, alternative []domain.OCRBlock
		want                 map[string]string
	}{
		{"recovered missing fields", []domain.OCRBlock{block("0000000000001")}, []domain.OCRBlock{block("ชื่อ ทดสอบ ระบบ")}, map[string]string{"citizen_id": "0000000000001", "legal_name": "ทดสอบ ระบบ"}},
		{"same dates in different calendars", []domain.OCRBlock{block("วันเกิด 1 ม.ค. 2543")}, []domain.OCRBlock{block("Date of Birth 1 Jan 2000")}, map[string]string{"birth_date": "2000-01-01"}},
		{"conflicting names", []domain.OCRBlock{block("ชื่อ ทดสอบ ระบบ")}, []domain.OCRBlock{block("ชื่อ ทดลอง ระบบ")}, map[string]string{}},
		{"conflicting dates", []domain.OCRBlock{block("วันเกิด 1 ม.ค. 2543")}, []domain.OCRBlock{block("วันเกิด 2 ม.ค. 2543")}, map[string]string{}},
		{"conflicting lifetime and expiry", []domain.OCRBlock{block("วันหมดอายุ ตลอดชีพ")}, []domain.OCRBlock{block("วันหมดอายุ 1 Jan 2035")}, map[string]string{}},
		{"low confidence alternative cannot override", []domain.OCRBlock{block("ชื่อ ทดสอบ ระบบ")}, []domain.OCRBlock{{Text: "ชื่อ ทดลอง ระบบ", Confidence: 0.1, Height: 0.03}}, map[string]string{"legal_name": "ทดสอบ ระบบ"}},
		{"ambiguous primary cannot be hidden by an alternative", []domain.OCRBlock{
			{Text: "วันเกิด 1 ม.ค. 2543", Confidence: 0.95, Height: 0.03, Y: 0.2},
			{Text: "Date of Birth 2 Jan 2000", Confidence: 0.95, Height: 0.03, Y: 0.3},
		}, []domain.OCRBlock{block("วันเกิด 1 ม.ค. 2543")}, map[string]string{}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			require.Equal(t, tc.want, domain.IdentityCardFields(&domain.IdentityOCR{Blocks: tc.primary, Alternatives: [][]domain.OCRBlock{tc.alternative}}, 0.55))
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

func TestIdentityOCRAdapterPreservesIndependentReadings(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		require.Equal(t, "/api/identity/read-card", r.URL.Path)
		require.Equal(t, "synthetic-key", r.Header.Get("X-Internal-Service-Key"))
		require.NoError(t, r.ParseMultipartForm(1024))
		defer r.MultipartForm.RemoveAll()
		require.Len(t, r.MultipartForm.File["card"], 1)
		w.Header().Set("Content-Type", "application/json")
		_, err := w.Write([]byte(`{"blocks":[],"alternatives":[[{"text":"ชื่อ ทดสอบ ระบบ","confidence":0.95,"x":0.1,"y":0.2,"width":0.8,"height":0.03}]]}`))
		require.NoError(t, err)
	}))
	defer server.Close()
	analyzer := aiservice.NewIdentityClient(server.URL, "synthetic-key", time.Second)
	result, err := analyzer.ReadIdentityCard(context.Background(), []byte("synthetic-image"))
	require.NoError(t, err)
	require.Len(t, result.Alternatives, 1)
	require.Equal(t, map[string]string{"legal_name": "ทดสอบ ระบบ"}, domain.IdentityCardFields(result, 0.55))
}

func TestCardReadingWithRealModelSyntheticCaptures(t *testing.T) {
	// ไฟล์นี้สร้างจากภาพจำลองใน benchmark_identity_ocr.py ไม่มีข้อมูลบุคคลจริง
	raw, err := os.ReadFile("testdata/identity_ocr_benchmark.json")
	require.NoError(t, err)
	var reports []struct {
		Case     string             `json:"case"`
		OCR      domain.IdentityOCR `json:"ocr"`
		Baseline domain.IdentityOCR `json:"baseline"`
	}
	require.NoError(t, json.Unmarshal(raw, &reports))
	require.Len(t, reports, 3)
	for _, report := range reports {
		t.Run(report.Case, func(t *testing.T) {
			fields := domain.IdentityCardFields(&report.OCR, 0.55)
			t.Logf("baseline filled=%d, improved filled=%d", len(domain.IdentityCardFields(&report.Baseline, 0.55)), len(fields))
			// วันเกิดในภาพชุดนี้คะแนนต่ำกว่า 0.55 จึงต้องเว้นไว้ แม้ข้อความบางรอบจะถูกต้อง
			require.Equal(t, map[string]string{"citizen_id": "0000000000001", "legal_name": "นายทดสอบ ระบบ", "expires_on": "2032-01-01"}, fields)
		})
	}
}
