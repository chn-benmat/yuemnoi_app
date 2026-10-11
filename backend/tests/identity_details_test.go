package tests

import (
	"bytes"
	"context"
	"encoding/json"
	"image"
	"image/png"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
	"github.com/stretchr/testify/require"
)

type identityDetailsStore struct{ opsStore }

func (*identityDetailsStore) UploadEvidence(context.Context, string, []byte, string) error {
	return nil
}

func TestIdentitySubmitPersonalDetails(t *testing.T) {
	for _, tc := range []struct {
		name   string
		change map[string]string
		omit   string
		legacy bool
		status int
	}{
		{name: "complete and trimmed", status: http.StatusCreated},
		{name: "minor without guardian or age flag in session", change: map[string]string{"birth_date": "2015-01-01"}, status: http.StatusCreated},
		{name: "age thirteen", change: map[string]string{"birth_date": time.Now().AddDate(-13, 0, 0).Format("2006-01-02")}, status: http.StatusCreated},
		{name: "newborn", change: map[string]string{"birth_date": time.Now().Format("2006-01-02")}, status: http.StatusCreated},
		{name: "miss", change: map[string]string{"name_prefix": "นางสาว"}, status: http.StatusCreated},
		{name: "mrs", change: map[string]string{"name_prefix": "นาง"}, status: http.StatusCreated},
		{name: "legacy combined name", legacy: true, status: http.StatusCreated},
		{name: "manual review without OCR service", status: http.StatusCreated},
		{name: "client cannot claim lifetime", change: map[string]string{"lifetime": "true"}, status: http.StatusCreated},
		{name: "client cannot set expiry", change: map[string]string{"lifetime": "false", "expires_on": "2000-01-01"}, status: http.StatusCreated},
		{name: "invalid prefix", change: map[string]string{"name_prefix": "ดร."}, status: http.StatusBadRequest},
		{name: "empty prefix", change: map[string]string{"name_prefix": " "}, status: http.StatusBadRequest},
		{name: "empty first name", change: map[string]string{"first_name": " "}, status: http.StatusBadRequest},
		{name: "missing last name", omit: "last_name", status: http.StatusBadRequest},
		{name: "missing address", omit: "address_detail", status: http.StatusBadRequest},
		{name: "short postcode", change: map[string]string{"postal_code": "1020"}, status: http.StatusBadRequest},
		{name: "non numeric postcode", change: map[string]string{"postal_code": "1020x"}, status: http.StatusBadRequest},
		{name: "zero postcode", change: map[string]string{"postal_code": "00000"}, status: http.StatusBadRequest},
		{name: "non ASCII postcode", change: map[string]string{"postal_code": "๑๐๒๐๐"}, status: http.StatusBadRequest},
		{name: "missing province", omit: "province", status: http.StatusBadRequest},
		{name: "blank district", change: map[string]string{"district": " \n "}, status: http.StatusBadRequest},
		{name: "missing subdistrict", omit: "subdistrict", status: http.StatusBadRequest},
		{name: "long address", change: map[string]string{"address_detail": strings.Repeat("ก", 501)}, status: http.StatusBadRequest},
	} {
		t.Run(tc.name, func(t *testing.T) {
			fields := map[string]string{
				"name_prefix": " นาย ", "first_name": " ทดสอบ ", "last_name": " ระบบ ",
				"address_detail": " 99/1 ถนนทดสอบ ", "postal_code": " 10200 ",
				"province": " กรุงเทพมหานคร ", "district": " พระนคร ", "subdistrict": " บวรนิเวศ ",
			}
			if tc.legacy {
				clear(fields)
			}
			fields["citizen_id"] = "0000000000001"
			fields["birth_date"] = "2000-01-01"
			fields["legal_name"] = "Synthetic Legacy Name"
			for k, v := range tc.change {
				fields[k] = v
			}
			delete(fields, tc.omit)
			key := bytes.Repeat([]byte{1}, 32)
			submitted := false
			store := &identityDetailsStore{}
			store.call = func(name string, args map[string]any) (json.RawMessage, error) {
				switch name {
				case "identity_status":
					return json.Marshal(map[string]any{"request": map[string]any{
						"id": performanceSession, "status": "capture", "capture_until": time.Now().Add(time.Minute),
					}})
				case "identity_submit":
					submitted = true
					data := args["p_data"].(map[string]any)
					require.Equal(t, false, data["lifetime"])
					require.Nil(t, data["expires_on"])
					require.Equal(t, map[string]any{"review_mode": "manual"}, data["analysis"])
					plain, err := domain.DecryptIdentity(data["raw_encrypted"].(string), key)
					require.NoError(t, err)
					var sensitive map[string]string
					require.NoError(t, json.Unmarshal(plain, &sensitive))
					require.Equal(t, fields["citizen_id"], sensitive["citizen_id"])
					require.Equal(t, fields["birth_date"], sensitive["birth_date"])
					require.NotContains(t, sensitive, "ocr_text")
					if tc.legacy {
						require.NotContains(t, sensitive, "name_prefix")
						require.Equal(t, fields["legal_name"], data["legal_name"])
					} else {
						for _, field := range []string{"name_prefix", "first_name", "last_name", "address_detail", "postal_code", "province", "district", "subdistrict"} {
							require.Equal(t, strings.TrimSpace(fields[field]), sensitive[field], field)
							require.NotContains(t, data, field)
						}
						require.Equal(t, sensitive["name_prefix"]+" ทดสอบ ระบบ", data["legal_name"])
					}
				}
				return json.RawMessage(`{"status":"pending"}`), nil
			}
			handler := ports.NewOperationsHandler(domain.OperationsOptions{
				Store: store, EncryptionKey: key, HMACKey: bytes.Repeat([]byte{2}, 32),
			}, opsVerifier{})
			app := ports.NewHTTPApp()
			app.Post("/identity/:id", handler.Submit)
			var body, photo bytes.Buffer
			require.NoError(t, png.Encode(&photo, image.NewRGBA(image.Rect(0, 0, 1, 1))))
			writer := multipart.NewWriter(&body)
			for k, v := range fields {
				require.NoError(t, writer.WriteField(k, v))
			}
			for _, kind := range []string{"card", "selfie"} {
				part, err := writer.CreateFormFile(kind, kind+".png")
				require.NoError(t, err)
				_, err = part.Write(photo.Bytes())
				require.NoError(t, err)
			}
			require.NoError(t, writer.Close())
			request := httptest.NewRequest(http.MethodPost, "/identity/"+performanceSession, &body)
			request.Header.Set("Authorization", "Bearer test-token")
			request.Header.Set("Content-Type", writer.FormDataContentType())
			response, err := app.Test(request)
			require.NoError(t, err)
			defer response.Body.Close()
			responseBody, err := io.ReadAll(response.Body)
			require.NoError(t, err)
			require.Equal(t, tc.status, response.StatusCode, string(responseBody))
			require.Equal(t, tc.status == http.StatusCreated, submitted)
			if submitted {
				require.JSONEq(t, `{"status":"pending"}`, string(responseBody))
			}
			require.NotContains(t, string(responseBody), "99/1")
			if tc.status != http.StatusCreated {
				require.Equal(t, []string{"identity_status"}, store.events)
			}
		})
	}
}
