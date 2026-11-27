package supabase

import (
	"context"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

func (r *supabaseRentalRepository) SaveRentalReturnPenalty(ctx context.Context, userID string, rentalID int64, report domain.RentalReturnPenaltyReport) (domain.RentalReturnPenaltyReport, error) {
	var saved domain.RentalReturnPenaltyReport
	err := r.client.DB.Rpc("rental_return_penalty", map[string]any{
		"p_actor": userID, "p_booking": rentalID, "p_action": "save",
		"p_damaged": report.Damaged, "p_late": report.Late, "p_details": report.Details,
	}).ExecuteWithContext(ctx, &saved)
	if err != nil {
		return saved, rentalLifecycleError(err)
	}
	return saved, nil
}

func (r *supabaseRentalRepository) RentalReturnPenaltyQR(ctx context.Context, userID string, rentalID int64) (string, error) {
	var result struct {
		AmountSatang         int64  `json:"amount_satang"`
		Phone                string `json:"phone"`
		NationalIDCiphertext string `json:"national_id_ciphertext"`
	}
	err := r.client.DB.Rpc("rental_return_penalty", map[string]any{
		"p_actor": userID, "p_booking": rentalID, "p_action": "qr",
	}).ExecuteWithContext(ctx, &result)
	if err != nil {
		return "", rentalLifecycleError(err)
	}
	if result.AmountSatang <= 0 {
		return "", domain.ErrReturnPenaltyNoAmount
	}
	var nationalID string
	if result.NationalIDCiphertext != "" {
		nationalID, err = r.decryptPromptPayNationalID(userID, result.NationalIDCiphertext)
		if err != nil {
			return "", err
		}
	}
	qr := domain.PromptPayQR(result.Phone, nationalID, result.AmountSatang)
	if qr == "" {
		return "", domain.ErrReturnPenaltyNoAccount
	}
	return qr, nil
}
