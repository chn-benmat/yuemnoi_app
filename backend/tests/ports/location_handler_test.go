package ports_test

import (
	"context"
	"encoding/json"
	"errors"
	"net/http/httptest"
	"net/url"
	"testing"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/chn-benmat/yuemnoi_app/backend/internal/ports"
)

type coverageGeocoder struct {
	fakeGeocoder
	places []domain.Place
}

func (g coverageGeocoder) Search(context.Context, string) ([]domain.Place, error) {
	return g.places, g.err
}

type coverageSuggester struct{ places []domain.Place }

func (g coverageSuggester) Suggest(context.Context, string) ([]domain.Place, error) {
	return g.places, nil
}

func TestExplicitPlaceSearchCombinesProvidersAndSurvivesOneProviderOutage(t *testing.T) {
	park := domain.Place{Name: "สวนเบญจกิติ", Latitude: 13.729, Longitude: 100.558}
	road := domain.Place{Name: "ถนนพุดตานใน", Latitude: 13.772, Longitude: 100.513, IsApproximate: true}
	for _, upstreamErr := range []error{nil, errors.New("upstream unavailable")} {
		app := ports.NewHTTPApp()
		ports.RegisterLocationRoutes(app, coverageGeocoder{fakeGeocoder: fakeGeocoder{err: upstreamErr}, places: []domain.Place{park}}, coverageSuggester{places: []domain.Place{park, road}})
		response, err := app.Test(httptest.NewRequest("GET", "/api/locations/search?q=park", nil))
		if err != nil {
			t.Fatal(err)
		}
		var places []domain.Place
		err = json.NewDecoder(response.Body).Decode(&places)
		response.Body.Close()
		app.Shutdown()
		if err != nil || response.StatusCode != 200 || len(places) != 2 || !places[1].IsApproximate {
			t.Fatalf("status=%d places=%v err=%v", response.StatusCode, places, err)
		}
	}
}

type fakeGeocoder struct{ err error }

func (g fakeGeocoder) Search(context.Context, string) ([]domain.Place, error) {
	return []domain.Place{}, g.err
}
func (g fakeGeocoder) Reverse(context.Context, float64, float64) (domain.Place, error) {
	return domain.Place{}, g.err
}

func (g fakeGeocoder) Suggest(ctx context.Context, query string) ([]domain.Place, error) {
	return g.Search(ctx, query)
}

func TestLocationRoutesValidateAndMapFailures(t *testing.T) {
	for _, tc := range []struct {
		path   string
		err    error
		status int
	}{
		{"/api/locations/search?q=" + url.QueryEscape("สวนเบญจกิติ"), nil, 200},
		{"/api/locations/search?q=x", nil, 400},
		{"/api/locations/suggest?q=park", nil, 200},
		{"/api/locations/suggest?q=x", nil, 400},
		{"/api/locations/suggest?q=park", domain.ErrGeocodingBusy, 429},
		{"/api/locations/search?q=park", domain.ErrGeocodingBusy, 429},
		{"/api/locations/search?q=park", errors.New("private upstream details"), 502},
		{"/api/locations/reverse?lat=NaN&lon=100", nil, 400},
		{"/api/locations/reverse?lat=91&lon=100", nil, 400},
	} {
		app := ports.NewHTTPApp()
		ports.RegisterLocationRoutes(app, fakeGeocoder{err: tc.err}, fakeGeocoder{err: tc.err})
		response, err := app.Test(httptest.NewRequest("GET", tc.path, nil))
		if err != nil {
			t.Fatal(err)
		}
		if response.StatusCode != tc.status {
			t.Errorf("%s: status=%d want=%d", tc.path, response.StatusCode, tc.status)
		}
		if tc.status == 429 && response.Header.Get("Retry-After") != "1" {
			t.Error("missing retry hint")
		}
		response.Body.Close()
		app.Shutdown()
	}
}
