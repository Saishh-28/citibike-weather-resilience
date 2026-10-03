-- A ride may only "end before it starts" on a daylight-saving fall-back night,
-- when the clock goes 1:59am -> 1:00am. In the US (2007 onwards) that is the
-- first Sunday of November, and the affected rides start in the 1am hour.
-- Phase 0: all 132 such rides in the overlap window matched this rule.
-- Any other case is real data corruption and fails this test.

select
    trip_id,
    started_at,
    ended_at,
    trip_duration_seconds
from {{ ref('stg_citibike_lab') }}
where ended_at < started_at
  and not (
        month(started_at) = 11
    and dayofweek(started_at) = 0          -- Sunday
    and day(started_at) <= 7               -- first Sunday of the month
    and hour(started_at) = 1
  )
