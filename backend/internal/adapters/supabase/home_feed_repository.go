package supabase

import (
	"context"
	"errors"
	"fmt"

	"github.com/chn-benmat/yuemnoi_app/backend/internal/domain"
	"github.com/nedpals/supabase-go"
	postgrest "github.com/nedpals/supabase-go/postgrest/pkg"
)

type supabaseHomeFeedRepository struct {
	client *supabase.Client
}

func NewSupabaseHomeFeedRepository(serviceRoleClient *supabase.Client) domain.HomeFeedRepository {
	return &supabaseHomeFeedRepository{client: serviceRoleClient}
}

func (r *supabaseHomeFeedRepository) GetHomeFeed(ctx context.Context, query domain.HomeFeedQuery) (domain.HomeFeedPage, error) {
	var page domain.HomeFeedPage
	err := r.client.DB.Rpc("get_home_feed_v2", map[string]any{
		"p_viewer_id":         query.ViewerID,
		"p_latitude":          query.Latitude,
		"p_longitude":         query.Longitude,
		"p_recent_categories": query.RecentCategories,
		"p_cursor":            query.Cursor,
		"p_limit":             query.Limit,
	}).ExecuteWithContext(ctx, &page)
	if err != nil {
		var requestErr *postgrest.RequestError
		if errors.As(err, &requestErr) && requestErr.Code == "22023" {
			return domain.HomeFeedPage{}, domain.ErrInvalidHomeFeedRequest
		}
		return domain.HomeFeedPage{}, fmt.Errorf("get_home_feed_v2: %w", err)
	}
	if page.Items == nil {
		return domain.HomeFeedPage{}, errors.New("get_home_feed_v2: missing items array")
	}
	return page, nil
}
