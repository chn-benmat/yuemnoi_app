package ports_test

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	sbadapter "github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/supabase"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	sbclient "github.com/nedpals/supabase-go"
)

func TestPromptPaySettingsSharesHandoverAccount(t *testing.T) {
	const nationalID = "1234567890121"
	const phone = "0812345678"
	var account map[string]any
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/auth/v1/user":
			if r.Header.Get("Authorization") != "Bearer user-token" {
				w.WriteHeader(http.StatusUnauthorized)
				return
			}
			fmt.Fprintf(w, `{"id":%q,"app_metadata":{}}`, userTestID)
		case "/rest/v1/rental_promptpay_account_tb":
			switch r.Method {
			case http.MethodGet:
				if r.URL.Query().Get("user_id") != "eq."+userTestID {
					t.Error("account lookup must be scoped to the authenticated user")
				}
				if account == nil {
					fmt.Fprint(w, `[]`)
					return
				}
			case http.MethodPost:
				var row map[string]any
				if err := json.NewDecoder(r.Body).Decode(&row); err != nil || row["user_id"] != userTestID || !strings.Contains(r.Header.Get("Prefer"), "resolution=merge-duplicates") {
					t.Error("account write must upsert the authenticated user's row")
				}
				if row["phone"] == nil {
					ciphertext, _ := row["national_id_ciphertext"].(string)
					if ciphertext == "" || strings.Contains(ciphertext, nationalID) {
						t.Error("national ID must be encrypted before storage")
					}
				} else if value, present := row["national_id_ciphertext"]; !present || value != nil {
					t.Error("switching to phone must clear the encrypted national ID")
				}
				account = row
			default:
				t.Errorf("unexpected account method %s", r.Method)
			}
			_ = json.NewEncoder(w).Encode([]map[string]any{account})
		case "/rest/v1/rpc/rental_handover_payment":
			var args map[string]any
			if err := json.NewDecoder(r.Body).Decode(&args); err != nil || args["p_actor"] != userTestID {
				t.Error("handover must use the authenticated user")
			}
			if value, writing := args["p_promptpay_phone"]; writing {
				account = map[string]any{"phone": value, "national_id_ciphertext": args["p_national_id_ciphertext"]}
			}
			_ = json.NewEncoder(w).Encode(map[string]any{
				"status": "confirmed", "payment_method": "promptpay", "can_collect_payment": true,
				"total_satang": 10000, "promptpay_phone": account["phone"], "national_id_ciphertext": account["national_id_ciphertext"],
			})
		default:
			t.Errorf("unexpected database request %s", r.URL.Path)
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer server.Close()

	client := sbclient.CreateClient(server.URL, "test-key")
	auth := sbadapter.NewSupabaseUserRepository(client, "test-key")
	rentals := sbadapter.NewSupabaseRentalRepository(client, sbadapter.RentalRepositoryKeys{PromptPayEncryption: []byte(strings.Repeat("x", 32))})
	app := ports.SetupRouterWithOperations(domain.OperationsOptions{}, nil, auth, nil, rentals, nil, nil, "test-secret")
	defer app.Shutdown()
	const settings = "/api/user/promptpay"
	const handover = "/api/rentals/25/handover-payment"
	for _, tc := range []struct {
		name, method, path, token, body, want string
		status                                int
	}{
		{"missing token", "GET", settings, "", "", "", 401},
		{"invalid token", "PUT", settings, "invalid", `{"promptpay_phone":"` + phone + `"}`, "", 401},
		{"unset account", "GET", settings, "user-token", "", `{}`, 200},
		{"missing identifier", "PUT", settings, "user-token", `{}`, "", 400},
		{"invalid phone", "PUT", settings, "user-token", `{"promptpay_phone":"081"}`, "", 400},
		{"invalid checksum", "PUT", settings, "user-token", `{"promptpay_national_id":"1234567890122"}`, "", 400},
		{"both identifiers", "PUT", settings, "user-token", `{"promptpay_phone":"` + phone + `","promptpay_national_id":"` + nationalID + `"}`, "", 400},
		{"set phone in handover", "PUT", handover, "user-token", `{"promptpay_phone":"` + phone + `"}`, `"promptpay_id_type":"phone"`, 200},
		{"read existing phone in settings", "GET", settings, "user-token", "", `{"promptpay_id_type":"phone","promptpay_phone":"` + phone + `"}`, 200},
		{"switch to national ID in settings", "PUT", settings, "user-token", `{"user_id":"another-user","promptpay_national_id":" ` + nationalID + ` "}`, `{"promptpay_id_type":"national_id","national_id_last_four":"0121"}`, 200},
		{"read masked national ID in settings", "GET", settings, "user-token", "", `{"promptpay_id_type":"national_id","national_id_last_four":"0121"}`, 200},
		{"use settings national ID in handover QR", "GET", handover, "user-token", "", `"promptpay_qr":"` + domain.PromptPayQR("", nationalID, 10000) + `"`, 200},
		{"switch back to phone", "PUT", settings, "user-token", `{"promptpay_phone":"` + phone + `"}`, `{"promptpay_id_type":"phone","promptpay_phone":"` + phone + `"}`, 200},
	} {
		if !t.Run(tc.name, func(t *testing.T) {
			request := httptest.NewRequest(tc.method, tc.path, strings.NewReader(tc.body))
			request.Header.Set("Content-Type", "application/json")
			request.Header.Set("X-App-Secret", "test-secret")
			if tc.token != "" {
				request.Header.Set("Authorization", "Bearer "+tc.token)
			}
			response, err := app.Test(request)
			if err != nil {
				t.Fatal(err)
			}
			defer response.Body.Close()
			body, err := io.ReadAll(response.Body)
			if err != nil || response.StatusCode != tc.status {
				t.Fatalf("status=%d want=%d read error=%v", response.StatusCode, tc.status, err)
			}
			if tc.status != http.StatusOK {
				return
			}
			if !strings.Contains(string(body), tc.want) || response.Header.Get("Cache-Control") != "private, no-store" {
				t.Fatal("incorrect response or cache policy")
			}
			if tc.path == settings && (strings.Contains(string(body), nationalID) || strings.Contains(string(body), "ciphertext")) {
				t.Fatal("settings response contains private account data")
			}
		}) {
			break
		}
	}
}
