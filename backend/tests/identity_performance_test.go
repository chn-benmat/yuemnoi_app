package tests

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"image"
	"image/jpeg"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	"github.com/stretchr/testify/require"
)

type parallelEvidenceStore struct {
	mu        sync.Mutex
	started   chan string
	release   chan struct{}
	reserved  map[string]bool
	finished  map[string]bool
	deleted   map[string]bool
	submitted bool
	fail      bool
	violation bool
}

const performanceSession = "00000000-0000-4000-8000-000000000002"

func (s *parallelEvidenceStore) RPC(_ context.Context, name string, args map[string]any) (json.RawMessage, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	switch name {
	case "identity_status":
		return json.Marshal(map[string]any{"request": map[string]any{
			"id": performanceSession, "status": "capture", "capture_until": time.Now().Add(time.Minute),
		}})
	case "identity_reserve_evidence":
		for _, evidence := range args["p_evidence"].([]map[string]any) {
			s.reserved[evidence["object_path"].(string)] = true
		}
	case "identity_submit":
		s.submitted = true
		if len(s.finished) != 2 || len(s.deleted) != 0 {
			s.violation = true
		}
	}
	return json.RawMessage(`{"status":"pending"}`), nil
}

func (s *parallelEvidenceStore) UploadEvidence(_ context.Context, path string, _ []byte, _ string) error {
	s.mu.Lock()
	if !s.reserved[path] {
		s.violation = true
	}
	s.mu.Unlock()
	s.started <- path
	// รอทั้งสองงานเริ่มก่อนปล่อย เพื่อจับการอัปโหลดทีละไฟล์โดยไม่เทียบเวลารวม
	<-s.release
	s.mu.Lock()
	s.finished[path] = true
	s.mu.Unlock()
	if s.fail {
		return errors.New("synthetic_upload_failure")
	}
	return nil
}

func (s *parallelEvidenceStore) ReadEvidence(context.Context, string) ([]byte, string, error) {
	return nil, "", nil
}

func (s *parallelEvidenceStore) DeleteEvidence(_ context.Context, path string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.finished) != 2 {
		s.violation = true
	}
	s.deleted[path] = true
	return nil
}

func identityPerformanceRequest(t *testing.T) *http.Request {
	t.Helper()
	var body, photo bytes.Buffer
	require.NoError(t, jpeg.Encode(&photo, image.NewRGBA(image.Rect(0, 0, 32, 32)), nil))
	writer := multipart.NewWriter(&body)
	for key, value := range map[string]string{
		"citizen_id": "0000000000001", "legal_name": "Synthetic Test", "birth_date": "2000-01-01",
	} {
		require.NoError(t, writer.WriteField(key, value))
	}
	for _, kind := range []string{"card", "selfie"} {
		part, err := writer.CreateFormFile(kind, kind+".jpg")
		require.NoError(t, err)
		_, err = part.Write(photo.Bytes())
		require.NoError(t, err)
	}
	require.NoError(t, writer.Close())
	request := httptest.NewRequest(http.MethodPost, "/identity/"+performanceSession, &body)
	request.Header.Set("Authorization", "Bearer test-token")
	request.Header.Set("Content-Type", writer.FormDataContentType())
	return request
}

func TestIdentityUploadsOverlapAndFinishBeforeCommitOrRollback(t *testing.T) {
	for _, fail := range []bool{false, true} {
		name := "success"
		if fail {
			name = "rollback"
		}
		t.Run(name, func(t *testing.T) {
			store := &parallelEvidenceStore{
				started: make(chan string, 2), release: make(chan struct{}),
				reserved: map[string]bool{}, finished: map[string]bool{}, deleted: map[string]bool{}, fail: fail,
			}
			handler := ports.NewOperationsHandler(domain.OperationsOptions{
				Store:         store,
				EncryptionKey: bytes.Repeat([]byte{1}, 32), HMACKey: bytes.Repeat([]byte{2}, 32),
			}, opsVerifier{})
			app := ports.NewHTTPApp()
			app.Post("/identity/:id", handler.Submit)
			request := identityPerformanceRequest(t)
			type outcome struct {
				response *http.Response
				err      error
			}
			done := make(chan outcome, 1)
			go func() {
				response, err := app.Test(request)
				done <- outcome{response, err}
			}()
			started := 0
			deadline := time.NewTimer(300 * time.Millisecond)
		loop:
			for started < 2 {
				select {
				case <-store.started:
					started++
				case <-deadline.C:
					break loop
				}
			}
			deadline.Stop()
			close(store.release)
			result := <-done
			require.NoError(t, result.err)
			defer result.response.Body.Close()
			require.Equal(t, 2, started, "both uploads must start before either is released")
			require.False(t, store.violation, "reserve before upload; join both workers before commit or rollback")
			if fail {
				require.Equal(t, http.StatusServiceUnavailable, result.response.StatusCode)
				require.False(t, store.submitted)
				require.Len(t, store.deleted, 2)
			} else {
				require.Equal(t, http.StatusCreated, result.response.StatusCode)
				require.True(t, store.submitted)
				require.Empty(t, store.deleted)
			}
		})
	}
}
