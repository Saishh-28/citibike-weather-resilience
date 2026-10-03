-- ============================================================================
-- CITIBIKE & WEATHER DATA ENGINEERING PIPELINE
-- PHASE 2 SETUP: A DEDICATED ROLE AND USER FOR dbt
-- ============================================================================
-- Why: dbt should not run as ACCOUNTADMIN. It gets exactly what it needs:
--   * READ the raw tables
--   * CREATE its own schemas (staging / intermediate / marts) in the database
--   * USE the one small warehouse
-- That is "least privilege" - a good answer if asked about security.
--
-- Why a SERVICE user with a key pair: Snowflake requires multi-factor sign-in
-- for normal (human) password users, which an automated tool like dbt Cloud
-- cannot complete. A service user authenticates with a key pair instead.
--
-- Run as ACCOUNTADMIN, top to bottom. Paste YOUR public key in STEP 3.
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- STEP 1: the role -----------------------------------------------------------
CREATE ROLE IF NOT EXISTS TRANSFORMER
    COMMENT = 'dbt transformation role: read RAW, build staging/intermediate/marts';

GRANT ROLE TRANSFORMER TO ROLE SYSADMIN;      -- keeps the role hierarchy tidy

-- STEP 2: what the role may do -----------------------------------------------
GRANT USAGE ON WAREHOUSE CITIBIKE_WH TO ROLE TRANSFORMER;

GRANT USAGE, CREATE SCHEMA ON DATABASE CITIBIKE_WEATHER TO ROLE TRANSFORMER;

GRANT USAGE ON SCHEMA CITIBIKE_WEATHER.RAW TO ROLE TRANSFORMER;
GRANT SELECT ON ALL TABLES    IN SCHEMA CITIBIKE_WEATHER.RAW TO ROLE TRANSFORMER;
GRANT SELECT ON FUTURE TABLES IN SCHEMA CITIBIKE_WEATHER.RAW TO ROLE TRANSFORMER;

-- STEP 3: the user ------------------------------------------------------------
-- Replace the placeholder with the CONTENTS of rsa_key.pub, without the
-- "-----BEGIN PUBLIC KEY-----" / "-----END PUBLIC KEY-----" lines, as one line.
CREATE USER IF NOT EXISTS DBT_USER
    TYPE = SERVICE
    DEFAULT_ROLE = TRANSFORMER
    DEFAULT_WAREHOUSE = CITIBIKE_WH
    RSA_PUBLIC_KEY = 'PASTE_PUBLIC_KEY_HERE'
    COMMENT = 'Service user for dbt Cloud';

GRANT ROLE TRANSFORMER TO USER DBT_USER;

-- STEP 4: check ------------------------------------------------------------------
DESC USER DBT_USER;                 -- RSA_PUBLIC_KEY_FP should be filled in
SHOW GRANTS TO ROLE TRANSFORMER;    -- warehouse, database, RAW schema, RAW tables

-- The account identifier dbt Cloud asks for:
SELECT CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME() AS account_identifier;
