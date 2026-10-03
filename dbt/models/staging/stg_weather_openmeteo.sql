-- stg_weather_openmeteo
-- One row per hour. Open-Meteo stores each variable as a parallel array
-- (hourly.time[i] goes with hourly.precipitation[i], ...). We flatten the
-- time array and use its index to pick the matching value from every other array.
--
-- Times are UTC (downloaded with timezone=GMT) and go through the same
-- UTC -> America/New_York conversion as the official feed.

with source as (

    select * from {{ source('raw', 'raw_weather_openmeteo') }}

),

hourly as (

    select
        to_timestamp_ntz(t.value::varchar, 'YYYY-MM-DD"T"HH24:MI')        as observed_at_utc,
        convert_timezone(
            'UTC', 'America/New_York',
            to_timestamp_ntz(t.value::varchar, 'YYYY-MM-DD"T"HH24:MI')
        )                                                                as observed_at_local,

        get(s.v:hourly.temperature_2m,       t.index)::float             as temperature_c,
        get(s.v:hourly.relative_humidity_2m, t.index)::float             as humidity_pct,
        get(s.v:hourly.precipitation,        t.index)::float             as precipitation_mm,
        get(s.v:hourly.rain,                 t.index)::float             as rain_mm,
        get(s.v:hourly.snowfall,             t.index)::float             as snowfall_cm,
        get(s.v:hourly.wind_speed_10m,       t.index)::float             as wind_speed_kmh,
        get(s.v:hourly.weather_code,         t.index)::number            as wmo_weather_code,

        s.v:latitude::float                                              as grid_lat,
        s.v:longitude::float                                             as grid_lon,
        s._source_file                                                   as source_file

    from source s,
         lateral flatten(input => s.v:hourly.time) t

)

select * from hourly
