create index if not exists review_tb_item_id_idx
  on public.review_tb (item_id);

create index if not exists item_tb_status_created_at_idx
  on public.item_tb (status, created_at desc);

create or replace view public.home_feed_ranked_v
with (security_invoker = true)
as
with booking_stats as (
  select
    item_id,
    count(*)::bigint as paid_booking_count
  from public.booking_tb
  where payment_status = 'paid'
  group by item_id
),
valid_reviews as (
  select
    item_id,
    case
      when btrim(rating) ~ '^[0-9]+([.][0-9]+)?$'
        and btrim(rating)::numeric between 1 and 5
      then btrim(rating)::numeric
    end as rating_value
  from public.review_tb
),
review_stats as (
  select
    item_id,
    count(rating_value)::bigint as review_count,
    avg(rating_value) as average_rating
  from valid_reviews
  where rating_value is not null
  group by item_id
),
base_scores as (
  select
    i.id,
    i.user_id,
    i.item_name,
    i.item_image_url,
    i.description,
    i.category,
    i.price,
    i.status,
    i.type,
    i.created_at,
    i.updated_at,
    coalesce(bs.paid_booking_count, 0)::bigint as paid_booking_count,
    coalesce(rs.review_count, 0)::bigint as review_count,
    round(coalesce(rs.average_rating, 0), 2)::double precision as rating,
    (
      0.50 * least(
        1.0,
        ln(1.0 + coalesce(bs.paid_booking_count, 0)::numeric) / ln(11.0)
      )
      + 0.30 * (
        (
          coalesce(rs.average_rating, 4.0) * coalesce(rs.review_count, 0)
          + 4.0 * 5.0
        ) / (coalesce(rs.review_count, 0) + 5.0)
      ) / 5.0
      + 0.20 / (
        1.0 + greatest(
          0.0,
          extract(epoch from (now() - i.created_at)) / 86400.0
        ) / 30.0
      )
    )::double precision as base_score
  from public.item_tb i
  left join booking_stats bs on bs.item_id = i.id
  left join review_stats rs on rs.item_id = i.id
  where i.status = 'available'
),
diversity_ranks as (
  select
    b.*,
    row_number() over (
      partition by coalesce(b.category, '')
      order by
        b.base_score desc,
        md5(current_date::text || ':' || b.id::text)
    ) as category_rank,
    row_number() over (
      partition by b.user_id
      order by
        b.base_score desc,
        md5(current_date::text || ':' || b.id::text)
    ) as owner_rank
  from base_scores b
),
final_scores as (
  select
    d.*,
    (
      d.base_score
      - least(greatest(d.category_rank - 1, 0), 2) * 0.06
      - least(greatest(d.owner_rank - 1, 0), 2) * 0.04
    )::double precision as rank_score
  from diversity_ranks d
)
select
  f.id,
  f.user_id,
  f.item_name,
  f.item_image_url,
  f.description,
  f.category,
  f.price,
  f.status,
  f.type,
  f.created_at,
  f.updated_at,
  f.rating,
  f.review_count,
  f.paid_booking_count,
  f.rank_score,
  row_number() over (
    order by
      f.rank_score desc,
      md5(current_date::text || ':' || f.id::text)
  )::bigint as rank_position
from final_scores f;

revoke all on public.home_feed_ranked_v from public;
revoke all on public.home_feed_ranked_v from anon;
revoke all on public.home_feed_ranked_v from authenticated;
grant select on public.home_feed_ranked_v to service_role;
