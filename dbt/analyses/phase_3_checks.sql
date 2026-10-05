-- Phase 3 verification queries (run 5 Oct 2026 with Preview in dbt Studio).
-- These are checks a human reads, not pipeline steps, so they live in analyses/:
-- dbt compiles them but never builds them as tables.
-- Expected values are written next to each check; all matched on 5 Oct 2026.


-- 1. int_trips_hourly: window and trip total --------------------------------------------
-- Expect: hours 17,290 (134 hours had no trips), first 2016-07-05 04:00 UTC,
--         last 2018-07-01 03:00 UTC, trips 32,012,552 (= Phase 1 reconciliation).
select
    count(*)            as hours,
    min(trip_hour_utc)  as first_hour,
    max(trip_hour_utc)  as last_hour,
    sum(trip_count)     as total_trips
from {{ ref('int_trips_hourly') }};


-- 2. Where are the 134 missing trip hours? ------------------------------------------------
-- Expect: 77h (Stella, Mar 2017), 38h (Feb 2017 blizzard), 16h (Mar 2018 nor'easter),
--         plus 1h each: second 1am on 2016-11-06 and 2017-11-05 (DST), 2017-04-04 2am.
with ordered as (
    select
        trip_hour_utc,
        lag(trip_hour_utc) over (order by trip_hour_utc) as previous_hour
    from {{ ref('int_trips_hourly') }}
)
select
    previous_hour                                        as last_hour_with_trips,
    trip_hour_utc                                        as next_hour_with_trips,
    datediff('hour', previous_hour, trip_hour_utc) - 1   as hours_missing
from ordered
where datediff('hour', previous_hour, trip_hour_utc) > 1
order by hours_missing desc;


-- 3. int_weather_hourly: official-feed coverage -------------------------------------------
-- Expect: observed 12,608 (72.4%), filled 1,982 (11.4%), missing 2,834 (16.3%).
select
    official_status,
    count(*)                                         as hours,
    round(100 * count(*) / sum(count(*)) over (), 1) as pct
from {{ ref('int_weather_hourly') }}
group by 1
order by 2 desc;


-- 4. fct_hourly_demand: everything at once --------------------------------------------------
-- Expect: 17,424 / 17,424 / 32,012,552 / 2016-07-05 04:00 / 2018-07-01 03:00 /
--         closed 131 / trips while closed 0 / quiet zero hours 3 /
--         12,608 / 1,982 / 2,834 / blank rain 0 / local 1am 728 / local 2am 724.
-- 728 and 724: 1am happens twice on each fall-back night, 2am never on each spring-forward.
select
    count(*)                                              as total_hours,
    count(distinct hour_utc)                              as distinct_hours,
    sum(trip_count)                                       as total_trips,
    min(hour_utc)                                         as first_hour,
    max(hour_utc)                                         as last_hour,
    count_if(is_system_closed)                            as closed_hours,
    sum(iff(is_system_closed, trip_count, 0))             as trips_while_closed,
    count_if(trip_count = 0 and not is_system_closed)     as quiet_zero_hours,
    count_if(official_status = 'observed')                as observed,
    count_if(official_status = 'filled')                  as filled,
    count_if(official_status = 'missing')                 as missing,
    count_if(precipitation_mm is null)                    as blank_rain,
    count_if(hour_of_day_local = 1)                       as local_1am_hours,
    count_if(hour_of_day_local = 2)                       as local_2am_hours
from {{ ref('fct_hourly_demand') }};


-- 5. dim_date and rider split --------------------------------------------------------------
-- Expect: 726 dates, 22 holidays, members 28,555,718 (89.2%), casual 3,405,054 (10.6%),
--         unknown 51,780 (0.16%); sum = 32,012,552.
select
    (select count(*)                      from {{ ref('dim_date') }})          as dates,
    (select count_if(is_holiday)          from {{ ref('dim_date') }})          as holidays,
    (select sum(member_trip_count)        from {{ ref('fct_hourly_demand') }}) as members,
    (select sum(casual_trip_count)        from {{ ref('fct_hourly_demand') }}) as casual,
    (select sum(unknown_rider_trip_count) from {{ ref('fct_hourly_demand') }}) as unknown_type;
