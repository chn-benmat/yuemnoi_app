package supabase

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

type operationsRepository struct {
	base, key string
	client    *http.Client
}

func NewOperationsRepository(base, key string) domain.OperationsStore {
	return &operationsRepository{strings.TrimRight(base, "/"), key, &http.Client{Timeout: 30 * time.Second}}
}
func (r *operationsRepository) request(ctx context.Context, method, path string, body []byte, content string) ([]byte, string, error) {
	req, err := http.NewRequestWithContext(ctx, method, r.base+path, bytes.NewReader(body))
	if err != nil {
		return nil, "", err
	}
	req.Header.Set("apikey", r.key)
	req.Header.Set("Authorization", "Bearer "+r.key)
	req.Header.Set("Content-Type", content)
	res, err := r.client.Do(req)
	if err != nil {
		return nil, "", errors.New("operations_unavailable")
	}
	defer res.Body.Close()
	data, err := io.ReadAll(io.LimitReader(res.Body, 8<<20))
	if err != nil {
		return nil, "", err
	}
	if res.StatusCode >= 300 {
		if method == http.MethodDelete && res.StatusCode == 404 {
			return nil, "", nil
		}
		// ส่งกลับเฉพาะรหัสที่กำหนดไว้ ไม่เผยแพร่ข้อความ SQL หรือข้อมูลผู้ใช้
		if strings.Contains(string(data), "invalid_settings") {
			return nil, "", errors.New("invalid_settings")
		}
		for _, code := range []string{"citizen_id_locked", "staff_required", "pilot_invite_required", "account_suspended", "active_request_exists", "capture_expired", "request_not_pending", "manual_review_required", "self_review_forbidden", "identity_duplicate", "card_expired", "card_validity_required", "last_staff_required", "self_suspend_forbidden", "reason_required", "evidence_unavailable", "invalid_date_range", "unknown_module", "unknown_action"} {
			if strings.Contains(string(data), code) {
				return nil, "", errors.New(code)
			}
		}
		return nil, "", errors.New("operations_unavailable")
	}
	return data, res.Header.Get("Content-Type"), nil
}
func (r *operationsRepository) RPC(ctx context.Context, name string, args map[string]any) (json.RawMessage, error) {
	body, err := json.Marshal(args)
	if err != nil {
		return nil, err
	}
	data, _, err := r.request(ctx, "POST", "/rest/v1/rpc/"+url.PathEscape(name), body, "application/json")
	return data, err
}
func (r *operationsRepository) ReadItemImages(ctx context.Context, itemIDs []int64) (map[int64][]string, error) {
	images := make(map[int64][]string, len(itemIDs))
	if len(itemIDs) == 0 {
		return images, nil
	}
	ids := make([]string, 0, len(itemIDs))
	seen := make(map[int64]struct{}, len(itemIDs))
	for _, id := range itemIDs {
		if id <= 0 {
			continue
		}
		if _, exists := seen[id]; exists {
			continue
		}
		seen[id] = struct{}{}
		ids = append(ids, strconv.FormatInt(id, 10))
	}
	if len(ids) == 0 {
		return images, nil
	}
	query := url.Values{}
	query.Set("select", "id,item_image_url")
	query.Set("id", "in.("+strings.Join(ids, ",")+")")
	data, _, err := r.request(ctx, http.MethodGet, "/rest/v1/item_tb?"+query.Encode(), nil, "application/json")
	if err != nil {
		return nil, err
	}
	var rows []struct {
		ID           int64    `json:"id"`
		ItemImageURL []string `json:"item_image_url"`
	}
	if err := json.Unmarshal(data, &rows); err != nil {
		return nil, err
	}
	for _, row := range rows {
		images[row.ID] = row.ItemImageURL
	}
	return images, nil
}
func (r *operationsRepository) UploadEvidence(ctx context.Context, path string, data []byte, content string) error {
	_, _, err := r.request(ctx, "POST", "/storage/v1/object/identity-private/"+path, data, content)
	return err
}
func (r *operationsRepository) ReadEvidence(ctx context.Context, path string) ([]byte, string, error) {
	return r.request(ctx, "GET", "/storage/v1/object/authenticated/identity-private/"+path, nil, "application/json")
}
func (r *operationsRepository) DeleteEvidence(ctx context.Context, path string) error {
	body, _ := json.Marshal(map[string]any{"prefixes": []string{path}})
	_, _, err := r.request(ctx, "DELETE", "/storage/v1/object/identity-private", body, "application/json")
	return err
}
