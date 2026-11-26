package ports_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	sb "github.com/nedpals/supabase-go"
	"github.com/stretchr/testify/require"
)

type incomeAuthGateway struct{ domain.AuthGateway }

func (incomeAuthGateway) AppUserIDFromToken(ctx context.Context, token string) (string, error) {
	return (handoverPaymentVerifier{}).UserIDFromToken(ctx, token)
}

func TestRentalIncomeReadsOnlyReceiptsForAuthenticatedAccount(t *testing.T) {
	database := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet || r.URL.Path != "/rest/v1/rental_handover_payment_tb" {
			t.Errorf("expected a read from the receipt table, got %s %s", r.Method, r.URL.Path)
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		query := r.URL.Query()
		if query.Get("select") != "booking_id,confirmed_at,booking:booking_tb!inner(total_price,payment_method,item:item_tb(item_name))" ||
			query.Get("order") != "booking_id.asc" || r.Header.Get("Range") != "0-199" {
			t.Errorf("receipt query must load booking details in bounded booking ID order: %v", query)
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		switch query.Get("confirmed_by") {
		case "eq.owner":
			switch query.Get("booking_id") {
			case "gt.0":
				fmt.Fprint(w, `[{"booking_id":12,"confirmed_at":"2026-11-25T10:00:00Z","booking":{"total_price":150,"payment_method":"cash","item":{"item_name":"กล้อง"}}}]`)
			case "gt.12":
				fmt.Fprint(w, `[{"booking_id":14,"confirmed_at":"2026-11-26T12:30:00Z","booking":{"total_price":200,"payment_method":"promptpay","item":{"item_name":"ขาตั้ง"}}}]`)
			case "gt.14":
				fmt.Fprint(w, `[]`)
			default:
				t.Errorf("invalid booking cursor: %v", query)
				w.WriteHeader(http.StatusBadRequest)
			}
		case "eq.renter":
			fmt.Fprint(w, `[]`)
		default:
			t.Errorf("read must be scoped to the authenticated account: %v", query)
			w.WriteHeader(http.StatusBadRequest)
		}
	}))
	defer database.Close()

	repo := supabase.NewSupabaseRentalRepository(sb.CreateClient(database.URL, "test-service-role-key"))
	app := ports.SetupRouter(nil, incomeAuthGateway{}, nil, repo, nil, nil, "test-app-secret")
	defer app.Shutdown()

	for _, tc := range []struct {
		token           string
		status          int
		total           int64
		confirmedMethod []string
	}{
		{token: "", status: http.StatusUnauthorized},
		{token: "renter", status: http.StatusOK, confirmedMethod: []string{}},
		{token: "owner", status: http.StatusOK, total: 35000, confirmedMethod: []string{"promptpay", "cash"}},
	} {
		t.Run(tc.token, func(t *testing.T) {
			request := httptest.NewRequest(http.MethodGet, "/api/rentals/income?user_id=other-account", nil)
			request.Header.Set("X-App-Secret", "test-app-secret")
			if tc.token != "" {
				request.Header.Set("Authorization", "Bearer "+tc.token)
			}
			res, err := app.Test(request)
			require.NoError(t, err)
			defer res.Body.Close()
			require.Equal(t, tc.status, res.StatusCode)
			if res.StatusCode != http.StatusOK {
				return
			}
			require.Equal(t, "private, no-store", res.Header.Get("Cache-Control"))
			var summary struct {
				TotalSatang  int64 `json:"total_satang"`
				Transactions []struct {
					ItemName      string `json:"item_name"`
					PaymentMethod string `json:"payment_method"`
				} `json:"transactions"`
			}
			require.NoError(t, json.NewDecoder(res.Body).Decode(&summary))
			require.Equal(t, tc.total, summary.TotalSatang)
			require.NotNil(t, summary.Transactions)
			require.Len(t, summary.Transactions, len(tc.confirmedMethod))
			for index, method := range tc.confirmedMethod {
				require.Equal(t, method, summary.Transactions[index].PaymentMethod)
			}
			if tc.token == "owner" {
				require.Equal(t, "ขาตั้ง", summary.Transactions[0].ItemName)
			}
		})
	}
}
