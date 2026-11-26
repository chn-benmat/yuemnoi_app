package ports_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"mime/multipart"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
)

type identityAccountStore struct {
	raw         string
	actor       string
	calls       []string
	reuse       bool
	legacy      bool
	submitError bool
	cancelled   bool
	uploads     atomic.Int32
	deletes     atomic.Int32
	submitted   map[string]any
}

func (s *identityAccountStore) RPC(_ context.Context, name string, args map[string]any) (json.RawMessage, error) {
	s.calls = append(s.calls, name)
	if args["p_actor"] != s.actor {
		return nil, errors.New("evidence_unavailable")
	}
	switch name {
	case "identity_account_details":
		return json.Marshal(map[string]any{"raw_encrypted": s.raw, "locked_hmac": domain.CitizenHMAC("1234567890123", bytes.Repeat([]byte{2}, 32)), "has_identity": true, "status": map[string]any{"profile": map[string]any{"status": "approved"}}})
	case "identity_owner_evidence":
		if s.reuse {
			kind := "card"
			if args["p_id"] == "00000000-0000-4000-8000-000000000003" {
				kind = "selfie"
			}
			return json.Marshal(map[string]any{"object_path": "renter/" + kind, "kind": kind, "selfie_with_card": !s.legacy})
		}
		return nil, errors.New("evidence_unavailable")
	case "identity_status":
		return json.Marshal(map[string]any{"request": map[string]any{"id": "00000000-0000-4000-8000-000000000001", "status": "capture", "capture_until": time.Now().Add(time.Minute)}})
	case "identity_reserve_evidence":
		return json.RawMessage(`{"ok":true}`), nil
	case "identity_submit":
		s.submitted = args["p_data"].(map[string]any)
		if s.submitError {
			return nil, errors.New("operations_unavailable")
		}
		return json.RawMessage(`{"status":"pending"}`), nil
	case "identity_cancel_capture":
		return json.Marshal(map[string]any{"cancelled": s.cancelled})
	}
	return nil, errors.New("unexpected_rpc")
}
func (s *identityAccountStore) UploadEvidence(context.Context, string, []byte, string) error {
	if s.reuse {
		s.uploads.Add(1)
		return nil
	}
	return errors.New("unexpected_upload")
}
func (s *identityAccountStore) ReadEvidence(context.Context, string) ([]byte, string, error) {
	if s.reuse {
		return []byte("previously sanitized image"), "image/jpeg", nil
	}
	return nil, "", errors.New("unexpected_read")
}
func (s *identityAccountStore) DeleteEvidence(context.Context, string) error {
	s.deletes.Add(1)
	return nil
}

func TestIdentityAccountReusesOwnedEvidenceAndKeepsCommittedImages(t *testing.T) {
	for _, tc := range []struct {
		name                   string
		submitError, cancelled bool
		wantStatus             int
		wantDeletes            int32
		legacy                 bool
		consentVersion         string
	}{
		{"reuse originals with updated consent", false, false, 201, 0, false, "identity-v2"},
		{"reuse legacy originals without new metadata", false, false, 201, 0, true, ""},
		{"failed capture can retry", true, true, 503, 2, false, ""},
		{"ambiguous submit preserves committed images", true, false, 503, 0, false, ""},
		{"unsupported consent stops upload", false, false, 400, 0, false, "unknown"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			key := bytes.Repeat([]byte{1}, 32)
			raw, _ := domain.EncryptIdentity([]byte(`{"citizen_id":"1234567890123"}`), key)
			store := &identityAccountStore{actor: "renter", raw: raw, reuse: true, legacy: tc.legacy, submitError: tc.submitError, cancelled: tc.cancelled}
			app := ports.NewHTTPApp()
			handler := ports.NewOperationsHandler(domain.OperationsOptions{Store: store, EncryptionKey: key, HMACKey: bytes.Repeat([]byte{2}, 32)}, rentalConfirmationVerifier{})
			app.Post("/sessions/:id", handler.Submit)
			var body bytes.Buffer
			form := multipart.NewWriter(&body)
			for field, value := range map[string]string{"legal_name": "นาย ทดสอบ ระบบ", "name_prefix": "นาย", "first_name": "ทดสอบ", "last_name": "ระบบ",
				"birth_date": "2000-01-01", "address_detail": "99 ถนนทดสอบ", "postal_code": "10200", "province": "กรุงเทพมหานคร", "district": "เขตพระนคร", "subdistrict": "พระบรมมหาราชวัง",
				"card_evidence_id": "00000000-0000-4000-8000-000000000002", "selfie_evidence_id": "00000000-0000-4000-8000-000000000003"} {
				_ = form.WriteField(field, value)
			}
			if tc.consentVersion != "" {
				_ = form.WriteField("consent_version", tc.consentVersion)
			}
			_ = form.Close()
			req := httptest.NewRequest("POST", "/sessions/00000000-0000-4000-8000-000000000001", &body)
			req.Header.Set("Authorization", "Bearer renter-token")
			req.Header.Set("Content-Type", form.FormDataContentType())
			response, err := app.Test(req)
			if err != nil {
				t.Fatal(err)
			}
			defer response.Body.Close()
			payload, _ := io.ReadAll(response.Body)
			if response.StatusCode != tc.wantStatus {
				t.Fatalf("status=%d body=%s", response.StatusCode, payload)
			}
			if tc.wantStatus == 400 {
				if store.uploads.Load() != 0 || store.submitted != nil {
					t.Fatal("invalid consent was accepted for upload")
				}
				return
			}
			if version, _ := store.submitted["consent_version"].(string); version != tc.consentVersion {
				t.Fatalf("submitted consent=%q, want %q", version, tc.consentVersion)
			}
			if store.uploads.Load() != 2 || store.deletes.Load() != tc.wantDeletes {
				t.Fatalf("uploads=%d deletes=%d", store.uploads.Load(), store.deletes.Load())
			}
			plain, err := domain.DecryptIdentity(store.submitted["raw_encrypted"].(string), key)
			if err != nil {
				t.Fatal(err)
			}
			if !strings.Contains(string(plain), "1234567890123") {
				t.Fatal("lost locked citizen ID")
			}
			if store.submitted["analysis"].(map[string]any)["selfie_with_card"] != !tc.legacy {
				t.Fatal("lost evidence kind")
			}
		})
	}
}

func TestIdentityAccountRequiresOwnerAndDoesNotLeakCiphertext(t *testing.T) {
	key := bytes.Repeat([]byte{1}, 32)
	encrypted, err := domain.EncryptIdentity([]byte(`{"first_name":"Test","citizen_id":"1234567890123"}`), key)
	if err != nil {
		t.Fatal(err)
	}
	store := &identityAccountStore{raw: encrypted, actor: "renter"}
	app := ports.NewHTTPApp()
	handler := ports.NewOperationsHandler(domain.OperationsOptions{Store: store, EncryptionKey: key}, rentalConfirmationVerifier{})
	app.Get("/account", handler.AccountDetails)
	app.Get("/evidence/:id", handler.AccountEvidence)
	for _, tc := range []struct {
		path, token string
		want        int
	}{
		{"/account", "", 401}, {"/account", "renter-token", 200},
		{"/evidence/00000000-0000-4000-8000-000000000099", "renter-token", 410},
	} {
		req := httptest.NewRequest("GET", tc.path, nil)
		if tc.token != "" {
			req.Header.Set("Authorization", "Bearer "+tc.token)
		}
		response, err := app.Test(req)
		if err != nil {
			t.Fatal(err)
		}
		body, _ := io.ReadAll(response.Body)
		response.Body.Close()
		if response.StatusCode != tc.want {
			t.Fatalf("%s: %d %s", tc.path, response.StatusCode, body)
		}
		if strings.Contains(string(body), "locked_hmac") || strings.Contains(string(body), encrypted) {
			t.Fatalf("private metadata leaked: %s", body)
		}
		if tc.want == 200 && (!strings.Contains(string(body), "1234567890123") || response.Header.Get("Cache-Control") != "private, no-store") {
			t.Fatal("missing owner fields or cache protection")
		}
	}
}

func TestIdentityAccountRejectsCitizenChangeBeforeUploading(t *testing.T) {
	store := &identityAccountStore{actor: "renter"}
	app := ports.NewHTTPApp()
	handler := ports.NewOperationsHandler(domain.OperationsOptions{Store: store, EncryptionKey: bytes.Repeat([]byte{1}, 32), HMACKey: bytes.Repeat([]byte{2}, 32)}, rentalConfirmationVerifier{})
	app.Post("/sessions/:id", handler.Submit)
	var body bytes.Buffer
	form := multipart.NewWriter(&body)
	_ = form.WriteField("citizen_id", "9999999999999")
	_ = form.WriteField("birth_date", "2000-01-01")
	_ = form.Close()
	req := httptest.NewRequest("POST", "/sessions/00000000-0000-4000-8000-000000000001", &body)
	req.Header.Set("Authorization", "Bearer renter-token")
	req.Header.Set("Content-Type", form.FormDataContentType())
	response, err := app.Test(req)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	payload, _ := io.ReadAll(response.Body)
	if response.StatusCode != 409 || !strings.Contains(string(payload), "citizen_id_locked") {
		t.Fatalf("unexpected response: %d %s", response.StatusCode, payload)
	}
	if len(store.calls) != 2 {
		t.Fatalf("unexpected upload RPC: %v", store.calls)
	}
}
