package domain

import (
	"context"
	"errors"
)

var ErrGeocodingBusy = errors.New("geocoding busy")

type Place struct {
	OriginalName  string  `json:"original_name,omitempty"`
	IsApproximate bool    `json:"is_approximate,omitempty"`
	Name          string  `json:"name"`
	DisplayName   string  `json:"display_name"`
	Latitude      float64 `json:"latitude"`
	Longitude     float64 `json:"longitude"`
	Type          string  `json:"type"`
}

type Geocoder interface {
	Search(context.Context, string) ([]Place, error)
	Reverse(context.Context, float64, float64) (Place, error)
}

type PlaceSuggester interface {
	Suggest(context.Context, string) ([]Place, error)
}
