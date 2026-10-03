-- ============================================================================
-- CITIBIKE & WEATHER DATA ENGINEERING PIPELINE
-- PHASE 1: RAW LANDING (the "L" in ELT)
-- Snowflake / AWS S3 / Open-Meteo
-- ============================================================================
-- Purpose:
--   Copy every source into Snowflake EXACTLY as it arrives. No filtering,
--   no deduplication, no type conversion, no timezone conversion.
--   All Phase 0 decisions (NYC-only city, dedup, UTC -> New York,
--   extreme-duration flags, 3h gap fill) are applied later in dbt.
--
-- Why load everything unchanged:
--   If a transformation decision turns out to be wrong, we fix one dbt model
--   and re-run. We never have to go back to the source and re-extract.
--
-- Done when:
--   Every raw table exists and its row count reconciles with Phase 0.
--
-- Run order: top to bottom. STEP 2 is a decision gate - read its result
-- before running STEP 3.
--
-- Author: Saisha
-- ============================================================================


-- ----------------------------------------------------------------------------
-- STEP 0: CONTEXT & COST CONTROLS
-- ----------------------------------------------------------------------------
-- AUTO_SUSPEND = 60: a warehouse left running while you think is the main way
-- trial credits disappear (plan §15). We size up only for the one-off trip
-- load in STEP 5 and size back down straight after.
-- ----------------------------------------------------------------------------

USE WAREHOUSE CITIBIKE_WH;
USE DATABASE CITIBIKE_WEATHER;
USE SCHEMA RAW;

ALTER WAREHOUSE CITIBIKE_WH SET AUTO_SUSPEND = 60;


-- ----------------------------------------------------------------------------
-- STEP 1: PERMANENT FILE FORMATS
-- ----------------------------------------------------------------------------
-- Phase 0 used TMP_* formats for inspection only. These are the formats the
-- pipeline itself uses.
--
-- NULL_IF = ('') : an empty field becomes NULL. Literal text such as 'NULL'
-- is kept as text - staging decides what it means, not the loader.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FILE FORMAT FF_TRIPS_CSV
    TYPE = 'CSV'
    COMPRESSION = 'AUTO'
    FIELD_DELIMITER = ','
    RECORD_DELIMITER = '\n'
    SKIP_HEADER = 0                     -- CONFIRMED in STEP 2: files have NO header row
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('')
    EMPTY_FIELD_AS_NULL = TRUE;

CREATE OR REPLACE FILE FORMAT FF_WEATHER_JSON
    TYPE = 'JSON'
    COMPRESSION = 'AUTO'
    STRIP_OUTER_ARRAY = TRUE;           -- same setting Phase 0 counted 57,894 with

CREATE OR REPLACE FILE FORMAT FF_OPENMETEO_JSON
    TYPE = 'JSON'
    COMPRESSION = 'AUTO'
    STRIP_OUTER_ARRAY = FALSE;          -- Open-Meteo returns one JSON object per file


-- ----------------------------------------------------------------------------
-- STEP 2: DECISION GATE - TRIP FILE LAYOUT
-- ----------------------------------------------------------------------------
-- Two things must be confirmed before loading 61.5M rows:
--
--   (a) HEADER: does each file start with a header row?
--       Phase 0 assumed yes (SKIP_HEADER = 1). The Snowflake lab that
--       publishes this bucket loads it with SKIP_HEADER = 0. If the files have
--       NO header and we skip line 1, we silently lose one real ride per file.
--
--   (b) COLUMN COUNT: 15 or 16 columns?
--       The lab's table has 16 (it includes MEMBERSHIP_TYPE between BIKEID and
--       USERTYPE). Phase 0 only inspected columns 1-8.
--
-- HOW TO READ THE RESULT:
--   * Rows where $1 = 'tripduration' (text)  -> files HAVE a header.
--       Change FF_TRIPS_CSV to SKIP_HEADER = 1 and re-run STEP 1's first
--       CREATE statement.
--   * $1 is a number on row 1                -> NO header. Keep SKIP_HEADER = 0.
--   * $16 has values (e.g. 1 / 2 for gender) -> 16 columns. STEP 3 is correct.
--   * $16 is always NULL, $15 has values     -> 15 columns. STOP and adjust
--       STEP 3 (remove MEMBERSHIP_TYPE) before loading.
-- ----------------------------------------------------------------------------

SELECT
    METADATA$FILENAME        AS source_file,
    METADATA$FILE_ROW_NUMBER AS row_in_file,
    $1, $2, $3, $12, $13, $14, $15, $16, $17
FROM @CITIBIKE_LAB_STAGE (FILE_FORMAT => 'FF_TRIPS_CSV')
LIMIT 10;

-- How many files are there? (Needed for the reconciliation in STEP 8.)
LIST @CITIBIKE_LAB_STAGE;
SELECT COUNT(*) AS n_trip_files FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));


-- ----------------------------------------------------------------------------
-- STEP 3: RAW TABLES
-- ----------------------------------------------------------------------------
-- Every source column is VARCHAR. Raw tables never reject a row because of a
-- type problem - typing happens in dbt staging, where a failure is visible
-- and testable.
--
-- Every raw table also records lineage:
--   _source_file   which file the row came from
--   _source_row    which line of that file
--   _loaded_at     when it was loaded
--
-- The old trip schema has no ride_id. (_source_file, _source_row) is
-- therefore the natural key of a raw trip row.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS RAW_CITIBIKE_LAB (
    tripduration             VARCHAR,
    starttime                VARCHAR,
    stoptime                 VARCHAR,
    start_station_id         VARCHAR,
    start_station_name       VARCHAR,
    start_station_latitude   VARCHAR,
    start_station_longitude  VARCHAR,
    end_station_id           VARCHAR,
    end_station_name         VARCHAR,
    end_station_latitude     VARCHAR,
    end_station_longitude    VARCHAR,
    bikeid                   VARCHAR,
    membership_type          VARCHAR,
    usertype                 VARCHAR,
    birth_year               VARCHAR,
    gender                   VARCHAR,
    _source_file             VARCHAR,
    _source_row              NUMBER,
    _loaded_at               TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Historical Citi Bike trips (S3 lab data, 2013-2018). Loaded unchanged; all columns VARCHAR.';

CREATE TABLE IF NOT EXISTS RAW_WEATHER_JSON (
    v                        VARIANT,
    _source_file             VARCHAR,
    _source_row              NUMBER,
    _loaded_at               TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Official NYC weather feed (S3 JSON). Both city IDs and all duplicates kept.';

CREATE TABLE IF NOT EXISTS RAW_WEATHER_OPENMETEO (
    v                        VARIANT,
    _source_file             VARCHAR,
    _loaded_at               TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Open-Meteo historical archive (ERA5 model), hourly, UTC. One row per downloaded file; hourly arrays are flattened in dbt.';


-- ----------------------------------------------------------------------------
-- STEP 4: (OPTIONAL) SIZE UP FOR THE ONE-OFF TRIP LOAD
-- ----------------------------------------------------------------------------
-- A SMALL warehouse costs 2x per second but loads files in parallel ~2x
-- faster, so total credits are about the same and you wait half as long.
-- Skip this if you prefer to stay on XSMALL.
-- ----------------------------------------------------------------------------

ALTER WAREHOUSE CITIBIKE_WH SET WAREHOUSE_SIZE = 'SMALL';


-- ----------------------------------------------------------------------------
-- STEP 5: LOAD HISTORICAL TRIPS  (expect 10-30 minutes)
-- ----------------------------------------------------------------------------
-- Loads ALL years (2013-2018), not just the 2016-2018 overlap.
-- Filtering to the overlap window is a transformation, so it belongs in dbt.
--
-- Re-running is safe: Snowflake remembers which files a table has already
-- loaded and skips them, so a second run cannot double-load the data.
-- ----------------------------------------------------------------------------

COPY INTO RAW_CITIBIKE_LAB (
    tripduration, starttime, stoptime,
    start_station_id, start_station_name, start_station_latitude, start_station_longitude,
    end_station_id, end_station_name, end_station_latitude, end_station_longitude,
    bikeid, membership_type, usertype, birth_year, gender,
    _source_file, _source_row
)
FROM (
    SELECT
        $1, $2, $3,
        $4, $5, $6, $7,
        $8, $9, $10, $11,
        $12, $13, $14, $15, $16,
        METADATA$FILENAME,
        METADATA$FILE_ROW_NUMBER
    FROM @CITIBIKE_LAB_STAGE
)
FILE_FORMAT = (FORMAT_NAME = 'FF_TRIPS_CSV')
ON_ERROR = 'ABORT_STATEMENT';          -- fail loudly, never half-load silently

-- Back to the smallest size straight away.
ALTER WAREHOUSE CITIBIKE_WH SET WAREHOUSE_SIZE = 'XSMALL';


-- ----------------------------------------------------------------------------
-- STEP 6: LOAD THE OFFICIAL WEATHER JSON  (expect < 1 minute)
-- ----------------------------------------------------------------------------
-- Loaded whole into a VARIANT column. The upstate city (5128638) and the
-- exact-copy duplicates are deliberately kept here - dbt removes them, and
-- the raw table remains the evidence for why.
-- ----------------------------------------------------------------------------

COPY INTO RAW_WEATHER_JSON (v, _source_file, _source_row)
FROM (
    SELECT
        $1,
        METADATA$FILENAME,
        METADATA$FILE_ROW_NUMBER
    FROM @WEATHER_STAGE
)
FILE_FORMAT = (FORMAT_NAME = 'FF_WEATHER_JSON')
ON_ERROR = 'ABORT_STATEMENT';


-- ----------------------------------------------------------------------------
-- STEP 7: LOAD OPEN-METEO (hourly rainfall in mm)
-- ----------------------------------------------------------------------------
-- Why this source exists: the official feed has no numerical rainfall and
-- covers only 72.4% of hours (Phase 0). Open-Meteo provides every hour.
--
-- 7a. DOWNLOAD - paste this URL into a browser and save the result as
--     openmeteo_nyc_2016-07-04_2018-07-01.json
--
--   https://archive-api.open-meteo.com/v1/archive?latitude=40.714272&longitude=-74.005966&start_date=2016-07-04&end_date=2018-07-01&hourly=temperature_2m,relative_humidity_2m,precipitation,rain,snowfall,wind_speed_10m,weather_code&models=era5&timezone=GMT
--
--   Choices baked into that URL (each one is deliberate):
--     latitude/longitude  = the exact coordinates of official city 5128581,
--                           so both sources describe the same place
--     start/end dates     = one day either side of the NYC-local overlap
--                           window, because UTC runs 4-5 hours ahead
--     models=era5         = pinned model, so the download is reproducible
--     timezone=GMT        = times in UTC. Both weather sources then go through
--                           the SAME UTC -> America/New_York conversion in dbt
--
--   If the API rejects a variable name, remove that one variable and retry.
--
-- 7b. UPLOAD - in Snowsight, open CITIBIKE_WEATHER > RAW > Stages >
--     OPENMETEO_STAGE and use "+ Files" to upload the saved .json file.
--     (Run the CREATE STAGE line below first so the stage exists.)
-- ----------------------------------------------------------------------------

CREATE STAGE IF NOT EXISTS OPENMETEO_STAGE
    FILE_FORMAT = (FORMAT_NAME = 'FF_OPENMETEO_JSON')
    COMMENT = 'Internal stage for manually downloaded Open-Meteo archive files.';

-- After uploading, confirm the file is there:
LIST @OPENMETEO_STAGE;

-- 7c. LOAD
COPY INTO RAW_WEATHER_OPENMETEO (v, _source_file)
FROM (
    SELECT
        $1,
        METADATA$FILENAME
    FROM @OPENMETEO_STAGE
)
FILE_FORMAT = (FORMAT_NAME = 'FF_OPENMETEO_JSON')
ON_ERROR = 'ABORT_STATEMENT';


-- ----------------------------------------------------------------------------
-- STEP 8: RECONCILIATION - Phase 1 is done when these all match
-- ----------------------------------------------------------------------------
-- Expected values come from Phase 0.
--
-- NOTE on the trip numbers: Phase 0 counted with SKIP_HEADER = 1.
--   * If STEP 2 showed the files HAVE a header -> raw counts should equal
--     Phase 0 exactly.
--   * If STEP 2 showed NO header -> raw counts should be HIGHER than Phase 0
--     by exactly the number of files (Phase 0 dropped the first ride of each
--     file). That would be a Phase 0 correction worth writing down.
-- ----------------------------------------------------------------------------

-- 8a. Trips
SELECT
    COUNT(*)                                       AS raw_rows,                -- expect 61,467,983 (see note)
    COUNT(DISTINCT _source_file)                   AS files_loaded,            -- expect = n_trip_files from STEP 2
    COUNT_IF(TRY_TO_TIMESTAMP(starttime) >= '2016-07-05'
         AND TRY_TO_TIMESTAMP(starttime) <  '2018-07-01')
                                                   AS overlap_rows,            -- expect 32,012,387 (see note)
    COUNT_IF(TRY_TO_TIMESTAMP(starttime) IS NULL)  AS unparseable_starttime,   -- expect 0
    MIN(TRY_TO_TIMESTAMP(starttime))               AS earliest,                -- expect 2013-06-01 00:00:08
    MAX(TRY_TO_TIMESTAMP(starttime))               AS latest,                  -- expect 2018-06-30 23:59:54
    COUNT_IF(gender IS NULL)                       AS null_gender              -- near 0 if the 16-column layout is right
FROM RAW_CITIBIKE_LAB;

-- 8b. Official weather
SELECT
    COUNT(*)                                       AS raw_rows,                -- expect 57,894
    COUNT(DISTINCT v:time::INT)                    AS unique_timestamps,       -- expect 40,327
    COUNT_IF(v:city.id::INT = 5128581)             AS nyc_rows,                -- expect 28,962
    COUNT_IF(v:city.id::INT = 5128638)             AS upstate_rows             -- expect 28,932
FROM RAW_WEATHER_JSON;

-- 8c. Open-Meteo
SELECT
    _source_file,
    v:latitude::FLOAT                              AS grid_lat,               -- snapped to the model grid, near 40.7
    v:longitude::FLOAT                             AS grid_lon,               -- near -74.0
    v:timezone::STRING                             AS tz,                     -- expect GMT
    ARRAY_SIZE(v:hourly.time)                      AS hours,                  -- expect 17,472 (728 days x 24)
    v:hourly.time[0]::STRING                       AS first_hour_utc,         -- expect 2016-07-04T00:00
    v:hourly_units                                 AS units                   -- precipitation should be mm
FROM RAW_WEATHER_OPENMETEO;

-- 8d. Open-Meteo has no missing rainfall values
SELECT
    COUNT(*)                                       AS hours,
    COUNT_IF(p.value IS NULL OR IS_NULL_VALUE(p.value)) AS missing_precip     -- expect 0
FROM RAW_WEATHER_OPENMETEO,
     LATERAL FLATTEN(input => v:hourly.precipitation) p;


-- ============================================================================
-- PHASE 1 COMPLETE when:
--   [ ] STEP 2 header + column-count decision recorded
--   [ ] 8a trip rows reconcile with Phase 0 (allowing for the header note)
--   [ ] 8b weather rows = 57,894 with both city IDs present
--   [ ] 8c Open-Meteo = 17,472 hours, timezone GMT
--   [ ] 8d zero missing precipitation values
--   [ ] Warehouse back on XSMALL
--   [ ] This file committed to Git
--
-- Next: Phase 2 - dbt sources, staging models and contracts.
-- ============================================================================
