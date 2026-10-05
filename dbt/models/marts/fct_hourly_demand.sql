-- fct_hourly_demand
-- THE table Power BI reads. One row per UTC hour in the analysis window: 17,424 rows.
-- Trips and weather side by side, plus calendar columns and the closure flag.
--
-- Decisions:
--   * Spine first, then LEFT joins. The spine guarantees every hour exists, even hours
--     with no trips. An inner join would silently drop them.
--   * trip_count: a missing hour means "we counted and nobody rode", so it is filled with 0.
--     Weather is NEVER filled with 0: there, blank means "not measured", not "dry".
--   * is_system_closed: a run of >= closure_min_hours consecutive zero-trip hours.
--     These are the three snowstorm shutdowns (Feb 2017, Mar 2017 Stella, Mar 2018).
--     They are excluded from weather-effect analysis (riders could not ride, they did
--     not choose not to) and reported separately.
--   * Hours are UTC (no missing or doubled hours); local time columns are for display
--     and for the "normal demand" baseline.

with spine as (

    -- 726 days x 24 = 17,424 hours, starting at New York midnight on overlap_start.
    -- row_number() is used because Snowflake's seq4() may skip numbers.
    select
        dateadd(
            'hour',
            row_number() over (order by seq4()) - 1,
            convert_timezone('America/New_York', 'UTC', '{{ var("overlap_start") }}'::timestamp_ntz)
        )                                                                as hour_utc
    from table(generator(rowcount => 17424))

),

joined as (

    select
        s.hour_utc,
        coalesce(t.trip_count, 0)                                        as trip_count,
        coalesce(t.member_trip_count, 0)                                 as member_trip_count,
        coalesce(t.casual_trip_count, 0)                                 as casual_trip_count,
        coalesce(t.unknown_rider_trip_count, 0)                          as unknown_rider_trip_count,

        w.temperature_c,
        w.humidity_pct,
        w.wind_speed_kmh,
        w.precipitation_mm,
        w.rain_mm,
        w.snowfall_cm,
        w.official_condition,
        w.official_condition_description,
        w.official_temperature_c,
        w.official_status

    from spine s
    left join {{ ref('int_trips_hourly') }}   t on t.trip_hour_utc    = s.hour_utc
    left join {{ ref('int_weather_hourly') }} w on w.weather_hour_utc = s.hour_utc

),

runs as (

    -- Gap-finding: every hour WITH trips starts a new group. The zero-trip hours that
    -- follow belong to that group, so counting zeros per group = length of the empty run.
    select
        joined.*,
        sum(iff(trip_count > 0, 1, 0)) over (
            order by hour_utc rows between unbounded preceding and current row
        )                                                                as run_group
    from joined

),

flagged as (

    select
        runs.*,
        count_if(trip_count = 0) over (partition by run_group)           as zero_run_hours
    from runs

)

select
    hour_utc,

    -- New York time, for charts and for the "normal demand" baseline
    convert_timezone('UTC', 'America/New_York', hour_utc)                as hour_local,
    to_date(convert_timezone('UTC', 'America/New_York', hour_utc))       as date_local,
    hour(convert_timezone('UTC', 'America/New_York', hour_utc))          as hour_of_day_local,
    dayofweekiso(convert_timezone('UTC', 'America/New_York', hour_utc))  as day_of_week_local,   -- 1 = Mon, 7 = Sun
    dayofweekiso(convert_timezone('UTC', 'America/New_York', hour_utc)) in (6, 7)
                                                                         as is_weekend,

    trip_count,
    member_trip_count,
    casual_trip_count,
    unknown_rider_trip_count,
    (trip_count = 0 and zero_run_hours >= {{ var('closure_min_hours') }}) as is_system_closed,

    temperature_c,
    humidity_pct,
    wind_speed_kmh,
    precipitation_mm,
    rain_mm,
    snowfall_cm,
    official_condition,
    official_condition_description,
    official_temperature_c,
    official_status

from flagged
