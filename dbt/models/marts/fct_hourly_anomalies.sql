-- fct_hourly_anomalies
-- One row per UTC hour (17,424). Which hours were unusual EVEN AFTER allowing for the weather?
--
--   weather-adjusted expected = normal demand x (1 + typical rain effect for that rain band
--                                                    and daypart, from agg_rain_response)
--   e.g. normal 5pm Tuesday = 4,000 trips; 1-2 mm of rain at a commute hour usually costs 54%
--        -> weather-adjusted expected = 4,000 x 0.46 = 1,840.
--        If only 600 rode, the hour is 67% below even the rainy expectation: an anomaly.
--
-- Rain effect per band x daypart is used when that cell has at least 30 hours behind it;
-- otherwise the band's all-daypart figure (small samples are not trusted).
--
-- An hour is an anomaly when it is at least 40% away from the weather-adjusted expectation
-- AND at least 300 trips were expected (so quiet night hours cannot dominate).
-- known_reason labels anomalies we can already explain: system closure or public holiday.
-- Anything else is 'Unexplained' - worth a human look, never a claim about the cause.

with hours as (

    select * from {{ ref('fct_hourly_expected_demand') }}

),

effect as (

    select rain_band, daypart, hours, pct_vs_expected
    from {{ ref('agg_rain_response') }}

),

adjusted as (

    select
        h.*,
        coalesce(
            iff(e.hours >= 30, e.pct_vs_expected, null),
            a.pct_vs_expected,
            0
        )                                                            as typical_weather_effect_pct
    from hours h
    left join effect e
        on e.rain_band = h.rain_band and e.daypart = h.daypart
    left join effect a
        on a.rain_band = h.rain_band and a.daypart = 'All'

),

scored as (

    select
        adjusted.*,
        dd.is_holiday,
        expected_trips * (1 + typical_weather_effect_pct)               as weather_adjusted_expected_trips
    from adjusted
    join {{ ref('dim_date') }} dd
        on dd.date_day = adjusted.date_local

)

select
    *,
    trip_count - weather_adjusted_expected_trips                        as unexplained_trips,
    trip_count / nullif(weather_adjusted_expected_trips, 0) - 1         as unexplained_pct,
    coalesce(
        abs(trip_count / nullif(weather_adjusted_expected_trips, 0) - 1) >= 0.40
        and weather_adjusted_expected_trips >= 300,
        false
    )                                                                   as is_anomaly,
    case
        when is_system_closed then 'Snowstorm closure'
        when is_holiday       then 'Public holiday'
        else 'Unexplained'
    end                                                                 as known_reason
from scored
