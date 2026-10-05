-- agg_rain_response
-- The rain curve: how far below normal are hours with more and more rain?
-- One row per rain band x daypart (plus an 'All' daypart row per band).
--
-- Built from fct_hourly_expected_demand, comparable hours only
-- (normal days, system open, expectation available).
--
-- Rain bands (precipitation in THAT hour; snow hours apart) and dayparts (weekday commute
-- 07:00-09:59 and 16:00-18:59 / weekday other / weekend) come from fct_hourly_expected_demand.
--
-- % vs expected is WEIGHTED: sum(actual) / sum(expected) - 1.
-- Example: a 5pm hour expected 4,000 trips and a 3am hour expected 40. A simple average of
-- their percentages would let the 3am hour count as much as 5pm; weighting by trips does not.
--
-- trips_lost = expected - actual: the number a business reads ("rain cost ~X trips").

with hours as (

    -- rain_band, band_order and daypart are defined once, in fct_hourly_expected_demand.
    select *
    from {{ ref('fct_hourly_expected_demand') }}
    where is_comparable_hour

),

by_daypart as (

    select rain_band, band_order, daypart,
           count(*) as hours, sum(trip_count) as actual_trips, sum(expected_trips) as expected_trips,
           avg(precipitation_mm) as avg_precipitation_mm
    from hours
    group by 1, 2, 3

),

all_dayparts as (

    select rain_band, band_order, 'All' as daypart,
           count(*), sum(trip_count), sum(expected_trips), avg(precipitation_mm)
    from hours
    group by 1, 2

),

combined as (

    select * from by_daypart
    union all
    select * from all_dayparts

)

select
    rain_band,
    band_order,
    daypart,
    hours,
    actual_trips,
    round(expected_trips)                                       as expected_trips,
    actual_trips / nullif(expected_trips, 0) - 1                as pct_vs_expected,
    round(expected_trips - actual_trips)                        as trips_lost,
    round((expected_trips - actual_trips) / nullif(hours, 0))   as trips_lost_per_hour,
    avg_precipitation_mm
from combined
