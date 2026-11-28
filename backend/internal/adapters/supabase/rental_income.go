package supabase

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"sort"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

type rentalIncomeRow struct {
	BookingID     int64     `json:"booking_id"`
	ConfirmedAt   time.Time `json:"confirmed_at"`
	TotalPrice    *int64    `json:"total_price"`
	PaymentMethod string    `json:"payment_method"`
	ItemName      string    `json:"item_name"`
}

func (r *supabaseRentalRepository) GetRentalIncome(ctx context.Context, userID string) (domain.RentalIncomeSummary, error) {
	const pageSize = 200
	summary := domain.RentalIncomeSummary{Transactions: []domain.RentalIncomeReceipt{}}
	var lastBookingID int64
	for {
		var rows []rentalIncomeRow
		// RPC อ่านตารางการรับเงินตรงด้วย index ของผู้ยืนยัน และแบ่งหน้าตาม booking_id
		err := r.client.DB.Rpc("rental_income_receipts", map[string]any{
			"p_owner": userID, "p_after": lastBookingID, "p_limit": pageSize,
		}).ExecuteWithContext(ctx, &rows)
		if err != nil {
			// ตัด URL ของคำขอออกจากข้อผิดพลาดก่อนบันทึก เพราะมีรหัสบัญชีอยู่ในตัวกรอง
			var requestErr *url.Error
			if errors.As(err, &requestErr) {
				err = requestErr.Err
			}
			return domain.RentalIncomeSummary{}, fmt.Errorf("read rental income receipts: %w", err)
		}
		if len(rows) == 0 {
			break
		}

		for _, row := range rows {
			if row.TotalPrice == nil {
				return domain.RentalIncomeSummary{}, fmt.Errorf("receipt for booking %d has no total price", row.BookingID)
			}
			method := row.PaymentMethod
			if method == "" {
				method = "cash"
			}
			amount := *row.TotalPrice * 100
			summary.Transactions = append(summary.Transactions, domain.RentalIncomeReceipt{
				ItemName: row.ItemName, ConfirmedAt: row.ConfirmedAt,
				PaymentMethod: method, AmountSatang: amount,
			})
			summary.TotalSatang += amount
		}
		lastBookingID = rows[len(rows)-1].BookingID
	}
	sort.SliceStable(summary.Transactions, func(i, j int) bool {
		return summary.Transactions[i].ConfirmedAt.After(summary.Transactions[j].ConfirmedAt)
	})
	return summary, nil
}
