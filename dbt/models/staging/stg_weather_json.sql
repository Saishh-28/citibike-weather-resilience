-- stg_weather_json
-- One row per real observation from the official feed.
--
-- Applied here:
--   * Flatten the JSON into typed columns.
--   * Epoch seconds -> UTC -> America/New_York with CONVERT_TIMEZONE
--     (handles daylight saving; a fixed "-5 hours" would be wrong half the year).
--   * Kelvin -> Celsius.
--   * Remove exact-copy duplicates (D2). Phase 0 showed 0 duplicate timestamps
--     with differing values, so keeping one copy loses no information.
--
-- NOT applied here (they are decisions, so they live in the intermediate layer):
--   * Filtering to the Manhattan city ID - both city IDs are kept in staging.
--   * Rolling up to hourly grain and gap filling.

with source as (

    select * from {{ source('raw', 'raw_weather_json') }}

),

flattened as (

    select
        v:city.id::number                                   as city_id,
        v:city.name::varchar                                as city_name,
        v:city.coord.lat::float                             as city_lat,
        v:city.coord.lon::float                             as city_lon,

        v:time::number                                      as observed_epoch,
        to_timestamp_ntz(v:time::number)                    as observed_at_utc,
        convert_timezone(
            'UTC', 'America/New_York',
            to_timestamp_ntz(v:time::number)
        )                                                   as observed_at_local,

        v:main.temp::float - 273.15                         as temperature_c,
        v:main.temp_min::float - 273.15                     as temperature_min_c,
        v:main.temp_max::float - 273.15                     as temperature_max_c,
        v:main.humidity::float                              as humidity_pct,
        v:main.pressure::float                              as pressure_hpa,

        -- Unit not confirmed (likely m/s), so named _raw. Not used downstream:
        -- wind speed in the marts comes from Open-Meteo (km/h).
        v:wind.speed::float                                 as wind_speed_raw,
        v:wind.deg::float                                   as wind_direction_deg,
        v:clouds.all::float                                 as cloud_cover_pct,

        v:weather[0].main::varchar                          as condition_main,
        v:weather[0].description::varchar                   as condition_description,
        array_size(v:weather)                               as condition_count,

        _source_file                                        as source_file,
        _source_row                                         as source_row

    from source

),

deduplicated as (

    select *
    from flattened
    qualify row_number() over (
        partition by city_id, observed_epoch
        order by source_file, source_row
    ) = 1

)

select
    city_id::varchar || '-' || observed_epoch::varchar      as weather_observation_id,
    *
from deduplicated
