package supabase

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"sort"
	"strconv"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

type rentalIncomeRow struct {
	BookingID   int64     `json:"booking_id"`
	ConfirmedAt time.Time `json:"confirmed_at"`
	Booking     struct {
		TotalPrice    *int64 `json:"total_price"`
		PaymentMethod string `json:"payment_method"`
		Item          struct {
			Name string `json:"item_name"`
		} `json:"item"`
	} `json:"booking"`
}

func (r *supabaseRentalRepository) GetRentalIncome(ctx context.Context, userID string) (domain.RentalIncomeSummary, error) {
	const pageSize = 200
	summary := domain.RentalIncomeSummary{Transactions: []domain.RentalIncomeReceipt{}}
	var lastBookingID int64
	for {
		var rows []rentalIncomeRow
		err := r.client.DB.From("rental_handover_payment_tb").
			Select("booking_id", "confirmed_at", "booking:booking_tb!inner(total_price,payment_method,item:item_tb(item_name))").
			OrderBy("booking_id", "asc").Limit(pageSize).
			Eq("confirmed_by", userID).Gt("booking_id", strconv.FormatInt(lastBookingID, 10)).
			ExecuteWithContext(ctx, &rows)
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
			if row.Booking.TotalPrice == nil {
				return domain.RentalIncomeSummary{}, fmt.Errorf("receipt for booking %d has no total price", row.BookingID)
			}
			method := row.Booking.PaymentMethod
			if method == "" {
				method = "cash"
			}
			amount := *row.Booking.TotalPrice * 100
			summary.Transactions = append(summary.Transactions, domain.RentalIncomeReceipt{
				ItemName: row.Booking.Item.Name, ConfirmedAt: row.ConfirmedAt,
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
