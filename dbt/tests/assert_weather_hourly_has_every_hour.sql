-- Every hour in the window must have exactly one weather row (726 days x 24 = 17,424).
-- A missing weather hour would silently become a "dry" hour downstream.
-- Returns a row (= test fails) if the count is wrong.

select count(*) as weather_hours
from {{ ref('int_weather_hourly') }}
having count(*) <> 17424
