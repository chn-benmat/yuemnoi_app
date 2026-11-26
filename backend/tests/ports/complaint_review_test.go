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

	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
)

type complaintReviewStore struct {
	domain.OperationsStore
	rpc  string
	args map[string]any
	err  error
}

func TestAdminComplaintReviewMapsDatabaseConflict(t *testing.T) {
	database := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		_, _ = io.WriteString(w, `{"code":"P0001","message":"complaint_not_open","details":"private context"}`)
	}))
	defer database.Close()
	app := ports.NewHTTPApp()
	store := supabase.NewOperationsRepository(database.URL, "test-service-key")
	handler := ports.NewOperationsHandler(domain.OperationsOptions{Store: store}, rentalConfirmationVerifier{})
	app.Post("/api/admin/actions/:action/:target", handler.Action)
	req := httptest.NewRequest(http.MethodPost, "/api/admin/actions/complaint/baf0cad0-cd80-4806-b6f0-2b4cd3d81af9",
		strings.NewReader(`{"status":"resolved","outcome":"confirmed","reason":"Please fix price"}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer renter-token")
	res, err := app.Test(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(res.Body)
	if res.StatusCode != http.StatusConflict || !strings.Contains(string(body), "complaint_not_open") || strings.Contains(string(body), "private context") {
		t.Fatalf("status=%d body=%s", res.StatusCode, body)
	}
}

func (s *complaintReviewStore) RPC(_ context.Context, name string, args map[string]any) (json.RawMessage, error) {
	s.rpc, s.args = name, args
	return json.RawMessage(`{"ok":true,"strike_count":2}`), s.err
}

func TestAdminComplaintReview(t *testing.T) {
	const id = "baf0cad0-cd80-4806-b6f0-2b4cd3d81af9"
	for _, tc := range []struct {
		name, method, path, rpc, dbError string
		status                           int
	}{
		{"load context", "GET", "/api/admin/complaints?id=" + id, "admin_complaint_context", "", http.StatusOK},
		{"save outcome", "POST", "/api/admin/actions/complaint/" + id, "admin_review_complaint", "", http.StatusOK},
		{"reject changed case", "POST", "/api/admin/actions/complaint/" + id, "admin_review_complaint", "complaint_not_open", http.StatusConflict},
		{"reject invalid case id", "POST", "/api/admin/actions/complaint/invalid", "", "", http.StatusBadRequest},
	} {
		t.Run(tc.name, func(t *testing.T) {
			store := &complaintReviewStore{}
			if tc.dbError != "" {
				store.err = errors.New(tc.dbError)
			}
			app := ports.NewHTTPApp()
			handler := ports.NewOperationsHandler(domain.OperationsOptions{Store: store}, rentalConfirmationVerifier{})
			app.Get("/api/admin/:module", handler.Read)
			app.Post("/api/admin/actions/:action/:target", handler.Action)
			req := httptest.NewRequest(tc.method, tc.path, strings.NewReader(`{"status":"resolved","outcome":"confirmed","reason":"Please fix price"}`))
			req.Header.Set("Authorization", "Bearer renter-token")
			req.Header.Set("Content-Type", "application/json")
			response, err := app.Test(req)
			if err != nil {
				t.Fatal(err)
			}
			defer response.Body.Close()
			body, _ := io.ReadAll(response.Body)
			if response.StatusCode != tc.status || store.rpc != tc.rpc {
				t.Fatalf("status=%d RPC=%s body=%s", response.StatusCode, store.rpc, body)
			}
			if tc.rpc != "" && (store.args["p_complaint"] != id || store.args["p_actor"] != "renter") {
				t.Fatalf("unexpected arguments: %v", store.args)
			}
			if tc.method == "POST" && tc.rpc != "" && store.args["p_data"].(map[string]any)["outcome"] != "confirmed" {
				t.Fatalf("review outcome not forwarded: %v", store.args)
			}
			if tc.dbError != "" && !strings.Contains(string(body), tc.dbError) {
				t.Fatalf("review conflict missing from response: %s", body)
			}
		})
	}
}
