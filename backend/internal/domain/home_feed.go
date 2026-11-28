package domain

import (
	"context"
	"encoding/json"
	"errors"
)

var ErrInvalidHomeFeedRequest = errors.New("invalid_home_feed_request")

type HomeFeedQuery struct {
	ViewerID         *string
	Latitude         *float64
	Longitude        *float64
	RecentCategories []string
	Cursor           *string
	Limit            int
}

type HomeFeedPage struct {
	Items      []json.RawMessage `json:"items"`
	NextCursor *string           `json:"next_cursor"`
}

type HomeFeedRepository interface {
	GetHomeFeed(context.Context, HomeFeedQuery) (HomeFeedPage, error)
}
