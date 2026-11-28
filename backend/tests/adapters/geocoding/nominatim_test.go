package geocoding_test

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/adapters/geocoding"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

func TestReverseUsesThaiAddressWhenUpstreamThaiNameIsActuallyEnglish(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"name":"Honorary Consulate of Albania","namedetails":{"name:th":"Honorary Consulate of Albania"},"display_name":"Honorary Consulate of Albania, 4, ซอยพร้อมมิตร, กรุงเทพมหานคร","address":{"road":"ซอยพร้อมมิตร"},"lat":"13.7336306","lon":"100.5720061"}`))
	}))
	defer server.Close()
	place, err := geocoding.NewClient(server.URL, server.Client()).Reverse(context.Background(), 13.7336306, 100.5720061)
	if err != nil || !strings.Contains(place.Name, "ซอยพร้อมมิตร") || strings.Contains(place.Name, "Honorary") {
		t.Fatalf("expected Thai meeting-point title: %+v err=%v", place, err)
	}
	if place.OriginalName != "Honorary Consulate of Albania" {
		t.Fatal("lost original place identity")
	}
}

func TestSearchPrefersActualThaiNameDetails(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("namedetails") != "1" {
			t.Error("missing Thai name details request")
		}
		w.Write([]byte(`[{"name":"Benchakitti Park","namedetails":{"name:th":"สวนเบญจกิติ"},"display_name":"Benchakitti Park, กรุงเทพมหานคร","lat":"13.7292243","lon":"100.5585211"}]`))
	}))
	defer server.Close()
	places, err := geocoding.NewClient(server.URL, server.Client()).Search(context.Background(), "Benchakitti Park")
	if err != nil || len(places) != 1 || places[0].Name != "สวนเบญจกิติ" || places[0].OriginalName != "Benchakitti Park" {
		t.Fatalf("places=%v err=%v", places, err)
	}
}

func TestSearchRejectsOtherHouseNumbersAndKeepsTheMatchedName(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`[
			{"name":"Other address","display_name":"991/2, ถนนพระรามที่ 1","lat":"13.74","lon":"100.53","address":{"house_number":"991/2"}},
			{"name":"Siam Paragon","display_name":"Siam Paragon, 991, ถนนพระรามที่ 1","lat":"13.7467785","lon":"100.534954","address":{"house_number":"991","road":"ถนนพระรามที่ 1"}}
		]`))
	}))
	defer server.Close()
	places, err := geocoding.NewClient(server.URL, server.Client()).Search(context.Background(), "991 ถนนพระรามที่ 1")
	if err != nil || len(places) != 1 || places[0].Name != "Siam Paragon" || places[0].Longitude != 100.534954 {
		t.Fatalf("expected the named place at the exact address: %v err=%v", places, err)
	}
}

func TestSearchRealPlacesCachesAndSharesReverseQuota(t *testing.T) {
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		q := r.URL.Query()
		if r.URL.Path != "/search" || q.Get("q") != "สวนเบญจกิติ" || q.Get("countrycodes") != "th" || q.Get("accept-language") != "th,en" || r.UserAgent() == "" {
			t.Errorf("unexpected request: %s", r.URL)
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`[{"name":"สวนเบญจกิติ","display_name":"สวนเบญจกิติ, กรุงเทพมหานคร","lat":"13.7292243","lon":"100.5585211","type":"park"}]`))
	}))
	defer server.Close()
	client := geocoding.NewClient(server.URL, server.Client())
	for range 2 {
		places, err := client.Search(context.Background(), " สวนเบญจกิติ ")
		if err != nil || len(places) != 1 {
			t.Fatalf("places=%v err=%v", places, err)
		}
		if places[0].Latitude != 13.7292243 || places[0].Longitude != 100.5585211 || places[0].Name != "สวนเบญจกิติ" {
			t.Fatalf("wrong place: %+v", places[0])
		}
	}
	if calls.Load() != 1 {
		t.Fatalf("cache missed: %d", calls.Load())
	}
	if _, err := client.Reverse(context.Background(), 13, 100); !errors.Is(err, domain.ErrGeocodingBusy) {
		t.Fatalf("quota not shared: %v", err)
	}
}

func TestSearchRejectsUpstreamErrorsAndMalformedPlaces(t *testing.T) {
	for _, body := range []string{`{"error":"unavailable"}`, `[{"name":"bad","display_name":"bad","lat":"NaN","lon":"100"}]`, `not json`} {
		t.Run(body, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write([]byte(body)) }))
			defer server.Close()
			_, err := geocoding.NewClient(server.URL, server.Client()).Search(context.Background(), "เชียงใหม่")
			if err == nil {
				t.Fatal("malformed upstream accepted")
			}
		})
	}
}
