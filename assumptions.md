# Assumptions

This document records assumptions and decisions made during the CitiBike Weather Resilience Engine case study.

Assumptions will be updated as the actual datasets are explored.

---

## 1. Data Assumptions

### 1.1 CitiBike data

The CitiBike dataset is assumed to represent individual trip records or another defined trip-level grain.

The exact grain will be confirmed during data exploration.

### 1.2 Weather data

The weather dataset is assumed to contain observations that can be aligned with CitiBike demand.

The available variables and time granularity will be confirmed before deciding which weather features to use.

### 1.3 Date coverage

The overlapping date range between CitiBike and weather data will determine the period available for analysis.

I will not assume that both datasets cover exactly the same period until this has been verified.

---

## 2. Data Alignment Assumptions

CitiBike demand and weather observations need to be aligned using an appropriate time grain.

The final grain will depend on:

- CitiBike timestamp granularity
- weather observation frequency
- availability of weather observations
- the amount of missing data

I will avoid forcing a join until the actual data has been inspected.

---

## 3. Expected Demand Assumptions

Expected demand should represent what would normally be expected given relevant temporal patterns.

Potential factors include:

- hour of day
- day of week
- season/month
- historical demand

The final baseline features will be determined after exploratory analysis.

---

## 4. Weather Impact Assumptions

The analysis will measure relationships between weather conditions and demand.

Because the data is observational, a relationship between weather and demand will not automatically be interpreted as proof of causation.

Where appropriate, results will be described as weather-associated differences or deviations from expected demand.

---

## 5. Threshold Assumptions

I will not assume a specific temperature, rainfall level or other weather threshold before analysing the data.

Potential break points should be supported by the observed data.

---

## 6. ML Assumptions

ML will not be included purely for complexity.

If used, the purpose will be to test whether weather provides additional predictive information beyond temporal demand patterns.

A baseline model and weather-informed model can be compared using unseen/future data.

If ML does not provide meaningful additional value, the project can remain based on simpler analytical methods.

---

## 7. Business Assumptions

The available datasets do not automatically provide information about:

- revenue
- pricing
- operating costs
- bike availability
- station capacity
- external events
- public transport disruptions

I will not make claims requiring these variables unless the data provides them or an external source is explicitly introduced.

---

## 8. Causality

The analysis is primarily observational.

Therefore, statements such as:

"Rain caused exactly X fewer trips"

will not be made unless the methodology supports a causal interpretation.

Instead, the analysis will focus on observed relationships and deviations from expected demand.

---

## 9. Limitations

Limitations identified during data exploration and modelling will be documented here.

Examples may include:

- missing weather observations
- incomplete date coverage
- differences in data granularity
- unavailable operational variables
- potential confounding factors
- limitations of the expected-demand model
