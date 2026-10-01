# Architecture

## 1. Overview

The CitiBike Weather Resilience Engine is designed as an ELT pipeline using Snowflake, dbt Cloud and Power BI.

The overall flow is:

Raw CitiBike data + NYC weather data
        ↓
    Snowflake
        ↓
   dbt staging
        ↓
 dbt transformations
        ↓
 Data quality tests
        ↓
 Analytical models
        ↓
    Power BI
        ↓
 Business insights

The architecture is designed to support repeatable analysis as new data becomes available rather than requiring the entire process to be manually rebuilt.

---

## 2. Data Sources

### CitiBike

Source:
`s3://snowflake-workshop-lab/japan/citibike-trips/`

Purpose:
Provide CitiBike trip-level data for analysing demand and rider behaviour.

### NYC Weather

Source:
`s3://snowflake-workshop-lab/weather-nyc`

Purpose:
Provide weather observations that can be aligned with CitiBike demand.

The exact fields, grain and date coverage will be confirmed during data exploration.

---

## 3. Snowflake

Snowflake will act as the central data warehouse.

The initial raw layer will contain:

- `RAW_CITIBIKE`
- `RAW_WEATHER`

The raw layer should preserve the source data as much as practical before transformation.

---

## 4. dbt

dbt will handle transformation, modelling, testing and documentation.

### Staging

- `stg_citibike`
- `stg_weather`

These models will clean and standardise the raw data.

### Intermediate

Potential models:

- `int_hourly_demand`
- `int_expected_demand`
- `int_weather_impact`
- `int_weather_thresholds`
- `int_demand_anomalies`

The exact models and grain will be finalised after inspecting the data.

### Final analytical model

- `fct_weather_resilience`

This will provide the business-facing dataset used for analysis and Power BI.

---

## 5. Analytical Layer

The analytical layer will investigate:

1. Expected CitiBike demand
2. Weather-associated demand deviation
3. Weather behavioural thresholds
4. Demand anomalies
5. Whether weather provides additional predictive value

ML will only be introduced if the data and analysis justify it.

---

## 6. Power BI

Power BI will act as the presentation and decision-support layer.

The dashboard will communicate:

- actual vs expected demand
- weather conditions
- weather-demand relationships
- potential behavioural thresholds
- unusual demand observations
- relevant model/pipeline status

The exact dashboard structure will depend on the findings from the data.

---

## 7. Data Quality

The pipeline will include checks for issues such as:

- missing required fields
- duplicate records
- uniqueness where expected
- invalid relationships
- data freshness
- unexpected data-quality changes

Failed checks should prevent unreliable results from silently reaching the analytical layer where possible.

---

## 8. Future / Production Flow

The intended ongoing flow is:

New data
→ ingestion
→ transformation
→ testing
→ analytical models
→ dashboard refresh

The goal is to make the system maintainable rather than treating the case study as a one-time analysis.

---

## 9. Architecture Decisions

Architecture decisions will be documented here as the implementation develops.

Examples include:

- chosen data grain
- CitiBike/weather join strategy
- incremental vs full transformation approach
- model structure
- testing strategy
- refresh strategy
