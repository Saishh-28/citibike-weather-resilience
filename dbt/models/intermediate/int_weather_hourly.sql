-- int_weather_hourly
-- One row per UTC hour in the analysis window (17,424 rows), holding everything we know
-- about the weather in that hour. Trips will join to this on the hour.
--
-- Step 1  Open-Meteo is the backbone: complete, exactly hourly, rain in mm.
-- Step 2  Official feed tidied to one reading per UTC hour, Manhattan only (written by Saisha).
-- Step 3  Left join step 2 onto step 1, fill official gaps up to weather_fill_cap_hours,
--         flag every filled hour, and leave longer gaps missing (never "dry").
--
-- Decision: Open-Meteo rain/snow alignment.
--   Open-Meteo stores precipitation, rain and snowfall as the total for the hour that ENDS at
--   the timestamp (the 10:00 row = rain that fell 09:00-10:00). Trips are bucketed by the hour
--   that STARTS at the timestamp (09:00 bucket = trips started 09:00-09:59). So the rain for
--   trip hour H is read from the Open-Meteo row at H + 1 hour (LEAD below).
--   Temperature, humidity and wind are instant readings, so they stay on the same row.

with openmeteo_all as (

    -- Raw download covers one extra day either side, so LEAD never runs off the end.
    select
        observed_at_utc                                                        as weather_hour_utc,
        temperature_c,
        humidity_pct,
        wind_speed_kmh,
        wmo_weather_code,
        lead(precipitation_mm) over (order by observed_at_utc)                 as precipitation_mm,
        lead(rain_mm)          over (order by observed_at_utc)                 as rain_mm,
        lead(snowfall_cm)      over (order by observed_at_utc)                 as snowfall_cm
    from {{ ref('stg_weather_openmeteo') }}

),

openmeteo as (

    -- Step 1: keep the window. The window dates are New York dates, so convert them to UTC.
    select *
    from openmeteo_all
    where weather_hour_utc >= convert_timezone('America/New_York', 'UTC', '{{ var("overlap_start") }}'::timestamp_ntz)
      and weather_hour_utc <  convert_timezone('America/New_York', 'UTC', '{{ var("overlap_end") }}'::timestamp_ntz)

),

official_hourly as (

    -- Step 2 (Saisha): one official reading per UTC hour, Manhattan only.
    -- Filter on city_id, never city_name: both locations are called "New York" (F3).
    select
        date_trunc('hour', observed_at_utc)                                    as weather_hour_utc,
        condition_main,
        condition_description,
        temperature_c
    from {{ ref('stg_weather_json') }}
    where city_id = {{ var('nyc_city_id') }}
    qualify row_number() over (
        partition by date_trunc('hour', observed_at_utc)
        order by observed_at_utc desc
    ) = 1

),

joined as (

    -- Step 3a: LEFT join, so every Open-Meteo hour survives even with no official reading.
    -- For each hour, remember the most recent hour that DID have an official reading.
    select
        o.*,
        last_value(w.weather_hour_utc) ignore nulls over (
            order by o.weather_hour_utc
            rows between unbounded preceding and current row
        )                                                                      as last_official_hour_utc,
        first_value(w.weather_hour_utc) ignore nulls over (
            order by o.weather_hour_utc
            rows between current row and unbounded following
        )                                                                      as next_official_hour_utc
    from openmeteo o
    left join official_hourly w
        on w.weather_hour_utc = o.weather_hour_utc

),

filled as (

    -- Step 3b: decision D5. Fill a gap only if the WHOLE gap is short (<= cap hours).
    -- A long gap stays missing from its first hour: we do not know when the weather changed.
    select
        j.*,
        datediff('hour', j.last_official_hour_utc, j.weather_hour_utc)         as hours_since_official,
        datediff('hour', j.last_official_hour_utc, j.next_official_hour_utc) - 1
                                                                               as gap_length_hours,
        w.condition_main,
        w.condition_description,
        w.temperature_c                                                        as official_temperature_c_raw
    from joined j
    left join official_hourly w
        on w.weather_hour_utc = j.last_official_hour_utc

),

labelled as (

    select
        filled.*,
        case
            when hours_since_official = 0                                    then 'observed'
            when gap_length_hours <= {{ var('weather_fill_cap_hours') }}     then 'filled'
            else 'missing'
        end                                                                    as official_status
    from filled

)

select
    weather_hour_utc,
    convert_timezone('UTC', 'America/New_York', weather_hour_utc)              as weather_hour_local,

    -- Open-Meteo (complete)
    temperature_c,
    humidity_pct,
    wind_speed_kmh,
    precipitation_mm,
    rain_mm,
    snowfall_cm,
    wmo_weather_code,

    -- Official feed (observed, filled for short gaps, otherwise null - never "dry")
    case when official_status <> 'missing' then condition_main end          as official_condition,
    case when official_status <> 'missing' then condition_description end   as official_condition_description,
    case when official_status <> 'missing' then official_temperature_c_raw end  as official_temperature_c,
    official_status

from labelled
