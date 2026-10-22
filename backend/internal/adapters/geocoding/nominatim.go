package geocoding

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
)

type cachedResult struct {
	data []byte
	at   time.Time
}

type Client struct {
	baseURL     string
	http        *http.Client
	mu          sync.Mutex
	nextRequest time.Time
	cache       map[string]cachedResult
}

func NewClient(baseURL string, client *http.Client) *Client {
	if client == nil {
		client = &http.Client{Timeout: 8 * time.Second}
	}
	return &Client{baseURL: strings.TrimRight(baseURL, "/"), http: client, cache: make(map[string]cachedResult)}
}

type osmPlace struct {
	Address struct {
		HouseNumber   string `json:"house_number"`
		Road          string `json:"road"`
		Neighbourhood string `json:"neighbourhood"`
		Quarter       string `json:"quarter"`
		Suburb        string `json:"suburb"`
		City          string `json:"city"`
	} `json:"address"`
	NameDetails map[string]string `json:"namedetails"`
	Name        string            `json:"name"`
	DisplayName string            `json:"display_name"`
	Lat         string            `json:"lat"`
	Lon         string            `json:"lon"`
	Type        string            `json:"type"`
}

func (p osmPlace) place() (domain.Place, error) {
	lat, latErr := strconv.ParseFloat(p.Lat, 64)
	lon, lonErr := strconv.ParseFloat(p.Lon, 64)
	if latErr != nil || lonErr != nil || math.IsNaN(lat) || math.IsNaN(lon) || math.IsInf(lat, 0) || math.IsInf(lon, 0) || math.Abs(lat) > 90 || math.Abs(lon) > 180 || strings.TrimSpace(p.DisplayName) == "" {
		return domain.Place{}, fmt.Errorf("invalid geocoding coordinates or address")
	}
	name := strings.TrimSpace(p.Name)
	if thai := strings.TrimSpace(p.NameDetails["name:th"]); hasThaiText(thai) {
		name = thai
	}
	if name == "" {
		name = strings.TrimSpace(strings.Split(p.DisplayName, ",")[0])
	}
	displayName := p.DisplayName
	originalName := ""
	if name != p.Name && p.Name != "" {
		originalName = p.Name
		displayName = strings.Replace(displayName, p.Name, name, 1)
	}
	return preferThaiPlace(domain.Place{Name: name, OriginalName: originalName, DisplayName: displayName, Latitude: lat, Longitude: lon, Type: p.Type}, p.Address.Road, p.Address.Neighbourhood, p.Address.Quarter, p.Address.Suburb, p.Address.City), nil
}

func (c *Client) Search(ctx context.Context, query string) ([]domain.Place, error) {
	raw, err := c.fetch(ctx, "search", url.Values{"q": {normalizePlaceQuery(query)}, "countrycodes": {"th"}, "limit": {"10"}})
	if err != nil {
		return nil, err
	}
	var source []osmPlace
	if err := json.Unmarshal(raw, &source); err != nil {
		return nil, err
	}
	places := make([]domain.Place, 0, len(source))
	for _, p := range source {
		number, _ := splitHouseQuery(normalizePlaceQuery(query))
		if number != "" && !strings.HasPrefix(p.Address.HouseNumber, number) {
			continue
		}
		place, err := p.place()
		if err != nil {
			return nil, err
		}
		places = append(places, place)
	}
	return places, nil
}

func (c *Client) Reverse(ctx context.Context, lat, lon float64) (domain.Place, error) {
	raw, err := c.fetch(ctx, "reverse", url.Values{"lat": {strconv.FormatFloat(lat, 'f', 6, 64)}, "lon": {strconv.FormatFloat(lon, 'f', 6, 64)}})
	if err != nil {
		return domain.Place{}, err
	}
	var source osmPlace
	if err := json.Unmarshal(raw, &source); err != nil {
		return domain.Place{}, err
	}
	return source.place()
}

func (c *Client) fetch(ctx context.Context, path string, params url.Values) ([]byte, error) {
	params.Set("format", "jsonv2")
	params.Set("addressdetails", "1")
	params.Set("namedetails", "1")
	params.Set("accept-language", "th,en")
	key := path + "?" + params.Encode()
	c.mu.Lock()
	now := time.Now()
	if entry, ok := c.cache[key]; ok && now.Sub(entry.at) < 24*time.Hour {
		c.mu.Unlock()
		return entry.data, nil
	}
	// รวมโควตาค้นหาและแปลงพิกัดทุกผู้ใช้ใน backend instance เดียว
	if now.Before(c.nextRequest) {
		c.mu.Unlock()
		return nil, domain.ErrGeocodingBusy
	}
	c.nextRequest = now.Add(time.Second)
	c.mu.Unlock()

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/"+key, nil)
	if err != nil {
		return nil, err
	}
	request.Header.Set("User-Agent", "YuemnoiApp/1.0 (contact: info@yuemnoi.com)")
	response, err := c.http.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("geocoding upstream status %d", response.StatusCode)
	}
	raw, err := io.ReadAll(io.LimitReader(response.Body, 1024*1024+1))
	if err != nil || len(raw) > 1024*1024 || !json.Valid(raw) {
		return nil, fmt.Errorf("invalid geocoding response")
	}
	// เก็บเฉพาะ response ที่มีโครงสร้างถูกต้อง เพื่อให้ลองใหม่ได้เมื่อ upstream ผิดพลาด
	if path == "search" {
		var places []osmPlace
		if err := json.Unmarshal(raw, &places); err != nil {
			return nil, err
		}
		for _, p := range places {
			if _, err := p.place(); err != nil {
				return nil, err
			}
		}
	} else {
		var place osmPlace
		if err := json.Unmarshal(raw, &place); err != nil {
			return nil, err
		}
		if _, err := place.place(); err != nil {
			return nil, err
		}
	}
	c.mu.Lock()
	if len(c.cache) >= 512 {
		clear(c.cache)
	}
	c.cache[key] = cachedResult{data: raw, at: time.Now()}
	c.mu.Unlock()
	return raw, nil
}
