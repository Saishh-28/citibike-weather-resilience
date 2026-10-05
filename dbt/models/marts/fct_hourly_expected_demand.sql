-- fct_hourly_expected_demand
-- One row per UTC hour (17,424): what actually happened, what NORMALLY happens in that hour,
-- and the gap between them. The gap is what we later line up against the weather.
--
-- "Normal" (expected) demand = LEVEL x SHAPE        (idea from the friend's review, 5 Oct)
--
--   LEVEL = how busy this kind of day normally is around this date, WITHOUT rain:
--           the MEDIAN daily total of the same weekday from 4 weeks before to 4 weeks after
--           (e.g. for Tuesday 18 April: the Tuesdays from ~21 March to ~16 May),
--           using only comparable Dry or Light (drizzle) days, and never the day itself.
--           * Same weekday, so Tuesdays are compared with Tuesdays.
--           * Centred window, so it follows the seasons and Citi Bike's growth WITHOUT lagging
--             behind (decision B, Saisha 6 Oct; the first version used the previous 8 weeks and
--             sat ~6% too low on dry days).
--           * Rain-free days only, so "normal" means "normal without rain".
--           * Uses future weeks: right for EXPLAINING the past, not for FORECASTING. A forecast
--             (Phase 5) must use past days only.
--
--   SHAPE = how a normal DRY day of that kind spreads its trips over 24 hours:
--           the average share of the day's trips falling in each hour,
--           by season x weekday x hour, from comparable dry days only.
--           e.g. on a dry summer Tuesday about 9% of the day's trips start at 5pm.
--
--   expected trips at 5pm on a Tuesday = (median of the rain-free Tuesdays around it) x (5pm share)
--
-- Limitations (declared):
--   * Expected is only computed when at least 3 rain-free same weekdays are available nearby.
--   * Clock-change days (23 or 25 hours) use the normal 24-hour shape.
--   * Hours next to a closure are not flagged and may look unusually low.

with hourly as (

    select * from {{ ref('fct_hourly_demand') }}

),

daily as (

    select
        a.date_local,
        a.trips              as day_trips,
        a.day_type,
        a.is_comparable_day,
        d.season,
        d.day_of_week
    from {{ ref('agg_daily_weather_demand') }} a
    join {{ ref('dim_date') }} d
        on d.date_day = a.date_local

),

level as (

    -- For each date: median daily trips of the same weekday within +/- 4 weeks,
    -- rain-free comparable days only, excluding the day itself.
    select
        d.date_local,
        median(p.day_trips)      as level_trips,
        count(p.date_local)      as level_days_used
    from daily d
    left join daily p
        on  p.day_of_week = d.day_of_week
        and p.date_local <> d.date_local
        and p.date_local between dateadd('day', -28, d.date_local) and dateadd('day', 28, d.date_local)
        and p.is_comparable_day
        and p.day_type in ('Dry', 'Light')
    group by 1

),

shape as (

    -- Average share of a dry day's trips that start in each hour.
    select
        d.season,
        d.day_of_week,
        h.hour_of_day_local,
        avg(h.trip_count / nullif(d.day_trips, 0))  as hour_share,
        count(*)                                     as shape_days_used
    from hourly h
    join daily d
        on d.date_local = h.date_local
    where d.day_type = 'Dry'
      and d.is_comparable_day
    group by 1, 2, 3

),

combined as (

    select
        h.*,
        d.day_type,
        d.season,
        d.is_comparable_day,
        l.level_trips,
        l.level_days_used,
        s.hour_share,
        iff(l.level_days_used >= 3, l.level_trips * s.hour_share, null)  as expected_trips
    from hourly h
    join daily d
        on d.date_local = h.date_local
    left join level l
        on l.date_local = h.date_local
    left join shape s
        on  s.season            = d.season
        and s.day_of_week       = h.day_of_week_local
        and s.hour_of_day_local = h.hour_of_day_local

)

select
    *,
    trip_count - expected_trips                                   as residual_trips,
    trip_count / nullif(expected_trips, 0) - 1                    as deviation_pct,
    -- Hours used in the weather analysis: a normal day, system open, expectation available.
    (is_comparable_day and not is_system_closed and expected_trips is not null)
                                                                  as is_comparable_hour
from combined
