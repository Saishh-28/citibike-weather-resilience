-- Reconciliation: the fact table must contain every trip in the window, no more, no less.
-- Compares the fact table's total with a fresh count straight from staging.
-- Returns a row (= test fails) if they differ, or if the row count is not 17,424.

with fact as (
    select count(*) as hours, sum(trip_count) as trips
    from {{ ref('fct_hourly_demand') }}
),

source_count as (
    select count(*) as trips
    from {{ ref('stg_citibike_lab') }}
    where started_at >= '{{ var("overlap_start") }}'
      and started_at <  '{{ var("overlap_end") }}'
)

select f.hours, f.trips as fact_trips, s.trips as source_trips
from fact f
cross join source_count s
where f.trips <> s.trips
   or f.hours <> 17424
