package supabase

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	postgrest "github.com/nedpals/supabase-go/postgrest/pkg"
)

const rentalEvidenceBucket = "rental_evidence"

func rentalLifecycleError(err error) error {
	var e *postgrest.RequestError
	if errors.As(err, &e) {
		switch {
		case strings.Contains(e.Message, "rental_forbidden"):
			return domain.ErrRentalForbidden
		case strings.Contains(e.Message, "rental_not_found"):
			return domain.ErrRentalNotFound
		case strings.Contains(e.Message, "rental_transition"):
			return domain.ErrRentalStatusTransition
		case strings.Contains(e.Message, "rental_not_started"):
			return domain.ErrRentalNotStarted
		case strings.Contains(e.Message, "return_penalty_no_amount"):
			return domain.ErrReturnPenaltyNoAmount
		case strings.Contains(e.Message, "invalid_rental"):
			return domain.ErrInvalidRental
		}
	}
	return fmt.Errorf("rental lifecycle: %w", err)
}

func (r *supabaseRentalRepository) lifecycleRPC(ctx context.Context, user string, id int64, action string, data map[string]any) (map[string]any, error) {
	var result map[string]any
	err := r.client.DB.Rpc("rental_lifecycle_action", map[string]any{"p_actor": user, "p_booking": id, "p_action": action, "p_data": data}).ExecuteWithContext(ctx, &result)
	if err != nil {
		return nil, rentalLifecycleError(err)
	}
	if result["error"] == "invalid_return_token" {
		return nil, domain.ErrRentalReturnToken
	}
	return result, nil
}

func (r *supabaseRentalRepository) rentalAction(ctx context.Context, user string, id int64, action string, data map[string]any) (*domain.RentalOrder, error) {
	result, err := r.lifecycleRPC(ctx, user, id, action, data)
	if err != nil {
		return nil, err
	}
	return rentalOrderFromAction(result)
}

func rentalOrderFromAction(result map[string]any) (*domain.RentalOrder, error) {
	raw, err := json.Marshal(result["booking"])
	if err != nil {
		return nil, err
	}
	var order domain.RentalOrder
	if err = json.Unmarshal(raw, &order); err != nil {
		return nil, err
	}
	if order.ID <= 0 {
		return nil, fmt.Errorf("rental lifecycle returned no booking")
	}
	return &order, nil
}

func (r *supabaseRentalRepository) RentalReturnSession(ctx context.Context, user string, id int64) (map[string]any, error) {
	result, err := r.lifecycleRPC(ctx, user, id, "session", map[string]any{})
	if err != nil {
		return nil, err
	}
	state, _ := result["return_state"].(map[string]any)
	for _, field := range []string{"photos", "cancellation_photos"} {
		photos, _ := state[field].([]any)
		for _, raw := range photos {
			photo, _ := raw.(map[string]any)
			path, _ := photo["object_path"].(string)
			if path == "" {
				continue
			}
			signed, signErr := r.signRentalEvidence(ctx, path)
			if signErr != nil {
				return nil, signErr
			}
			photo["imageUrl"] = signed
			delete(photo, "object_path")
		}
	}
	return result, nil
}

func (r *supabaseRentalRepository) signRentalEvidence(ctx context.Context, path string) (string, error) {
	body, _ := json.Marshal(map[string]int{"expiresIn": 900})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, r.storage.baseURL+"/storage/v1/object/sign/"+escapedStoragePath(rentalEvidenceBucket, path), bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	res, err := r.storage.do(req)
	if err != nil {
		return "", err
	}
	defer res.Body.Close()
	var signed struct {
		URL string `json:"signedURL"`
	}
	if err = json.NewDecoder(io.LimitReader(res.Body, 1<<20)).Decode(&signed); err != nil {
		return "", err
	}
	if signed.URL == "" {
		return "", fmt.Errorf("missing rental evidence URL")
	}
	if strings.HasPrefix(signed.URL, "/") {
		return r.storage.baseURL + "/storage/v1" + strings.TrimPrefix(signed.URL, "/storage/v1"), nil
	}
	return signed.URL, nil
}

func (r *supabaseRentalRepository) uploadRentalEvidence(ctx context.Context, user string, id int64, kind string, images []domain.ItemImage) ([]map[string]any, []string, error) {
	photos := make([]map[string]any, 0, len(images))
	paths := make([]string, 0, len(images))
	for i, image := range images {
		random := make([]byte, 16)
		if _, err := rand.Read(random); err != nil {
			return nil, paths, err
		}
		path := fmt.Sprintf("%s/%d/%s_%s.jpg", user, id, kind, hex.EncodeToString(random))
		if err := r.storage.upload(ctx, rentalEvidenceBucket, path, image.Data, "image/jpeg"); err != nil {
			return nil, paths, err
		}
		paths = append(paths, path)
		photos = append(photos, map[string]any{"object_path": path, "angleKey": fmt.Sprintf("angle_%d", i+1), "angleTitle": fmt.Sprintf("ภาพตรวจสภาพ %d", i+1), "timestamp": time.Now().UTC(), "challengeCode": fmt.Sprintf("YM-%05d", id)})
	}
	return photos, paths, nil
}

func (r *supabaseRentalRepository) cleanupRentalEvidence(ctx context.Context, paths []string) {
	cleanup, cancel := context.WithTimeout(context.WithoutCancel(ctx), storageCleanupTimeout)
	defer cancel()
	_ = r.storage.remove(cleanup, rentalEvidenceBucket, paths)
}

func (r *supabaseRentalRepository) SubmitRentalEvidence(ctx context.Context, user string, id int64, images []domain.ItemImage, checklist map[string]bool) (*domain.RentalOrder, error) {
	if len(images) != 3 || !checklist["power_on"] || !checklist["no_new_cracks"] || !checklist["accessories_complete"] {
		return nil, domain.ErrInvalidRental
	}
	if _, err := r.lifecycleRPC(ctx, user, id, "authorize_evidence", map[string]any{}); err != nil {
		return nil, err
	}
	photos, paths, err := r.uploadRentalEvidence(ctx, user, id, "return", images)
	if err != nil {
		r.cleanupRentalEvidence(ctx, paths)
		return nil, err
	}
	order, err := r.rentalAction(ctx, user, id, "evidence", map[string]any{"photos": photos, "checklist": checklist})
	if err != nil && knownRentalRejection(err) {
		r.cleanupRentalEvidence(ctx, paths)
	}
	return order, err
}

func rentalTokenHash(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

// หากคำตอบเครือข่ายหายหลัง commit ให้เก็บไฟล์ไว้ก่อน เพื่อไม่ลบหลักฐานที่ DB อ้างอิงแล้ว
func knownRentalRejection(err error) bool {
	return errors.Is(err, domain.ErrRentalForbidden) || errors.Is(err, domain.ErrRentalStatusTransition) ||
		errors.Is(err, domain.ErrInvalidRental) || errors.Is(err, domain.ErrRentalNotFound)
}

func (r *supabaseRentalRepository) InspectRentalReturn(ctx context.Context, user string, id int64) (*domain.RentalReturnChallenge, error) {
	random := make([]byte, 24)
	if _, err := rand.Read(random); err != nil {
		return nil, err
	}
	n, err := rand.Int(rand.Reader, big.NewInt(900000))
	if err != nil {
		return nil, err
	}
	challenge := &domain.RentalReturnChallenge{Token: "YUEMNOI_RETURN_" + strconv.FormatInt(id, 10) + "_" + hex.EncodeToString(random), OTP: strconv.FormatInt(n.Int64()+100000, 10), ExpiresAt: time.Now().UTC().Add(5 * time.Minute)}
	_, err = r.rentalAction(ctx, user, id, "inspect", map[string]any{"token_hash": rentalTokenHash(challenge.Token), "otp_hash": rentalTokenHash(challenge.OTP), "expires_at": challenge.ExpiresAt})
	if err != nil {
		return nil, err
	}
	return challenge, nil
}

func (r *supabaseRentalRepository) ConfirmRentalReceipt(ctx context.Context, user string, id int64) (*domain.RentalOrder, error) {
	return r.rentalAction(ctx, user, id, "confirm_receipt", map[string]any{})
}

func (r *supabaseRentalRepository) CompleteRentalReturn(ctx context.Context, user string, id int64, token string) (*domain.RentalOrder, error) {
	if strings.TrimSpace(token) == "" || len(token) > 200 {
		return nil, domain.ErrInvalidRental
	}
	return r.rentalAction(ctx, user, id, "complete", map[string]any{"token_hash": rentalTokenHash(strings.TrimSpace(token))})
}

func (r *supabaseRentalRepository) CancelRental(ctx context.Context, user string, id int64, reason, note string, images []domain.ItemImage) (*domain.RentalOrder, error) {
	if len(images) < 1 || len(images) > 5 || len([]rune(strings.TrimSpace(reason))) < 3 || len([]rune(reason)) > 500 || len([]rune(note)) > 2000 {
		return nil, domain.ErrInvalidRental
	}
	if _, err := r.lifecycleRPC(ctx, user, id, "authorize_cancel", map[string]any{}); err != nil {
		return nil, err
	}
	photos, paths, err := r.uploadRentalEvidence(ctx, user, id, "cancel", images)
	if err != nil {
		r.cleanupRentalEvidence(ctx, paths)
		return nil, err
	}
	order, err := r.rentalAction(ctx, user, id, "cancel", map[string]any{"reason": strings.TrimSpace(reason), "note": strings.TrimSpace(note), "photos": photos})
	if err != nil && knownRentalRejection(err) {
		r.cleanupRentalEvidence(ctx, paths)
	}
	return order, err
}
