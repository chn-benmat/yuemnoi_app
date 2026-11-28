package geocoding

import (
	"context"
	"encoding/json"
	"fmt"
	"golang.org/x/time/rate"
	"io"
	"math"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

type suggestionCache struct {
	places []domain.Place
	at     time.Time
}
type PhotonClient struct {
	baseURL string
	http    *http.Client
	mu      sync.Mutex
	limiter *rate.Limiter
	cache   map[[2]string]suggestionCache
}

func NewPhotonClient(baseURL string, client *http.Client) *PhotonClient {
	if client == nil {
		client = &http.Client{Timeout: 8 * time.Second}
	}
	return &PhotonClient{baseURL: strings.TrimRight(baseURL, "/"), http: client, cache: make(map[[2]string]suggestionCache), limiter: rate.NewLimiter(rate.Every(350*time.Millisecond), 1)}
}

func (c *PhotonClient) Suggest(ctx context.Context, query string) ([]domain.Place, error) {
	query, number, area := normalizePlaceQuery(query)
	cacheKey := [2]string{query, number}
	ctx, cancel := context.WithTimeout(ctx, 12*time.Second)
	defer cancel()
	c.mu.Lock()
	if entry, ok := c.cache[cacheKey]; ok && time.Since(entry.at) < 30*time.Minute {
		c.mu.Unlock()
		return append([]domain.Place{}, entry.places...), nil
	}
	c.mu.Unlock()
	variants := []string{query}
	if number != "" && area != "" {
		variants = append(variants, area)
	}
	if area != "" && !strings.Contains(area, " ") && !strings.HasPrefix(area, "ถนน") && !strings.HasPrefix(area, "ซอย") && len([]rune(area)) >= 3 {
		variants = append(variants, "ถนน"+area)
	}
	places := []domain.Place{}
	for index, variant := range variants {
		exactNumber := ""
		if index == 0 {
			exactNumber = number
		}
		found, err := c.fetchSuggestions(ctx, variant, exactNumber)
		if err != nil {
			return nil, err
		}
		if index > 0 {
			for _, p := range found {
				if matchesPlaceArea(p, area) {
					p.IsApproximate = number != ""
					places = append(places, p)
				}
			}
		} else {
			places = found
		}
		if len(places) > 0 {
			break
		}
	}
	c.mu.Lock()
	if len(c.cache) >= 512 {
		clear(c.cache)
	}
	c.cache[cacheKey] = suggestionCache{places: places, at: time.Now()}
	c.mu.Unlock()
	return places, nil
}

func (c *PhotonClient) fetchSuggestions(ctx context.Context, query, number string) ([]domain.Place, error) {
	// ทุก query สำรองรอโควตาเดียวกัน ไม่เพิ่ม burst ไปยังบริการสาธารณะ
	if err := c.limiter.Wait(ctx); err != nil {
		return nil, err
	}
	params := url.Values{"q": {query}, "limit": {"8"}, "countrycode": {"TH"}, "bbox": {"97.3,5.6,105.7,20.5"}}
	params.Set("lang", "default")

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/api/?"+params.Encode(), nil)
	if err != nil {
		return nil, err
	}
	request.Header.Set("User-Agent", "YuemnoiApp/1.0 (contact: info@yuemnoi.com)")
	response, err := c.http.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	if response.StatusCode != 200 {
		return nil, fmt.Errorf("suggestions upstream status %d", response.StatusCode)
	}
	raw, err := io.ReadAll(io.LimitReader(response.Body, 1024*1024+1))
	if err != nil || len(raw) > 1024*1024 {
		return nil, fmt.Errorf("invalid suggestions response")
	}
	var data struct {
		Features []struct {
			Properties map[string]any `json:"properties"`
			Geometry   struct {
				Type        string    `json:"type"`
				Coordinates []float64 `json:"coordinates"`
			} `json:"geometry"`
		} `json:"features"`
	}
	if err := json.Unmarshal(raw, &data); err != nil {
		return nil, err
	}
	if data.Features == nil {
		return nil, fmt.Errorf("missing suggestion features")
	}
	places := make([]domain.Place, 0, len(data.Features))
	seen := make(map[string]bool)
	for _, feature := range data.Features {
		text := func(key string) string { value, _ := feature.Properties[key].(string); return strings.TrimSpace(value) }
		if !strings.EqualFold(text("countrycode"), "TH") {
			continue
		}
		coords := feature.Geometry.Coordinates
		if feature.Geometry.Type != "Point" || len(coords) != 2 || math.IsNaN(coords[0]) || math.IsNaN(coords[1]) || math.IsInf(coords[0], 0) || math.IsInf(coords[1], 0) || math.Abs(coords[0]) > 180 || math.Abs(coords[1]) > 90 {
			return nil, fmt.Errorf("invalid suggestion coordinates")
		}
		houseNumber := text("housenumber")
		street := strings.TrimSpace(houseNumber + " " + text("street"))
		name := text("name")
		if name == "" {
			name = street
		}
		if name == "" {
			name = text("city")
		}
		if name == "" {
			continue
		}
		// เลขที่บ้านต้องตรงคำค้น ไม่ใช้การเดาตัวเลขของ fuzzy search เป็นที่อยู่จริง
		if number != "" && !hasHouseNumber(houseNumber, number) {
			continue
		}

		parts := []string{}
		used := map[string]bool{}
		for _, part := range []string{name, street, text("locality"), text("district"), text("city"), text("county"), text("state"), text("postcode"), text("country")} {
			if part != "" && !used[part] {
				parts = append(parts, part)
				used[part] = true
			}
		}
		key := fmt.Sprintf("%s:%f:%f", name, coords[0], coords[1])
		if seen[key] {
			continue
		}
		seen[key] = true
		places = append(places, domain.Place{Name: name, DisplayName: strings.Join(parts, ", "), Latitude: coords[1], Longitude: coords[0], Type: text("osm_value")})
	}
	return places, nil
}
