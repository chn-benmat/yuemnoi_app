package geocoding_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/geocoding"
)

func TestHouseAddressFallsBackToMatchingStreetWithoutInventingHousePin(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query().Get("q")
		if q == "ถนนพุดตาน" {
			w.Write([]byte(`{"features":[{"properties":{"name":"ถนนพุดตานใน","city":"กรุงเทพมหานคร","countrycode":"TH"},"geometry":{"type":"Point","coordinates":[100.513,13.772]}}]}`))
		} else {
			w.Write([]byte(`{"features":[{"properties":{"name":"7-Eleven","housenumber":"254","countrycode":"TH"},"geometry":{"type":"Point","coordinates":[100,13]}}]}`))
		}
	}))
	defer server.Close()
	for _, query := range []string{"719/259 พุดตาน", "บ้านเลขที่ ๗๑๙ / ๒๕๙ ถ.พุดตาน", "719/259พุดตาน"} {
		places, err := geocoding.NewPhotonClient(server.URL, server.Client()).Suggest(context.Background(), query)
		if err != nil || len(places) != 1 || places[0].Name != "ถนนพุดตานใน" {
			t.Fatalf("matching street missing: %v err=%v", places, err)
		}
		raw, _ := json.Marshal(places[0])
		if !strings.Contains(string(raw), `"is_approximate":true`) {
			t.Fatalf("street must not be presented as the exact house: %s", raw)
		}
	}
}

func TestSuggestionsUsePhotonPrefixesAndCacheRealCoordinates(t *testing.T) {
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		if r.URL.Path != "/api/" || r.URL.Query().Get("q") != "สวนเบญ" || r.URL.Query().Get("countrycode") != "TH" || r.URL.Query().Get("lang") != "default" {
			t.Errorf("wrong request %s", r.URL)
		}
		w.Write([]byte(`{"features":[{"properties":{"name":"สวนเบญจกิติ","street":"ถนนรัชดาภิเษก","city":"กรุงเทพมหานคร","country":"ประเทศไทย","countrycode":"TH","osm_value":"park"},"geometry":{"type":"Point","coordinates":[100.5585211,13.7292243]}},{"properties":{"name":"outside Thailand","countrycode":"LA"},"geometry":{"type":"Point","coordinates":[102,18]}}]}`))
	}))
	defer server.Close()
	client := geocoding.NewPhotonClient(server.URL, server.Client())
	for range 2 {
		places, err := client.Suggest(context.Background(), "สวนเบญ")
		if err != nil || len(places) != 1 {
			t.Fatalf("places=%v err=%v", places, err)
		}
		p := places[0]
		if p.Name != "สวนเบญจกิติ" || p.Latitude != 13.7292243 || p.Longitude != 100.5585211 || p.DisplayName != "สวนเบญจกิติ, ถนนรัชดาภิเษก, กรุงเทพมหานคร, ประเทศไทย" {
			t.Fatalf("wrong suggestion %+v", p)
		}
	}
	if calls.Load() != 1 {
		t.Fatal("uncached requests")
	}
}

func TestSuggestionsDoNotInventHouseNumbers(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"features":[{"properties":{"name":"7-11","housenumber":"254","countrycode":"TH"},"geometry":{"type":"Point","coordinates":[100,13]}}]}`))
	}))
	defer server.Close()
	for _, tc := range []struct {
		query string
		count int
	}{{"719/259", 0}, {"7-Eleven", 1}} {
		places, err := geocoding.NewPhotonClient(server.URL, server.Client()).Suggest(context.Background(), tc.query)
		if err != nil || len(places) != tc.count {
			t.Fatalf("%s: places=%v err=%v", tc.query, places, err)
		}
	}

}

func TestSuggestionsUseExactHouseNumberAndKeepPlaceName(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"features":[
			{"properties":{"name":"Another address","housenumber":"991/2","countrycode":"TH"},"geometry":{"type":"Point","coordinates":[100.53,13.74]}},
			{"properties":{"name":"Siam Paragon","housenumber":"๙๙๑","street":"ถนนพระรามที่ 1","countrycode":"TH"},"geometry":{"type":"Point","coordinates":[100.534954,13.7467785]}}
		]}`))
	}))
	defer server.Close()
	places, err := geocoding.NewPhotonClient(server.URL, server.Client()).Suggest(context.Background(), "991 ถนนพระรามที่ 1")
	if err != nil || len(places) != 1 || places[0].Name != "Siam Paragon" || places[0].IsApproximate {
		t.Fatalf("expected the named place at the exact address: %v err=%v", places, err)
	}
}

func TestSuggestionsKeepNumericStoreNamesSearchable(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"features":[{"properties":{"name":"24 Fitness","street":"ถนนสุขุมวิท","countrycode":"TH"},"geometry":{"type":"Point","coordinates":[100.56,13.73]}}]}`))
	}))
	defer server.Close()
	places, err := geocoding.NewPhotonClient(server.URL, server.Client()).Suggest(context.Background(), "24 Fitness")
	if err != nil || len(places) != 1 || places[0].Name != "24 Fitness" || places[0].IsApproximate {
		t.Fatalf("expected the actual store name: %v err=%v", places, err)
	}
}

func TestExplicitHouseNumberIsFilteredEvenWithoutThaiStreetName(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"features":[
			{"properties":{"name":"Wrong house","housenumber":"123/3","countrycode":"TH"},"geometry":{"type":"Point","coordinates":[100.53,13.74]}},
			{"properties":{"name":"Exact house","housenumber":"123","street":"Sukhumvit","countrycode":"TH"},"geometry":{"type":"Point","coordinates":[100.54,13.74]}}
		]}`))
	}))
	defer server.Close()
	places, err := geocoding.NewPhotonClient(server.URL, server.Client()).Suggest(context.Background(), "บ้านเลขที่ 123 Sukhumvit")
	if err != nil || len(places) != 1 || places[0].Name != "Exact house" || places[0].IsApproximate {
		t.Fatalf("explicit house number was not enforced: %v err=%v", places, err)
	}
}

func TestSuggestionsRejectBadResponseAndUpstreamFailure(t *testing.T) {
	for _, tc := range []struct {
		status int
		body   string
	}{
		{503, `{"error":"unavailable"}`}, {200, `{"error":"missing features"}`},
		{200, `{"features":[{"properties":{"name":"bad","countrycode":"TH"},"geometry":{"type":"Point","coordinates":[181,13]}}]}`},
	} {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(tc.status); w.Write([]byte(tc.body)) }))
		_, err := geocoding.NewPhotonClient(server.URL, server.Client()).Suggest(context.Background(), "สวน")
		server.Close()
		if err == nil {
			t.Fatal("bad response accepted")
		}
	}
}
