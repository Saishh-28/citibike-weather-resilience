-- ============================================================================
-- CITIBIKE & WEATHER DATA ENGINEERING PIPELINE
-- PHASE 0: SOURCE & DATA VALIDATION
-- Snowflake / AWS S3
-- ============================================================================
-- Purpose:
-- Validate source accessibility, schemas, temporal coverage, dataset overlap,
-- timestamp structure, timezone handling, and weather observation frequency
-- before beginning the production ELT pipeline.
--
-- Author: Saisha
-- ============================================================================


-- ----------------------------------------------------------------------------
-- STEP 1: DATABASE, SCHEMA & WAREHOUSE INITIALIZATION
-- ----------------------------------------------------------------------------

CREATE WAREHOUSE IF NOT EXISTS CITIBIKE_WH
    WITH WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE;

USE WAREHOUSE CITIBIKE_WH;

CREATE DATABASE IF NOT EXISTS CITIBIKE_WEATHER;

CREATE SCHEMA IF NOT EXISTS CITIBIKE_WEATHER.RAW;

USE DATABASE CITIBIKE_WEATHER;
USE SCHEMA RAW;


-- ----------------------------------------------------------------------------
-- STEP 2: SOURCE STAGES
-- ----------------------------------------------------------------------------
-- External S3 stages used to inspect the available source data.
-- No production ingestion occurs in Phase 0.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE STAGE CITIBIKE_LAB_STAGE
    URL = 's3://snowflake-workshop-lab/japan/citibike-trips/';

CREATE OR REPLACE STAGE WEATHER_STAGE
    URL = 's3://snowflake-workshop-lab/weather-nyc/';


-- Verify that the source locations are accessible.

LIST @CITIBIKE_LAB_STAGE;

LIST @WEATHER_STAGE;


-- ----------------------------------------------------------------------------
-- STEP 3: TEMPORARY FILE FORMATS
-- ----------------------------------------------------------------------------
-- These formats are used only for source inspection during Phase 0.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FILE FORMAT CITIBIKE_WEATHER.RAW.TMP_CSV_FORMAT
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    RECORD_DELIMITER = '\n'
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"';

CREATE OR REPLACE FILE FORMAT CITIBIKE_WEATHER.RAW.TMP_JSON_FORMAT
    TYPE = 'JSON'
    STRIP_OUTER_ARRAY = TRUE;


-- ----------------------------------------------------------------------------
-- STEP 4: CITIBIKE SOURCE VALIDATION
-- ----------------------------------------------------------------------------

-- Inspect the historical CitiBike CSV structure.

SELECT
    $1 AS tripduration,
    $2 AS starttime,
    $3 AS stoptime,
    $4 AS start_station_id,
    $5 AS start_station_name,
    $6 AS start_latitude,
    $7 AS start_longitude,
    $8 AS end_station_id
FROM @CITIBIKE_LAB_STAGE
    (FILE_FORMAT => 'CITIBIKE_WEATHER.RAW.TMP_CSV_FORMAT')
LIMIT 5;


-- Validate historical CitiBike coverage and row count.

SELECT
    MIN($2::TIMESTAMP) AS citibike_earliest_date,
    MAX($2::TIMESTAMP) AS citibike_latest_date,
    COUNT(*) AS citibike_row_count
FROM @CITIBIKE_LAB_STAGE
    (FILE_FORMAT => 'CITIBIKE_WEATHER.RAW.TMP_CSV_FORMAT');


-- ----------------------------------------------------------------------------
-- STEP 5: WEATHER SOURCE VALIDATION
-- ----------------------------------------------------------------------------

-- Inspect the raw JSON structure.

SELECT
    $1 AS weather_record
FROM @WEATHER_STAGE
    (FILE_FORMAT => 'CITIBIKE_WEATHER.RAW.TMP_JSON_FORMAT')
LIMIT 3;


-- Validate weather record count and timestamp coverage.
--
-- IMPORTANT:
-- The source `time` field is Unix epoch seconds, not a formatted
-- timestamp. Therefore it must be converted explicitly.

SELECT
    COUNT(*) AS total_records,
    COUNT(DISTINCT $1:time::INTEGER) AS unique_timestamps,
    MIN(
        TO_TIMESTAMP_NTZ($1:time::INTEGER)
    ) AS first_timestamp_utc,
    MAX(
        TO_TIMESTAMP_NTZ($1:time::INTEGER)
    ) AS last_timestamp_utc
FROM @WEATHER_STAGE
    (FILE_FORMAT => 'CITIBIKE_WEATHER.RAW.TMP_JSON_FORMAT');


-- ----------------------------------------------------------------------------
-- STEP 6: DATASET OVERLAP VALIDATION
-- ----------------------------------------------------------------------------
-- Check whether the historical CitiBike data overlaps the available
-- weather period.
-- ----------------------------------------------------------------------------

SELECT
    COUNT(*) AS overlapping_rides,
    MIN($2::TIMESTAMP) AS overlap_start,
    MAX($2::TIMESTAMP) AS overlap_end
FROM @CITIBIKE_LAB_STAGE
    (FILE_FORMAT => 'CITIBIKE_WEATHER.RAW.TMP_CSV_FORMAT')
WHERE $2::TIMESTAMP >= '2016-07-05'
  AND $2::TIMESTAMP <= '2019-06-25';


-- ----------------------------------------------------------------------------
-- STEP 7: EXPLORATORY TIMESTAMP VALIDATION
-- ----------------------------------------------------------------------------
--
-- Initial hypothesis:
-- The weather records might contain a `dt` epoch field that could be
-- compared against another timestamp field to determine the source
-- timezone.
--
-- Test:
-- Check whether the `dt` field exists and can be used.
--
-- Result:
-- `dt` is NULL in the source, so this approach cannot be used.
--
-- Decision:
-- Inspect the raw JSON structure and use the available `time` field,
-- which is stored as Unix epoch seconds.
-- ----------------------------------------------------------------------------

WITH weather AS (
    SELECT
        $1:time::TIMESTAMP AS weather_time,
        $1:dt::INTEGER AS epoch_time
    FROM @WEATHER_STAGE
        (FILE_FORMAT => 'CITIBIKE_WEATHER.RAW.TMP_JSON_FORMAT')
)
SELECT
    weather_time,
    TO_TIMESTAMP(epoch_time) AS epoch_as_timestamp,
    DATEDIFF(
        'hour',
        TO_TIMESTAMP(epoch_time),
        weather_time
    ) AS hour_difference
FROM weather
WHERE epoch_time IS NOT NULL
LIMIT 20;


-- ----------------------------------------------------------------------------
-- STEP 8: RESOLVED WEATHER TIMESTAMP CONVERSION
-- ----------------------------------------------------------------------------
--
-- The raw JSON inspection established that `time` is Unix epoch seconds.
--
-- Convert:
--     Unix epoch → UTC → America/New_York
--
-- CONVERT_TIMEZONE is used rather than a fixed UTC offset so that
-- daylight-saving transitions are handled correctly.
-- ----------------------------------------------------------------------------

SELECT
    $1:time::INTEGER AS epoch_time,

    TO_TIMESTAMP_NTZ(
        $1:time::INTEGER
    ) AS timestamp_utc,

    CONVERT_TIMEZONE(
        'UTC',
        'America/New_York',
        TO_TIMESTAMP_NTZ($1:time::INTEGER)
    ) AS timestamp_nyc

FROM @WEATHER_STAGE
    (FILE_FORMAT => 'CITIBIKE_WEATHER.RAW.TMP_JSON_FORMAT')

LIMIT 10;


-- ----------------------------------------------------------------------------
-- STEP 9: WEATHER OBSERVATION FREQUENCY
-- ----------------------------------------------------------------------------
-- Determine whether weather observations are already hourly or whether
-- further aggregation/deduplication will be required downstream.
-- ----------------------------------------------------------------------------

WITH weather AS (
    SELECT
        TO_TIMESTAMP_NTZ($1:time::INTEGER) AS weather_time
    FROM @WEATHER_STAGE
        (FILE_FORMAT => 'CITIBIKE_WEATHER.RAW.TMP_JSON_FORMAT')
),

spacing AS (
    SELECT
        weather_time,

        LAG(weather_time) OVER (
            ORDER BY weather_time
        ) AS previous_time,

        DATEDIFF(
            'minute',
            LAG(weather_time) OVER (
                ORDER BY weather_time
            ),
            weather_time
        ) AS minutes_between

    FROM weather
)

SELECT
    minutes_between,
    COUNT(*) AS occurrences
FROM spacing
WHERE minutes_between IS NOT NULL
GROUP BY minutes_between
ORDER BY minutes_between;


-- ----------------------------------------------------------------------------
-- PHASE 0 COMPLETE
-- ----------------------------------------------------------------------------
--
-- Key findings from source validation:
--
-- 1. Historical CitiBike data is available in the S3 source.
--
-- 2. Historical CitiBike coverage:
--       2013-06-01 → 2018-06-30
--
-- 3. Weather data is available in the S3 source.
--
-- 4. The weather `time` field is Unix epoch seconds.
--
-- 5. The weather source can be converted from UTC to
--    America/New_York using Snowflake timezone conversion.
--
-- 6. CitiBike and weather data overlap from:
--       2016-07-05 → 2018-06-30
--
-- 7. Weather observations are not cleanly hourly and contain
--    duplicate/irregular timestamps.
--
-- 8. The initial `dt` timezone hypothesis was tested but could
--    not be used because the field was unavailable.
--
-- These findings determine the design of the raw ingestion and
-- dbt transformation layers in Phase 1.
-- ============================================================================

-- ============================================================================
-- MORE PRE-CHECKS: DEDUPLICATION & TIMEZONE VALIDATION
-- ============================================================================

-- 1. Duplicates Check: Verify if duplicate timestamps stem from multiple city IDs
SELECT 
    $1:city.id::INT AS city_id, 
    $1:city.name::STRING AS city_name, 
    COUNT(*) AS record_count
FROM @WEATHER_STAGE (FILE_FORMAT => 'CITIBIKE_WEATHER.RAW.TMP_JSON_FORMAT')
GROUP BY 1, 2 
ORDER BY 3 DESC;


-- 2 & 3. Hourly Coverage & Afternoon Peak Temperature Test (UTC -> Local NYC Validation)
WITH weather_nyc AS (
  SELECT 
      CONVERT_TIMEZONE('UTC', 'America/New_York', TO_TIMESTAMP_NTZ($1:time::INT)) AS ts_nyc,
      $1:main.temp::FLOAT - 273.15 AS temp_c
  FROM @WEATHER_STAGE (FILE_FORMAT => 'CITIBIKE_WEATHER.RAW.TMP_JSON_FORMAT')
  WHERE ts_nyc BETWEEN '2016-07-05' AND '2018-07-01'
)
SELECT 
    HOUR(ts_nyc) AS hr, 
    ROUND(AVG(temp_c), 2) AS avg_temp_c,
    COUNT(DISTINCT DATE_TRUNC('hour', ts_nyc)) AS hours_covered
FROM weather_nyc 
GROUP BY 1 
ORDER BY 1;


WITH spine AS (
  SELECT DATEADD('hour', SEQ4(), '2016-07-05 00:00'::TIMESTAMP_NTZ) AS hr
  FROM TABLE(GENERATOR(ROWCOUNT => 17424))
),
obs AS (
  SELECT DISTINCT DATE_TRUNC('hour',
    CONVERT_TIMEZONE('UTC','America/New_York', TO_TIMESTAMP_NTZ($1:time::INT))) AS hr
  FROM @WEATHER_STAGE (FILE_FORMAT => 'CITIBIKE_WEATHER.RAW.TMP_JSON_FORMAT')
),
flagged AS (
  SELECT s.hr, o.hr IS NULL AS is_gap,
         ROW_NUMBER() OVER (ORDER BY s.hr)
       - ROW_NUMBER() OVER (PARTITION BY o.hr IS NULL ORDER BY s.hr) AS grp
  FROM spine s LEFT JOIN obs o ON s.hr = o.hr
),
runs AS (
  SELECT MIN(hr) AS gap_start, COUNT(*) AS gap_hours
  FROM flagged WHERE is_gap GROUP BY grp
)
SELECT CASE WHEN gap_hours = 1 THEN '1h'
            WHEN gap_hours <= 3 THEN '2-3h'
            WHEN gap_hours <= 24 THEN '4-24h'
            ELSE '>24h' END AS gap_length,
       COUNT(*) AS num_gaps, SUM(gap_hours) AS total_hours, MIN(gap_start) AS example
FROM runs GROUP BY 1 ORDER BY MIN(gap_hours);

SELECT $1:city.id::INT      AS city_id,
       $1:city.name::STRING AS city_name,
       COUNT(*)             AS records,
       COUNT(DISTINCT $1:time::INT) AS unique_times
FROM @WEATHER_STAGE (FILE_FORMAT => 'CITIBIKE_WEATHER.RAW.TMP_JSON_FORMAT')
GROUP BY 1, 2
ORDER BY records DESC;


-- A. Where is each city, and are the duplicates identical copies?
WITH w AS (
  SELECT $1:city.id::INT AS city_id,
         $1:city.coord.lat::FLOAT AS lat, $1:city.coord.lon::FLOAT AS lon,
         $1:time::INT AS t,
         $1:main.temp::FLOAT AS temp_k,
         $1:weather[0].main::STRING AS cond
  FROM @WEATHER_STAGE (FILE_FORMAT => 'CITIBIKE_WEATHER.RAW.TMP_JSON_FORMAT')
),
dupes AS (
  SELECT city_id, t,
         COUNT(*) AS n,
         COUNT(DISTINCT temp_k) AS distinct_temps,
         COUNT(DISTINCT cond)   AS distinct_conds
  FROM w GROUP BY 1, 2 HAVING COUNT(*) > 1
)
SELECT w.city_id, ANY_VALUE(lat) AS lat, ANY_VALUE(lon) AS lon,
       (SELECT COUNT(*) FROM dupes d WHERE d.city_id = w.city_id) AS dup_timestamps,
       (SELECT COUNT_IF(distinct_temps > 1 OR distinct_conds > 1)
          FROM dupes d WHERE d.city_id = w.city_id)             AS dups_that_disagree
FROM w GROUP BY w.city_id;

-- B. Hourly coverage for NYC only (5128581), within the trip overlap window
WITH obs AS (
  SELECT DISTINCT DATE_TRUNC('hour',
    CONVERT_TIMEZONE('UTC','America/New_York', TO_TIMESTAMP_NTZ($1:time::INT))) AS hr
  FROM @WEATHER_STAGE (FILE_FORMAT => 'CITIBIKE_WEATHER.RAW.TMP_JSON_FORMAT')
  WHERE $1:city.id::INT = 5128581
)
SELECT COUNT(*) AS hours_covered, ROUND(COUNT(*) / 17424 * 100, 1) AS pct_covered
FROM obs WHERE hr >= '2016-07-05' AND hr < '2018-07-01';


WITH w AS (
  SELECT $1:city.id::INT            AS city_id,
         $1:city.coord.lat::FLOAT   AS lat,
         $1:city.coord.lon::FLOAT   AS lon,
         $1:time::INT               AS t,
         $1:main.temp::FLOAT        AS temp_k,
         $1:weather[0].main::STRING AS cond
  FROM @WEATHER_STAGE (FILE_FORMAT => 'CITIBIKE_WEATHER.RAW.TMP_JSON_FORMAT')
),
loc AS (
  SELECT city_id, MIN(lat) AS lat, MIN(lon) AS lon, COUNT(DISTINCT lat || ',' || lon) AS n_coords
  FROM w GROUP BY city_id
),
dupes AS (
  SELECT city_id, t,
         COUNT(DISTINCT temp_k) AS distinct_temps,
         COUNT(DISTINCT cond)   AS distinct_conds
  FROM w GROUP BY city_id, t
  HAVING COUNT(*) > 1
),
dup_summary AS (
  SELECT city_id,
         COUNT(*)                                            AS dup_timestamps,
         COUNT_IF(distinct_temps > 1 OR distinct_conds > 1)  AS dups_that_disagree
  FROM dupes GROUP BY city_id
)
SELECT l.city_id, l.lat, l.lon, l.n_coords,
       d.dup_timestamps, d.dups_that_disagree
FROM loc l
LEFT JOIN dup_summary d ON l.city_id = d.city_id
ORDER BY l.city_id;

SELECT
  COUNT(*)                                        AS rides,
  MIN(TRY_TO_NUMBER($1::STRING))                  AS shortest_seconds,
  MAX(TRY_TO_NUMBER($1::STRING))                  AS longest_seconds,
  COUNT_IF(TRY_TO_NUMBER($1::STRING) < 60)        AS under_1_minute,
  COUNT_IF(TRY_TO_NUMBER($1::STRING) > 86400)     AS over_24_hours,
  COUNT_IF(TRY_TO_NUMBER($1::STRING) > 2592000)   AS over_30_days,
  COUNT_IF($3::TIMESTAMP < $2::TIMESTAMP)         AS ends_before_start,
  COUNT_IF($8 IS NULL OR $8::STRING = 'NULL')     AS no_end_station
FROM @CITIBIKE_LAB_STAGE (FILE_FORMAT => 'CITIBIKE_WEATHER.RAW.TMP_CSV_FORMAT')
WHERE $2::TIMESTAMP BETWEEN '2016-07-05' AND '2018-07-01';


SELECT $2::DATE AS ride_date, HOUR($2::TIMESTAMP) AS start_hour, COUNT(*) AS rides
FROM @CITIBIKE_LAB_STAGE (FILE_FORMAT => 'CITIBIKE_WEATHER.RAW.TMP_CSV_FORMAT')
WHERE $2::TIMESTAMP BETWEEN '2016-07-05' AND '2018-07-01'
  AND $3::TIMESTAMP < $2::TIMESTAMP
GROUP BY 1, 2 ORDER BY 3 DESC;