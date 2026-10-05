-- One row per New York date in the window, and every day classified.
-- Returns a row (= test fails) if not exactly 726 dates or any day_type is unexpected.

select 'row count' as problem, count(*) as n
from {{ ref('agg_daily_weather_demand') }}
having count(*) <> 726

union all

select 'bad day_type', count(*)
from {{ ref('agg_daily_weather_demand') }}
where day_type not in ('Snowy', 'Rainy', 'Dry', 'Light') or day_type is null
having count(*) > 0
