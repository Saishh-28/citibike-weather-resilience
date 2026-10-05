-- Members + casual + unknown must equal the total in every hour.
-- If this fails, a rider type was double-counted or dropped.

select hour_utc, trip_count, member_trip_count, casual_trip_count, unknown_rider_trip_count
from {{ ref('fct_hourly_demand') }}
where member_trip_count + casual_trip_count + unknown_rider_trip_count <> trip_count
