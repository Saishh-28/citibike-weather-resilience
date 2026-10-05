-- int_trips_hourly
-- One row per UTC hour that had at least one trip: how many trips STARTED in that hour.
-- Written by Saisha, 5 Oct 2026.
--
-- Decisions:
--   * Demand = trips STARTED (A7). The rider decides at the start, under the weather at
--     that moment, so start time is what we compare to weather.
--   * Hours are counted in UTC, not New York time. UTC has no missing hour in March and
--     no doubled hour in November, so every hour appears once (friend's review, 5 Oct).
--   * The window filter uses started_at (New York time) because the overlap dates in
--     dbt_project.yml are New York calendar dates.
--
-- Known limitation (declared):
--   * Trips starting 01:00-01:59 on a fall-back night are ambiguous: that local hour
--     happened twice, and the raw data does not say which one. Snowflake puts them in
--     one of the two UTC hours. About one hour a year; too small to change any result.
--
-- Hours with zero trips do NOT appear here. The hourly spine (built later) fixes that.

select
    date_trunc('hour', convert_timezone('America/New_York', 'UTC', started_at)) as trip_hour_utc,
    count(*)                                                                     as trip_count
from {{ ref('stg_citibike_lab') }}
where started_at >= '{{ var("overlap_start") }}'
  and started_at <  '{{ var("overlap_end") }}'
group by 1
