-- ============================================================================
-- CITIBIKE & WEATHER DATA ENGINEERING PIPELINE
-- PHASE 2 SETUP: A DEDICATED ROLE AND USER FOR dbt
-- ============================================================================
-- Least privilege: dbt does not run as ACCOUNTADMIN. Its role can only
--   * READ the raw tables
--   * CREATE its own schemas (staging / intermediate / marts) in the database
--   * USE the one small warehouse
--
-- Service user with a key pair: Snowflake requires multi-factor sign-in for
-- human password users, which an automated tool like dbt Cloud cannot
-- complete. A SERVICE user authenticates with a key pair instead.
-- The public key is redacted below; the private key is never stored in git.
--
-- Runs as ACCOUNTADMIN.
-- Author: Saisha
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
GRANT SELECT ON FUTURE TABLES IN SCHEMA CITIBIKE_WEATHER.RAW TO ROLE TRANSFORMER;   -- new raw tables are readable automatically

-- STEP 3: the service user ---------------------------------------------------
-- RSA_PUBLIC_KEY takes the body of rsa_key.pub as one line, without the
-- BEGIN/END PUBLIC KEY lines.
CREATE USER IF NOT EXISTS DBT_USER
    TYPE = SERVICE
    DEFAULT_ROLE = TRANSFORMER
    DEFAULT_WAREHOUSE = CITIBIKE_WH
    RSA_PUBLIC_KEY = '<public key redacted>'
    COMMENT = 'Service user for dbt Cloud';

GRANT ROLE TRANSFORMER TO USER DBT_USER;

-- STEP 4: verification -------------------------------------------------------
DESC USER DBT_USER;                 -- RSA_PUBLIC_KEY_FP is filled in
SHOW GRANTS TO ROLE TRANSFORMER;    -- warehouse, database, RAW schema, RAW tables

-- Account identifier used in the dbt Cloud connection:
SELECT CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME() AS account_identifier;
