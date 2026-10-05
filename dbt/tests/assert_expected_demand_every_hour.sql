-- Every hour in the window must be present exactly once (17,424), and every comparable
-- hour must have an expected value. Returns a row (= test fails) otherwise.

select 'row count' as problem, count(*) as n
from {{ ref('fct_hourly_expected_demand') }}
having count(*) <> 17424

union all

select 'comparable hour without expectation', count(*)
from {{ ref('fct_hourly_expected_demand') }}
where is_comparable_hour and (expected_trips is null or expected_trips <= 0)
having count(*) > 0
