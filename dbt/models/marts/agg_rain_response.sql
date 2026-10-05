-- agg_rain_response
-- The rain curve: how far below normal are hours with more and more rain?
-- One row per rain band x daypart (plus an 'All' daypart row per band).
--
-- Built from fct_hourly_expected_demand, comparable hours only
-- (normal days, system open, expectation available).
--
-- Rain bands use precipitation in THAT hour (Open-Meteo, mm). Hours with any snowfall are
-- kept apart in their own 'Snow' band, so snow does not blur the rain curve.
--
-- Dayparts (New York time):
--   Weekday commute = Mon-Fri 07:00-09:59 and 16:00-18:59  (the peaks)
--   Weekday other   = all other weekday hours
--   Weekend         = Sat and Sun
--
-- % vs expected is WEIGHTED: sum(actual) / sum(expected) - 1.
-- Example: a 5pm hour expected 4,000 trips and a 3am hour expected 40. A simple average of
-- their percentages would let the 3am hour count as much as 5pm; weighting by trips does not.
--
-- trips_lost = expected - actual: the number a business reads ("rain cost ~X trips").

with hours as (

    select
        *,
        case
            when snowfall_cm > 0          then 'Snow'
            when precipitation_mm = 0     then '0 mm (dry)'
            when precipitation_mm < 0.1   then '0-0.1 mm'
            when precipitation_mm < 0.5   then '0.1-0.5 mm'
            when precipitation_mm < 1     then '0.5-1 mm'
            when precipitation_mm < 2     then '1-2 mm'
            when precipitation_mm < 4     then '2-4 mm'
            else '4+ mm'
        end                                                     as rain_band,
        case
            when snowfall_cm > 0          then 8
            when precipitation_mm = 0     then 1
            when precipitation_mm < 0.1   then 2
            when precipitation_mm < 0.5   then 3
            when precipitation_mm < 1     then 4
            when precipitation_mm < 2     then 5
            when precipitation_mm < 4     then 6
            else 7
        end                                                     as band_order,
        case
            when is_weekend                                   then 'Weekend'
            when hour_of_day_local between 7 and 9
              or hour_of_day_local between 16 and 18          then 'Weekday commute'
            else 'Weekday other'
        end                                                     as daypart
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
