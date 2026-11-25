package supabase

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"fmt"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

func (r *supabaseRentalRepository) HandoverPayment(ctx context.Context, userID string, rentalID int64, confirm bool) (domain.RentalHandoverPayment, error) {
	payment, err := r.handoverPayment(ctx, userID, map[string]any{
		"p_actor": userID, "p_booking": rentalID, "p_confirm": confirm,
	})
	if err == nil && confirm && (payment.Status != "active" || !payment.PaymentConfirmed) {
		return domain.RentalHandoverPayment{}, fmt.Errorf("payment confirmation RPC did not activate rental")
	}
	return payment, err
}

func (r *supabaseRentalRepository) SavePromptPayAccount(ctx context.Context, userID string, rentalID int64, phone, nationalID string) (domain.RentalHandoverPayment, error) {
	params := map[string]any{"p_actor": userID, "p_booking": rentalID, "p_confirm": false}
	if nationalID != "" {
		key, err := r.promptPayAccountKey(userID)
		if err != nil {
			return domain.RentalHandoverPayment{}, err
		}
		ciphertext, err := domain.EncryptIdentity([]byte(nationalID), key)
		if err != nil {
			return domain.RentalHandoverPayment{}, fmt.Errorf("encrypt PromptPay national ID: %w", err)
		}
		params["p_promptpay_phone"] = nil
		params["p_national_id_ciphertext"] = ciphertext
	} else {
		params["p_promptpay_phone"] = phone
	}
	return r.handoverPayment(ctx, userID, params)
}

func (r *supabaseRentalRepository) handoverPayment(ctx context.Context, userID string, params map[string]any) (domain.RentalHandoverPayment, error) {
	var result struct {
		domain.RentalHandoverPayment
		NationalIDCiphertext string `json:"national_id_ciphertext"`
	}
	err := r.client.DB.Rpc("rental_handover_payment", params).ExecuteWithContext(ctx, &result)
	payment := result.RentalHandoverPayment
	if err != nil {
		return payment, rentalLifecycleError(err)
	}
	if payment.Status == "" || payment.PaymentMethod == "" {
		return payment, fmt.Errorf("handover payment RPC returned incomplete data")
	}
	if payment.CanCollectPayment && result.NationalIDCiphertext != "" {
		key, err := r.promptPayAccountKey(userID)
		if err != nil {
			return payment, err
		}
		decrypted, err := domain.DecryptIdentity(result.NationalIDCiphertext, key)
		if err != nil {
			return payment, fmt.Errorf("decrypt PromptPay national ID: %w", err)
		}
		payment.PromptPayNationalID = string(decrypted)
	}
	return payment, nil
}

func (r *supabaseRentalRepository) promptPayAccountKey(userID string) ([]byte, error) {
	if len(r.promptPayKey) != 32 {
		return nil, fmt.Errorf("PromptPay national ID encryption key is unavailable")
	}
	// แยกคีย์จากงานยืนยันตัวตน และผูกข้อมูลที่เข้ารหัสกับบัญชีผู้รับ
	mac := hmac.New(sha256.New, r.promptPayKey)
	_, _ = mac.Write([]byte("yuemnoi:promptpay-national-id:v1:" + userID))
	return mac.Sum(nil), nil
}
