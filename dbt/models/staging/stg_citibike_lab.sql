-- stg_citibike_lab
-- One row per raw trip row. Rename + type only. No filtering, no business logic.
--
-- Decisions applied here (all type-level):
--   * Station IDs stay TEXT. In the 2026 schema they look like '6322.01';
--     storing them as numbers would make '6322.01' and '6322.1' collide.
--   * Trip timestamps are already NYC local time (assumption A1, verified),
--     so no timezone conversion is needed for trips.
--   * Duration comes from the source column, never from ended - started:
--     on daylight-saving "fall back" nights the clock repeats 1am, so 132 real
--     rides in the overlap window appear to end before they start (Phase 0).

with source as (

    select * from {{ source('raw', 'raw_citibike_lab') }}

),

renamed as (

    select
        -- keys & lineage
        md5(_source_file || '|' || _source_row::varchar)   as trip_id,
        _source_file                                        as source_file,
        _source_row                                         as source_row,

        -- time (NYC local, no timezone attached)
        try_to_timestamp_ntz(starttime)                     as started_at,
        try_to_timestamp_ntz(stoptime)                      as ended_at,
        try_to_number(tripduration)                         as trip_duration_seconds,

        -- stations (IDs kept as text on purpose)
        nullif(trim(start_station_id), 'NULL')              as start_station_id,
        nullif(trim(start_station_name), 'NULL')            as start_station_name,
        try_to_double(start_station_latitude)               as start_station_lat,
        try_to_double(start_station_longitude)              as start_station_lon,
        nullif(trim(end_station_id), 'NULL')                as end_station_id,
        nullif(trim(end_station_name), 'NULL')              as end_station_name,
        try_to_double(end_station_latitude)                 as end_station_lat,
        try_to_double(end_station_longitude)                as end_station_lon,

        -- rider & bike
        try_to_number(bikeid)                               as bike_id,
        nullif(trim(membership_type), '')                   as membership_type,
        nullif(trim(usertype), '')                          as usertype,
        try_to_number(birth_year)                           as birth_year,
        try_to_number(gender)                               as gender_code,

        _loaded_at                                          as loaded_at

    from source

)

select * from renamed
