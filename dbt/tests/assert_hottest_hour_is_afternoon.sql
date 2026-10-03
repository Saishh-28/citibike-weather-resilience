-- Timezone guard (plan §10, Phase 0 check 3).
-- After converting to New York time, the hottest average hour of the day must
-- fall between 12:00 and 17:00. If the UTC conversion is ever broken or removed,
-- the peak jumps to ~19:00-20:00 and this test fails instead of the dashboard
-- silently shifting rain onto the wrong hours.
-- Returns a row (= failure) for each source whose peak is outside the afternoon.

with official as (

    select
        'official_feed'                    as source,
        hour(observed_at_local)            as hr,
        avg(temperature_c)                 as avg_temp_c
    from {{ ref('stg_weather_json') }}
    where city_id = {{ var('nyc_city_id') }}
    group by 1, 2

),

openmeteo as (

    select
        'openmeteo'                        as source,
        hour(observed_at_local)            as hr,
        avg(temperature_c)                 as avg_temp_c
    from {{ ref('stg_weather_openmeteo') }}
    group by 1, 2

),

peaks as (

    select source, hr as hottest_hour, avg_temp_c
    from (select * from official union all select * from openmeteo)
    qualify row_number() over (partition by source order by avg_temp_c desc) = 1

)

select *
from peaks
where hottest_hour not between 12 and 17
