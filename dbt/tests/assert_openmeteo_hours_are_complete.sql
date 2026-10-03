-- Open-Meteo is the complete hourly backbone for rainfall, so it must have
-- exactly one row for every UTC hour between its first and last timestamp.
-- A missing hour would later look like a "dry" hour and dilute the rain effect.
-- Returns a row (= failure) if the count does not match the span.

with span as (

    select
        min(observed_at_utc)                                         as first_hour,
        max(observed_at_utc)                                         as last_hour,
        count(*)                                                     as actual_hours,
        datediff('hour', min(observed_at_utc), max(observed_at_utc)) + 1 as expected_hours
    from {{ ref('stg_weather_openmeteo') }}

)

select *
from span
where actual_hours <> expected_hours
