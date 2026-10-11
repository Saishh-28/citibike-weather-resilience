# CitiBike × NYC Weather — Data Engineering Case Study

**Question (from the brief):** *How does a rainy or snowy day affect user behaviour compared to a clear, sunny day?*

**Short answer** (5 Jul 2016 – 30 Jun 2018, 32,012,552 trips, compared with dry days of the same month):

| | Riders vs a dry day | Members | Casual riders |
|---|---|---|---|
| Drizzle (< 1 mm) | −0.4% | ≈0 | ≈0 |
| Rainy day (≥ 1 mm) | **−18.2%** | −16.4% | −27.3% |
| Snowy day (≥ 1 cm) | **−48.7%** | −47.7% | −68.2% |

- The first measurable rain in an hour (0.1–0.5 mm) already costs about 25% of riders; heavier rain levels off around −55%.
- Commute hours lose about twice as many trips per hour as weekends; weekends drop further in heavy rain.
- Daily rain vs riders (season removed): r = −0.53. All results are associations, not causes.
- A forecasting test (Snowflake ML.FORECAST) cut its error by 40% when weather was added (May–June 2018, best case: actual weather used).

---

## Architecture

```
S3 (trip CSVs, weather JSON) ─┐
Open-Meteo archive (JSON) ────┴─► Snowflake RAW ─► dbt staging ─► dbt intermediate ─► dbt marts ─► Power BI
                                  (as loaded)      (typed, UTC,    (one row per hour)  (fact, date,   (4 pages,
                                                    deduplicated)                       daily, rain,   Import mode)
                                                                                        anomalies)
```

| Layer | Models | Materialised |
|---|---|---|
| Staging | `stg_citibike_lab`, `stg_weather_json`, `stg_weather_openmeteo` | views |
| Intermediate | `int_trips_hourly`, `int_weather_hourly` | tables |
| Marts | `fct_hourly_demand`, `dim_date`, `agg_daily_weather_demand`, `fct_hourly_expected_demand`, `agg_rain_response`, `fct_hourly_anomalies` | tables |

- **Grain:** one row per UTC hour (17,424 hours), built on a generated spine so clock changes never create missing or doubled hours. Trips and weather are LEFT-joined; an hour with no trips still exists.
- **Settings in one place:** analysis window, city ID, gap-fill cap, closure threshold and day-type thresholds are dbt variables in `dbt_project.yml`.
- **Weather sources:** the supplied feed has no rainfall amounts and goes missing more in snow (24% of snow hours vs 17% of dry hours), so hourly rain and snow come from Open-Meteo (ERA5, ~25 km cell over Midtown). This is disclosed everywhere it is used.

## Tests

Run on every `dbt build`: unique / not-null keys on every model; every hour present (17,424); trip total reconciles to staging (32,012,552); member + casual + unknown = total; every date exists in `dim_date`; hottest hour is in the afternoon (timezone proof); trips ending before they start only on clock-change nights; staging contract enforced on the trip model.

## Repository

| Path | What it is |
|---|---|
| `sql/` | Phase 0 diagnostics and Phase 1 raw load (run in a Snowflake worksheet) |
| `dbt/models/` | staging, intermediate, marts + YAML docs and tests |
| `dbt/tests/`, `dbt/seeds/` | custom tests; US federal holidays seed |
| `dbt/analyses/` | Phase 3 verification queries; Phase 5 forecasting test |
| `powerbi/citibike_weather.pbix` | dashboard (4 pages) |
| `docs/CitiBike_Final_Reference.docx` | full reference: findings F1–F22, decisions D1–D35, assumptions, errors caught |

## How to run

1. **Snowflake:** run `sql/02_phase_1_raw_load.sql` to create the stages and load the RAW tables (upload the Open-Meteo JSON to `OPENMETEO_STAGE` first).
2. **dbt Cloud:** connect to Snowflake with the `DBT_USER` service user (key pair, role `TRANSFORMER`), then `dbt seed` and `dbt build`.
3. **Docs:** `dbt docs generate`, then open the docs to see descriptions and the lineage graph.
4. **Power BI:** open the .pbix. It uses Import mode, so it works offline; Refresh needs a Snowflake login with read access to the marts schema.

## Security

- dbt runs as a dedicated service user with key-pair authentication and a least-privilege role (`TRANSFORMER`).
- The private key lives outside this repository and has never been committed.
- Raw data, development schemas and the forecasting sandbox (`ML_SANDBOX`) are separate schemas.
- Next: a resource monitor to cap credit spend; keep birth year and gender out of the marts.

## Assumptions and limits

- A fully dry day (0.0 mm) stands in for "clear, sunny": neither source measures sunshine.
- One weather grid cell represents the whole network.
- 131 hours with zero trips (three snowstorms) are flagged as closures and left out of the weather comparison.
- Holidays are excluded from "normal"; the anomaly model finds them on its own.
- The expected-demand baseline explains the past (it uses weeks either side of each day); it is not a forecast.

## How AI was used

I used an AI assistant (Claude) as a pair programmer. It drafted most of the SQL and much of the documentation. I made the design decisions, predicted the result of each step before running it, and checked every output against that expected number. That is how these errors were caught:

- The gap fill first filled 21.5% of hours; I had predicted about 12%. It was filling the start of every gap, not only short ones. Fixed: 11.4%.
- The row count was 134 hours short of 17,424, which led to the three snowstorm closures.
- The first expected-demand baseline was 6% too low on dry days (should be ≈0%); the window was centred to fix it.
- A Power BI data-type change shifted daily totals by 1–3 trips; caught by comparing with Snowflake.
- The first forecasting test (six months ahead from 18 months of history) failed; a month-by-month check showed why, and the test was redesigned.
- One fix came from the AI's review rather than from me: filtering the weather feed by city name would have returned the wrong station, because both are called "New York".

## Next steps

Rain duration, temperature relative to the season and snow on the ground in the model; a scheduled dbt Cloud job with tests on every pull request; incremental models; station-level grain; the 2026 file format in staging; checking whether the rain effect still holds in 2026.
