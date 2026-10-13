-- phase_5_forecast.sql  (run in a Snowflake WORKSHEET, not in dbt — dbt does not run analyses)
-- Phase 5 stretch: does knowing the weather make a daily trip forecast better?
--
-- Design:
--   * Daily grain: one number per day (agg_daily_weather_demand, 726 days).
--   * Time-based split, PAST DATA ONLY for training:
--       train = 2016-07-05 .. 2018-04-30 (665 days)   test = 2018-05-01 .. 2018-06-30 (61 days)
--   * FIRST ATTEMPT trained to 2017-12-31 and forecast all of 2018 H1 (181 days): both models
--     failed (calendar MAPE 57.7%, weather 78.2%; calendar predicted a flat ~25k/day while June was 65k).
--     Cause: 18 months of history = one winter-to-summer cycle, so seasonality was never learned, and a
--     6-month horizon is unrealistic. Fixed by training to end of April 2018 (May-June 2017 seen once).
--   * RESULT: 61 test days. MAE calendar 15,253 vs weather 9,134; MAPE 26.8% vs 16.2%;
--     weather cut the average error by 40.1%.
--     (Unlike the explanatory baseline, nothing here looks at future weeks.)
--   * Two models, identical except for weather:
--       A  "calendar"  : date + is_holiday + is_weekend
--       B  "weather"   : the same + precipitation, snowfall, average temperature
--     So any difference in error is what the weather adds.
--   * Test-period weather = what actually happened (a "perfect forecast").
--     In real use you would feed in the weather FORECAST, so B's gain is a best case.
--   * Scored on test days with no closure hours (riders could not ride on those days).
--   * Separate schema ML_SANDBOX: experiments stay out of the dbt schemas.

-- =========================================================================
-- STEP 0 — Is the forecasting function available on this account?
-- =========================================================================
use database CITIBIKE_WEATHER;
use warehouse CITIBIKE_WH;
create schema if not exists ML_SANDBOX;
use schema ML_SANDBOX;

show snowflake.ml.forecast;
-- Expected: "Query produced no results" (= function exists, no models yet).
-- An error like "does not exist or not authorized" = not available on this account.

-- =========================================================================
-- STEP 1 — Training and test tables
-- =========================================================================
create or replace table daily_input as
select
    date_local::timestamp_ntz          as ds,
    trips,
    iff(is_holiday, 1, 0)              as is_holiday,
    iff(is_weekend, 1, 0)              as is_weekend,
    precipitation_mm,
    snowfall_cm,
    avg_temperature_c,
    closed_hours
from CITIBIKE_WEATHER.DBT_SAISHA_MARTS.AGG_DAILY_WEATHER_DEMAND;

-- Check: 726 rows, 665 train, 61 test
select count(*) as all_days,
       count_if(ds <  '2018-05-01') as train_days,
       count_if(ds >= '2018-05-01') as test_days
from daily_input;

create or replace view train_calendar as
select ds, trips, is_holiday, is_weekend
from daily_input where ds < '2018-05-01';

create or replace view train_weather as
select ds, trips, is_holiday, is_weekend, precipitation_mm, snowfall_cm, avg_temperature_c
from daily_input where ds < '2018-05-01';

-- Test inputs: the features only (no trips — that is what we predict)
create or replace view test_calendar as
select ds, is_holiday, is_weekend
from daily_input where ds >= '2018-05-01';

create or replace view test_weather as
select ds, is_holiday, is_weekend, precipitation_mm, snowfall_cm, avg_temperature_c
from daily_input where ds >= '2018-05-01';

-- =========================================================================
-- STEP 2 — Train the two models
-- =========================================================================
create or replace snowflake.ml.forecast model_calendar(
    input_data        => table(train_calendar),
    timestamp_colname => 'ds',
    target_colname    => 'trips'
);

create or replace snowflake.ml.forecast model_weather(
    input_data        => table(train_weather),
    timestamp_colname => 'ds',
    target_colname    => 'trips'
);

-- =========================================================================
-- STEP 3 — Forecast the test period (May-June 2018) with each model
-- =========================================================================
call model_calendar!forecast(
    input_data        => table(test_calendar),
    timestamp_colname => 'ds'
);
create or replace table forecast_calendar as
select * from table(result_scan(last_query_id()));

call model_weather!forecast(
    input_data        => table(test_weather),
    timestamp_colname => 'ds'
);
create or replace table forecast_weather as
select * from table(result_scan(last_query_id()));

-- Check: 61 rows each
select (select count(*) from forecast_calendar) as calendar_rows,
       (select count(*) from forecast_weather)  as weather_rows;

-- =========================================================================
-- STEP 4 — Score: how far off is each model, on average?
--   MAE  = average miss in trips per day
--   MAPE = average miss as a % of the actual day
-- =========================================================================
with scored as (
    select
        d.ds,
        d.trips                    as actual,
        c.forecast                 as pred_calendar,
        w.forecast                 as pred_weather
    from daily_input d
    join forecast_calendar c on c.ts = d.ds
    join forecast_weather  w on w.ts = d.ds
    where d.closed_hours = 0
)
select
    count(*)                                                        as test_days_scored,
    round(avg(abs(actual - pred_calendar)))                          as mae_calendar,
    round(avg(abs(actual - pred_weather)))                           as mae_weather,
    round(100 * avg(abs(actual - pred_calendar) / actual), 1)        as mape_calendar_pct,
    round(100 * avg(abs(actual - pred_weather)  / actual), 1)        as mape_weather_pct,
    round(100 * (1 - avg(abs(actual - pred_weather))
                   / avg(abs(actual - pred_calendar))), 1)           as error_reduction_pct
from scored;

-- =========================================================================
-- STEP 5 (optional) — Which features mattered most in the weather model?
-- =========================================================================
call model_weather!explain_feature_importance();
