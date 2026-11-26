package supabase_test

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	supabase "github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	sb "github.com/nedpals/supabase-go"
)

func TestConfirmRentalPaymentRequiresActiveBooking(t *testing.T) {
	for _, status := range []string{"confirmed", "active"} {
		t.Run(status, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				var args map[string]any
				if r.URL.Path != "/rest/v1/rpc/rental_handover_payment" ||
					json.NewDecoder(r.Body).Decode(&args) != nil ||
					args["p_confirm"] != true || args["p_actor"] != "owner" || args["p_booking"] != float64(25) {
					t.Error("payment confirmation must use the authenticated owner and one database RPC")
				}
				w.Header().Set("Content-Type", "application/json")
				fmt.Fprintf(w, `{"payment_method":"cash","status":%q,"payment_confirmed":true}`, status)
			}))
			defer server.Close()
			repo := supabase.NewSupabaseRentalRepository(sb.CreateClient(server.URL, "test-key")).(domain.RentalHandoverRepository)
			payment, err := repo.HandoverPayment(context.Background(), "owner", 25, true)
			if status == "confirmed" && err == nil {
				t.Fatal("payment confirmation must only succeed once the rental is active")
			}
			if status == "active" && (err != nil || payment.Status != "active" || !payment.PaymentConfirmed) {
				t.Fatalf("active rental was not returned: payment=%+v err=%v", payment, err)
			}
		})
	}
}

func TestPromptPayNationalIDEncryptedBeforeDatabaseWrite(t *testing.T) {
	const nationalID = "1234567890121"
	var ciphertext string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var args map[string]any
		if r.URL.Path != "/rest/v1/rpc/rental_handover_payment" || json.NewDecoder(r.Body).Decode(&args) != nil {
			t.Error("unexpected handover payment RPC")
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		if value, supplied := args["p_national_id_ciphertext"]; supplied {
			ciphertext, _ = value.(string)
			if ciphertext == "" || strings.Contains(ciphertext, nationalID) || args["p_promptpay_phone"] != nil {
				t.Error("request must carry only encrypted account data")
			}
		}
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"status":"confirmed","payment_method":"promptpay","can_collect_payment":true,"national_id_ciphertext":%q}`, ciphertext)
	}))
	defer server.Close()

	keys := supabase.RentalRepositoryKeys{PromptPayEncryption: []byte(strings.Repeat("x", 32))}
	repo := supabase.NewSupabaseRentalRepository(sb.CreateClient(server.URL, "test-key"), keys).(domain.RentalHandoverRepository)
	ctx := context.Background()
	saved, err := repo.SavePromptPayAccount(ctx, "owner", 25, "", nationalID)
	if err != nil || saved.PromptPayNationalID != nationalID {
		t.Fatalf("saving encrypted account failed: %v", err)
	}
	saved, err = repo.HandoverPayment(ctx, "owner", 26, false)
	if err != nil || saved.PromptPayNationalID != nationalID {
		t.Fatalf("reading encrypted account failed: %v", err)
	}
	if _, err := repo.HandoverPayment(ctx, "different-owner", 27, false); err == nil {
		t.Fatal("a different account must not be able to decrypt the saved national ID")
	}
}

func TestUnreadablePromptPayNationalIDCanBeReplaced(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.Method == http.MethodGet {
			fmt.Fprint(w, `[{"phone":null,"national_id_ciphertext":"old-ciphertext"}]`)
			return
		}
		fmt.Fprint(w, `[{"phone":"0812345678","national_id_ciphertext":null}]`)
	}))
	defer server.Close()
	repo := supabase.NewSupabaseRentalRepository(sb.CreateClient(server.URL, "test-key")).(domain.PromptPayAccountRepository)
	ctx := context.Background()
	account, err := repo.GetPromptPayAccount(ctx, "owner")
	if err != nil || account.IDType != "national_id" || account.NationalIDLastFour != "" {
		t.Fatal("an unreadable national ID should return its type so settings can offer replacement")
	}
	account, err = repo.UpdatePromptPayAccount(ctx, "owner", "0812345678", "")
	if err != nil || account.Phone != "0812345678" {
		t.Fatal("saving a phone number should work without the old encryption key")
	}
}

func TestRentalReturnUsesServerChallengeAndNeverLeaksRawSecretsToDatabase(t *testing.T) {
	var tokenHash, otpHash string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var args struct {
			Actor  string         `json:"p_actor"`
			ID     int64          `json:"p_booking"`
			Action string         `json:"p_action"`
			Data   map[string]any `json:"p_data"`
		}
		if r.URL.Path != "/rest/v1/rpc/rental_lifecycle_action" {
			t.Errorf("unexpected path %s", r.URL.Path)
		}
		json.NewDecoder(r.Body).Decode(&args)
		w.Header().Set("Content-Type", "application/json")
		if args.Action == "inspect" {
			tokenHash, _ = args.Data["token_hash"].(string)
			otpHash, _ = args.Data["otp_hash"].(string)
			if args.Actor != "owner" || args.ID != 25 || len(tokenHash) != 64 || len(otpHash) != 64 {
				t.Errorf("invalid challenge contract %v", args)
			}
			expires, _ := time.Parse(time.RFC3339Nano, args.Data["expires_at"].(string))
			if time.Until(expires) < 4*time.Minute || time.Until(expires) > 6*time.Minute {
				t.Errorf("invalid expiry")
			}
			fmt.Fprint(w, `{"booking":{"id":25,"status":"return_ready"}}`)
		} else if args.Action == "complete" {
			if args.Actor != "renter" || args.Data["token_hash"] != tokenHash {
				t.Error("completion did not hash renter challenge")
			}
			fmt.Fprint(w, `{"booking":{"id":25,"status":"completed"}}`)
		} else {
			t.Errorf("unexpected action %s", args.Action)
		}
	}))
	defer server.Close()
	repo := supabase.NewSupabaseRentalRepository(sb.CreateClient(server.URL, "test-key"))
	challenge, err := repo.InspectRentalReturn(context.Background(), "owner", 25)
	if err != nil {
		t.Fatal(err)
	}
	tokenSum, otpSum := sha256.Sum256([]byte(challenge.Token)), sha256.Sum256([]byte(challenge.OTP))
	if len(challenge.OTP) != 6 || !strings.HasPrefix(challenge.Token, "YUEMNOI_RETURN_25_") || hex.EncodeToString(tokenSum[:]) != tokenHash || hex.EncodeToString(otpSum[:]) != otpHash {
		t.Fatal("challenge contract invalid")
	}
	result, err := repo.CompleteRentalReturn(context.Background(), "renter", 25, challenge.Token)
	if err != nil || result.Status != "completed" {
		t.Fatalf("result %v error %v", result, err)
	}
}

func TestRentalEvidenceAuthorizesBeforeUploadingAndNeverAllowsLegacyCompletion(t *testing.T) {
	requests := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		if !strings.HasSuffix(r.URL.Path, "rental_lifecycle_action") {
			t.Error("unauthorized actor reached storage")
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(403)
		fmt.Fprint(w, `{"code":"42501","message":"rental_forbidden"}`)
	}))
	defer server.Close()
	repo := supabase.NewSupabaseRentalRepository(sb.CreateClient(server.URL, "test-key"))
	_, err := repo.SubmitRentalEvidence(context.Background(), "owner", 25, []domain.ItemImage{{}, {}, {}}, map[string]bool{"power_on": true, "no_new_cracks": true, "accessories_complete": true})
	if err != domain.ErrRentalForbidden || requests != 1 {
		t.Fatalf("error=%v requests=%d", err, requests)
	}
	_, err = repo.UpdateRentalStatus(context.Background(), "renter", 25, "completed")
	if err != domain.ErrRentalStatusTransition || requests != 1 {
		t.Fatal("legacy completion reached database")
	}
}

func TestInvalidReturnTokenIsAnExpectedFailure(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, `{"error":"invalid_return_token"}`) }))
	defer server.Close()
	_, err := supabase.NewSupabaseRentalRepository(sb.CreateClient(server.URL, "test-key")).CompleteRentalReturn(context.Background(), "renter", 25, "123456")
	if err != domain.ErrRentalReturnToken {
		t.Fatalf("error=%v", err)
	}
}
