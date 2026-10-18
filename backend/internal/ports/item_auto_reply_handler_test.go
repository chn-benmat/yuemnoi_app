package ports

import (
	"context"
	"encoding/json"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

type autoReplyRepository struct {
	domain.ItemRepository
	saved *domain.ItemAutoReply
	actor string
}

func (r *autoReplyRepository) GetAutoReply(_ context.Context, _ int64, actor string) (*domain.ItemAutoReply, error) {
	if actor != "owner" {
		return nil, domain.ErrItemNotFound
	}
	return &domain.ItemAutoReply{Enabled: true, Message: "สวัสดี"}, nil
}
func (r *autoReplyRepository) SaveAutoReply(_ context.Context, _ int64, actor string, value domain.ItemAutoReply) (*domain.ItemAutoReply, error) {
	if actor != "owner" {
		return nil, domain.ErrItemNotFound
	}
	r.saved, r.actor = &value, actor
	return &value, nil
}

func TestItemAutoReplyRequiresOwnerAndValidSettings(t *testing.T) {
	for _, tc := range []struct {
		name, method, token, body string
		status                    int
	}{
		{"load", "GET", "owner", "", 200},
		{"no auth", "GET", "", "", 401},
		{"cannot read another owner's settings", "GET", "stranger", "", 404},
		{"save trimmed", "PUT", "owner", `{"enabled":true,"message":"  สวัสดี  "}`, 200},
		{"turn off retains message", "PUT", "owner", `{"enabled":false,"message":"เก็บไว้"}`, 200},
		{"off can be empty", "PUT", "owner", `{"enabled":false,"message":""}`, 200},
		{"save needs auth", "PUT", "", `{"enabled":true,"message":"hello"}`, 401},
		{"cannot change another owner", "PUT", "stranger", `{"enabled":true,"message":"hello"}`, 404},
		{"on cannot be blank", "PUT", "owner", `{"enabled":true,"message":" \n "}`, 400},
		{"requires both fields", "PUT", "owner", `{"enabled":false}`, 400},
		{"invalid boolean", "PUT", "owner", `{"enabled":"true","message":"hello"}`, 400},
		{"limit Unicode", "PUT", "owner", `{"enabled":true,"message":"` + strings.Repeat("ก", 501) + `"}`, 400},
		{"accepts 500 Unicode characters", "PUT", "owner", `{"enabled":true,"message":"` + strings.Repeat("ก", 500) + `"}`, 200},
	} {
		t.Run(tc.name, func(t *testing.T) {
			repo := &autoReplyRepository{}
			app := NewHTTPApp()
			defer app.Shutdown()
			h := NewItemHandler(repo, itemManagementVerifier{})
			app.Get("/items/:id/auto-reply", h.GetAutoReply)
			app.Put("/items/:id/auto-reply", h.SaveAutoReply)
			req := httptest.NewRequest(tc.method, "/items/7/auto-reply", strings.NewReader(tc.body))
			req.Header.Set("Content-Type", "application/json")
			if tc.token != "" {
				req.Header.Set("Authorization", "Bearer "+tc.token)
			}
			response, err := app.Test(req)
			if err != nil {
				t.Fatal(err)
			}
			defer response.Body.Close()
			if response.StatusCode != tc.status {
				t.Fatalf("status %d, want %d", response.StatusCode, tc.status)
			}
			if tc.method == "PUT" && tc.status == 200 {
				var input domain.ItemAutoReply
				_ = json.Unmarshal([]byte(tc.body), &input)
				if repo.saved == nil || repo.saved.Enabled != input.Enabled || repo.saved.Message != strings.TrimSpace(input.Message) || repo.actor != "owner" {
					t.Fatalf("unexpected saved settings: %+v", repo.saved)
				}
			} else if repo.saved != nil {
				t.Fatal("invalid settings were saved")
			}
		})
	}
}
