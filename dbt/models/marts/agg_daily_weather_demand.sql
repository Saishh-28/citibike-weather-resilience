-- agg_daily_weather_demand
-- One row per New York calendar date (726 rows). Answers the brief's literal question:
-- "How does a rainy or snowy day affect user behaviour compared to a clear, sunny day?"
--
-- Day types (thresholds in dbt_project.yml):
--   Snowy  = snowfall >= snowy_day_min_cm  (snow beats rain)
--   Rainy  = rain     >= rainy_day_min_mm
--   Dry    = no measurable precipitation at all (0.0 mm) - stands in for "clear, sunny"
--   Light  = some precipitation but below both thresholds - shown, not compared
--
-- Two ways to compare, both kept on purpose:
--   1. The LITERAL view: average trips on rainy vs snowy vs dry days.
--      Simple, but unfair: snowy days only happen in winter, when demand is low anyway.
--   2. The FAIRER view: each day compared with DRY days of the same month and the same
--      day type (weekday vs weekend). A snowy Tuesday in February is compared with dry
--      weekdays in that February, not with July.
--
-- Not comparable (flagged, kept): days with a snowstorm closure (riders could not ride)
-- and public holidays (different demand for reasons other than weather).

with hourly as (

    select * from {{ ref('fct_hourly_demand') }}

),

daily as (

    select
        date_local,
        sum(trip_count)                       as trips,
        sum(member_trip_count)                as member_trips,
        sum(casual_trip_count)                as casual_trips,
        sum(precipitation_mm)                 as precipitation_mm,
        sum(rain_mm)                          as rain_mm,
        sum(snowfall_cm)                      as snowfall_cm,
        avg(temperature_c)                    as avg_temperature_c,
        min(temperature_c)                    as min_temperature_c,
        max(temperature_c)                    as max_temperature_c,
        avg(wind_speed_kmh)                   as avg_wind_speed_kmh,
        count(*)                              as hours_in_day,       -- 23 or 25 on clock-change days
        count_if(is_system_closed)            as closed_hours
    from hourly
    group by 1

),

classified as (

    select
        d.*,
        dd.year,
        dd.month,
        dd.month_name,
        dd.season,
        dd.day_name,
        dd.is_weekend,
        dd.is_holiday,
        dd.holiday_name,
        case
            when d.snowfall_cm >= {{ var('snowy_day_min_cm') }} then 'Snowy'
            when d.rain_mm     >= {{ var('rainy_day_min_mm') }} then 'Rainy'
            when d.precipitation_mm = 0                          then 'Dry'
            else 'Light'
        end                                                       as day_type,
        (d.closed_hours = 0 and not dd.is_holiday)                as is_comparable_day,
        d.casual_trips / nullif(d.trips, 0)                       as casual_share
    from daily d
    join {{ ref('dim_date') }} dd
        on dd.date_day = d.date_local

),

dry_baseline as (

    -- Average trips on comparable DRY days, per year-month and weekday/weekend.
    select
        year,
        month,
        is_weekend,
        avg(trips)          as dry_day_avg_trips,
        avg(casual_share)   as dry_day_avg_casual_share,
        avg(member_trips)   as dry_day_avg_member_trips,
        avg(casual_trips)   as dry_day_avg_casual_trips,
        count(*)            as dry_days_in_baseline
    from classified
    where day_type = 'Dry'
      and is_comparable_day
    group by 1, 2, 3

)

select
    c.*,
    b.dry_day_avg_trips,
    b.dry_day_avg_casual_share,
    b.dry_days_in_baseline,
    c.trips / nullif(b.dry_day_avg_trips, 0) - 1               as pct_vs_dry_days_same_month,
    -- Each rider group against ITS OWN dry-day level in the same month:
    -- "did members drop by less than casual riders?"
    c.member_trips / nullif(b.dry_day_avg_member_trips, 0) - 1 as member_pct_vs_dry_days_same_month,
    c.casual_trips / nullif(b.dry_day_avg_casual_trips, 0) - 1 as casual_pct_vs_dry_days_same_month
from classified c
left join dry_baseline b
    on  b.year       = c.year
    and b.month      = c.month
    and b.is_weekend = c.is_weekend
