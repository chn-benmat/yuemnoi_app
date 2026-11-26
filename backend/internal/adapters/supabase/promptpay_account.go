package supabase

import (
	"context"
	"fmt"
	"log/slog"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

type promptPayAccountRow struct {
	Phone                string `json:"phone"`
	NationalIDCiphertext string `json:"national_id_ciphertext"`
}

func (r *supabaseRentalRepository) GetPromptPayAccount(ctx context.Context, userID string) (domain.PromptPayAccount, error) {
	var rows []promptPayAccountRow
	err := r.client.DB.From("rental_promptpay_account_tb").Select("phone", "national_id_ciphertext").
		Eq("user_id", userID).ExecuteWithContext(ctx, &rows)
	if err != nil {
		return domain.PromptPayAccount{}, fmt.Errorf("read PromptPay account: %w", err)
	}
	if len(rows) == 0 {
		return domain.PromptPayAccount{}, nil
	}
	if rows[0].NationalIDCiphertext == "" {
		return domain.PromptPayAccount{IDType: "phone", Phone: rows[0].Phone}, nil
	}
	nationalID, err := r.decryptPromptPayNationalID(userID, rows[0].NationalIDCiphertext)
	if err != nil || !domain.IsPromptPayNationalID(nationalID) {
		// ให้เจ้าของบัญชีเปลี่ยนข้อมูลได้แม้อ่านเลขบัตรเดิมไม่ได้
		slog.WarnContext(ctx, "could not read stored PromptPay national ID")
		return domain.PromptPayAccount{IDType: "national_id"}, nil
	}
	return domain.PromptPayAccount{IDType: "national_id", NationalIDLastFour: nationalID[len(nationalID)-4:]}, nil
}

func (r *supabaseRentalRepository) UpdatePromptPayAccount(ctx context.Context, userID, phone, nationalID string) (domain.PromptPayAccount, error) {
	row := map[string]any{"user_id": userID, "phone": nil, "national_id_ciphertext": nil}
	account := domain.PromptPayAccount{IDType: "phone", Phone: phone}
	if nationalID != "" {
		if !domain.IsPromptPayNationalID(nationalID) {
			return domain.PromptPayAccount{}, fmt.Errorf("PromptPay national ID is invalid")
		}
		ciphertext, err := r.encryptPromptPayNationalID(userID, nationalID)
		if err != nil {
			return domain.PromptPayAccount{}, err
		}
		row["national_id_ciphertext"] = ciphertext
		account = domain.PromptPayAccount{IDType: "national_id", NationalIDLastFour: nationalID[len(nationalID)-4:]}
	} else {
		row["phone"] = phone
	}
	var saved []promptPayAccountRow
	if err := r.client.DB.From("rental_promptpay_account_tb").Upsert(row).ExecuteWithContext(ctx, &saved); err != nil {
		return domain.PromptPayAccount{}, fmt.Errorf("save PromptPay account: %w", err)
	}
	if len(saved) != 1 {
		return domain.PromptPayAccount{}, fmt.Errorf("save PromptPay account returned no matching row")
	}
	return account, nil
}
