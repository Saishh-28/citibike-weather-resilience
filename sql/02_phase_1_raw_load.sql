-- ============================================================================
-- CITIBIKE & WEATHER DATA ENGINEERING PIPELINE
-- PHASE 1: RAW LANDING (the "L" in ELT)
-- Snowflake / AWS S3 / Open-Meteo
-- ============================================================================
-- Purpose:
--   Copy every source into Snowflake exactly as it arrives. No filtering,
--   no deduplication, no type conversion, no timezone conversion.
--   All Phase 0 decisions (NYC-only city, dedup, UTC -> New York,
--   extreme-duration flags, short-gap fill) are applied later in dbt.
--
-- Why load everything unchanged:
--   If a transformation decision turns out to be wrong, one dbt model is
--   fixed and re-run. The source never has to be re-extracted.
--
-- Author: Saisha
-- ============================================================================


-- ----------------------------------------------------------------------------
-- STEP 0: CONTEXT & COST CONTROLS
-- ----------------------------------------------------------------------------
-- AUTO_SUSPEND = 60: an idle warehouse stops after one minute, so no credits
-- are spent while nothing is running. The warehouse is sized up only for the
-- one-off trip load (STEP 4) and sized back down straight after.
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
    SKIP_HEADER = 0                     -- files have NO header row (see STEP 2)
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('')
    EMPTY_FIELD_AS_NULL = TRUE;

CREATE OR REPLACE FILE FORMAT FF_WEATHER_JSON
    TYPE = 'JSON'
    COMPRESSION = 'AUTO'
    STRIP_OUTER_ARRAY = TRUE;           -- same setting Phase 0 counted 57,894 rows with

CREATE OR REPLACE FILE FORMAT FF_OPENMETEO_JSON
    TYPE = 'JSON'
    COMPRESSION = 'AUTO'
    STRIP_OUTER_ARRAY = FALSE;          -- Open-Meteo returns one JSON object per file


-- ----------------------------------------------------------------------------
-- STEP 2: TRIP FILE LAYOUT CHECK
-- ----------------------------------------------------------------------------
-- Two things were confirmed before loading 61.5M rows:
--
--   (a) HEADER: the files have NO header row. Row 1 of each file is a real
--       ride ($1 is a number, not the text 'tripduration'). Phase 0 had used
--       SKIP_HEADER = 1, which silently dropped the first ride of every file.
--
--   (b) COLUMN COUNT: 16 columns. $16 holds gender codes, so the layout
--       includes MEMBERSHIP_TYPE between BIKEID and USERTYPE.
-- ----------------------------------------------------------------------------

SELECT
    METADATA$FILENAME        AS source_file,
    METADATA$FILE_ROW_NUMBER AS row_in_file,
    $1, $2, $3, $12, $13, $14, $15, $16, $17
FROM @CITIBIKE_LAB_STAGE (FILE_FORMAT => 'FF_TRIPS_CSV')
LIMIT 10;

-- Number of trip files (used in the STEP 8 reconciliation).
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
-- The old trip schema has no ride_id, so (_source_file, _source_row) is the
-- natural key of a raw trip row.
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
-- STEP 4: SIZE UP FOR THE ONE-OFF TRIP LOAD
-- ----------------------------------------------------------------------------
-- A SMALL warehouse costs 2x per second but loads files in parallel about 2x
-- faster, so total credits are about the same and the load finishes sooner.
-- ----------------------------------------------------------------------------

ALTER WAREHOUSE CITIBIKE_WH SET WAREHOUSE_SIZE = 'SMALL';


-- ----------------------------------------------------------------------------
-- STEP 5: LOAD HISTORICAL TRIPS
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
-- STEP 6: LOAD THE OFFICIAL WEATHER JSON
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
-- Source file openmeteo_nyc_2016-07-04_2018-07-01.json was downloaded from:
--
--   https://archive-api.open-meteo.com/v1/archive?latitude=40.714272&longitude=-74.005966&start_date=2016-07-04&end_date=2018-07-01&hourly=temperature_2m,relative_humidity_2m,precipitation,rain,snowfall,wind_speed_10m,weather_code&models=era5&timezone=GMT
--
-- Choices in that URL:
--   latitude/longitude  = the exact coordinates of official city 5128581,
--                         so both sources describe the same place
--   start/end dates     = one day either side of the NYC-local overlap
--                         window, because UTC runs 4-5 hours ahead
--   models=era5         = pinned model, so the download is reproducible
--   timezone=GMT        = times in UTC; both weather sources then go through
--                         the same UTC -> America/New_York conversion in dbt
--
-- The file was uploaded to the internal stage below through Snowsight.
-- ----------------------------------------------------------------------------

CREATE STAGE IF NOT EXISTS OPENMETEO_STAGE
    FILE_FORMAT = (FORMAT_NAME = 'FF_OPENMETEO_JSON')
    COMMENT = 'Internal stage for manually downloaded Open-Meteo archive files.';

LIST @OPENMETEO_STAGE;

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
-- STEP 8: RECONCILIATION
-- ----------------------------------------------------------------------------
-- Raw row counts compared with Phase 0. Expected values are noted per column.
--
-- Trips: Phase 0 counted with SKIP_HEADER = 1, which skipped the first ride
-- of every file. The raw table is therefore higher than Phase 0 by exactly
-- one row per file (61,468,359 vs 61,467,983).
-- ----------------------------------------------------------------------------

-- 8a. Trips
SELECT
    COUNT(*)                                       AS raw_rows,                -- 61,468,359
    COUNT(DISTINCT _source_file)                   AS files_loaded,            -- = n_trip_files from STEP 2
    COUNT_IF(TRY_TO_TIMESTAMP(starttime) >= '2016-07-05'
         AND TRY_TO_TIMESTAMP(starttime) <  '2018-07-01')
                                                   AS overlap_rows,            -- 32,012,552
    COUNT_IF(TRY_TO_TIMESTAMP(starttime) IS NULL)  AS unparseable_starttime,   -- 0
    MIN(TRY_TO_TIMESTAMP(starttime))               AS earliest,                -- 2013-06-01 00:00:08
    MAX(TRY_TO_TIMESTAMP(starttime))               AS latest,                  -- 2018-06-30 23:59:54
    COUNT_IF(gender IS NULL)                       AS null_gender              -- near 0 if the 16-column layout is right
FROM RAW_CITIBIKE_LAB;

-- 8b. Official weather
SELECT
    COUNT(*)                                       AS raw_rows,                -- 57,894
    COUNT(DISTINCT v:time::INT)                    AS unique_timestamps,       -- 40,327
    COUNT_IF(v:city.id::INT = 5128581)             AS nyc_rows,                -- 28,962
    COUNT_IF(v:city.id::INT = 5128638)             AS upstate_rows             -- 28,932
FROM RAW_WEATHER_JSON;

-- 8c. Open-Meteo
SELECT
    _source_file,
    v:latitude::FLOAT                              AS grid_lat,               -- snapped to the model grid, near 40.7
    v:longitude::FLOAT                             AS grid_lon,               -- near -74.0
    v:timezone::STRING                             AS tz,                     -- GMT
    ARRAY_SIZE(v:hourly.time)                      AS hours,                  -- 17,472 (728 days x 24)
    v:hourly.time[0]::STRING                       AS first_hour_utc,         -- 2016-07-04T00:00
    v:hourly_units                                 AS units                   -- precipitation in mm
FROM RAW_WEATHER_OPENMETEO;

-- 8d. Open-Meteo has no missing rainfall values
SELECT
    COUNT(*)                                       AS hours,
    COUNT_IF(p.value IS NULL OR IS_NULL_VALUE(p.value)) AS missing_precip     -- 0
FROM RAW_WEATHER_OPENMETEO,
     LATERAL FLATTEN(input => v:hourly.precipitation) p;
