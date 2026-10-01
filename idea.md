# CitiBike Weather Resilience Engine

### Dataengine Technical Case Study

### Analysing the Impact of Weather on CitiBike Usage in NYC

---

## 1. The case study I'm solving

The obvious question is:

> “How does weather affect CitiBike usage?”

The Dataengine brief asks me to explore CitiBike trip data and NYC weather data, define the right questions myself, build an ELT pipeline using Snowflake and dbt Cloud, and deliver the resulting insights through Power BI. I also need to explain my assumptions, architecture and reasoning as if I were working with a client.

So I don't want to just make a dashboard that says:

> Rain ↑ → Trips ↓

I want to turn the problem into a small weather-demand intelligence system.

---

## 2. My central idea

### CitiBike Weather Resilience Engine

The big question I want to answer is:

> **How can CitiBike understand, anticipate and continuously monitor how weather changes trip demand?**

I'm approaching the solution from two sides.

### A. The analytical side

I want to investigate:

1. What would normal CitiBike demand look like?
2. How does weather change that expectation?
3. At what weather conditions does rider behaviour change meaningfully?
4. When does actual demand behave unexpectedly?
5. Does weather actually improve my ability to anticipate demand?

### B. The engineering side

I don't want the analysis to be something that I build once and then have to manually recreate every time new data arrives.

Conceptually, I want the pipeline to look like:

**New CitiBike/weather data
→ Snowflake
→ dbt transformations
→ data-quality tests
→ weather-demand models
→ Power BI
→ updated insights**

The point is to think beyond a one-off analysis and consider how this could operate as an ongoing data product.

---

## 3. The problem I'm really trying to solve

A simple analysis could tell CitiBike:

> “Trips decrease when it rains.”

That's useful, but it's quite limited.

What I actually want to ask is:

> **“Given what normally happens at this time of year, on this day of the week and at this time of day, how much does weather change expected demand?”**

That lets me move from a simple correlation to something more useful:

### Expected demand vs Actual demand

For example:

**Expected:** 20,000 trips
**Actual:** 15,500 trips
**Weather:** unusually rainy

I can then investigate whether that difference is consistent with the historical relationship between weather and demand.

I would describe this as a **modelled weather-associated deviation**, rather than automatically claiming that weather caused exactly 4,500 “lost” rides.

That distinction matters because this is observational data.

---

## 4. Analytical Question #1 — What is normal demand?

Before I can say that weather changed demand, I need some idea of what demand normally looks like.

I'll investigate patterns such as:

* hour of day
* day of week
* season/month
* historical demand

The exact features will depend on what is actually present in the supplied datasets.

The purpose is to establish an expected-demand baseline.

Conceptually:

> **Expected demand = what I would normally expect given the temporal context**

Then I can compare that expectation with what actually happened.

---

## 5. Analytical Question #2 — How does weather change demand?

Once I have the baseline, I'll introduce the weather data.

I don't want to assume that particular weather fields exist before I've explored the dataset.

Potential examples could include:

* temperature
* precipitation
* snow
* wind
* weather condition

The actual available fields will be confirmed during data exploration.

The key question becomes:

> **How different is actual demand under different weather conditions from what I would normally expect?**

I can then communicate this through Power BI using things like:

* actual vs expected demand
* weather-condition comparisons
* demand deviation over time
* weather-response curves

---

## 6. Analytical Question #3 — Are there weather “break points”?

I don't want to assume that weather affects demand linearly.

Maybe:

**small amount of rain →** almost no change

**moderate rain →** noticeable decline

**heavy rain →** major behavioural change

Or maybe the data shows something completely different.

So I want to investigate:

> **Are there weather conditions where demand changes disproportionately?**

These would become potential behavioural thresholds or break points.

I don't want to decide beforehand that the threshold is “X mm of rain” or “Y degrees.”

The data needs to demonstrate that.

Possible approaches could include:

* binned comparisons
* response curves
* segmented/piecewise analysis
* interaction analysis

I'll start with methods that are easy to interpret rather than immediately reaching for complex ML.

---

## 7. Analytical Question #4 — What happens when reality doesn't match expectations?

Once I have an expected-demand baseline, I can identify unusual observations.

For example:

**Expected demand:** high
**Weather:** poor
**Actual demand:** surprisingly high

Or:

**Expected demand:** moderate
**Weather:** reasonable
**Actual demand:** surprisingly low

These become weather-adjusted demand anomalies.

The important distinction for me is:

> An anomaly tells me **WHAT** is unusual.

It doesn't automatically tell me **WHY**.

If I don't have event, transit, outage or other external data, I shouldn't invent explanations.

Instead, the dashboard can say:

> “This observation is unusual relative to the model.”

That keeps the analysis disciplined.

---

## 8. Optional Analytical Question #5 — Does weather actually improve prediction?

This is where I think ML could genuinely be useful.

I don't want to use ML just so I can say that I used ML.

Instead, I want to test whether weather actually provides meaningful additional predictive information.

I could compare two models.

### Model A — Baseline

Uses temporal information such as:

* hour
* day of week
* season/time period
* historical demand

### Model B — Weather-informed

Uses the baseline information **plus relevant weather features**.

Then I can evaluate both models on unseen/future data.

The question becomes:

> **Does adding weather actually improve my ability to anticipate CitiBike demand?**

If it does, then weather adds useful predictive information.

If it doesn't, that is still a valid result. It could mean that most demand variation is already explained by temporal patterns, with weather only becoming useful under particular conditions.

I'm testing a hypothesis rather than designing the project around a predetermined conclusion.

---

## 9. The production aspect — making this more than a one-off project

This is a really important part of my solution.

I don't want the finished system to require someone to manually run everything whenever new data appears.

My conceptual production flow is:

### Step 1 — New data arrives

New CitiBike trip data and weather data become available.

### Step 2 — Snowflake ingests the data

The raw data enters the warehouse.

### Step 3 — dbt transforms it

dbt handles the repeatable transformation and modelling logic.

### Step 4 — Tests run

I check that the data still behaves as expected.

For example:

* required fields aren't unexpectedly missing
* keys remain unique where expected
* relationships remain valid
* data is fresh
* unexpected schema/data-quality issues are detected

### Step 5 — Analytical models update

Expected demand, weather effects, thresholds and anomalies are recalculated.

### Step 6 — Power BI refreshes

The dashboard exposes the newest trusted results.

So the overall system becomes:

> **Ingest → Transform → Test → Analyse → Refresh**

rather than:

> **Manually download → manually run → manually update dashboard**

This is important because I want to show that I'm thinking about what happens after the initial analysis.

---

## 10. What happens if the pipeline breaks?

Automation isn't enough by itself.

For example, imagine tomorrow's weather file is malformed.

I don't want the system to quietly produce nonsense.

Instead, I'd want something like:

**New data**

↓

**Validation / tests**

↓

**PASS → continue through the pipeline**

**FAIL → stop/quarantine the problematic data and surface an alert**

The principle I'm working with is:

> **Automate the normal path, detect the abnormal path.**

I don't need to build some enormous monitoring platform for this case study.

I just want to demonstrate that I've thought about what happens after deployment.

---

## 11. My Snowflake → dbt → Power BI architecture

The exact table names will be finalised after I inspect the actual data.

Conceptually, I currently see it as:

### Snowflake

**RAW_CITIBIKE**

Raw CitiBike source data.

**RAW_WEATHER**

Raw NYC weather source data.

### dbt

**stg_citibike**
Cleaned/standardised trip data.

**stg_weather**
Cleaned/structured weather data.

**int_hourly_demand**
Trip volume aggregated at the appropriate time grain.

**int_expected_demand**
Expected-demand baseline.

**int_weather_impact**
Weather-associated differences and relevant weather features.

**int_weather_thresholds**
Potential behavioural break points.

**int_demand_anomalies**
Unexpected demand observations.

**fct_weather_resilience**
The final analytical/business-facing model combining the important outputs.

These names are just my current conceptual structure. I won't pretend they're final until I inspect the actual schemas and decide the correct grain.

---

## 12. Power BI — what the dashboard is actually for

Power BI isn't the project.

It's the storytelling and decision layer.

I want the dashboard to answer different questions rather than just display charts.

### Page 1 — What is happening?

* actual demand
* expected demand
* weather conditions
* demand deviation over time

### Page 2 — How does weather affect behaviour?

* temperature response
* precipitation response
* weather-condition comparisons
* potential thresholds
* time/season interactions

### Page 3 — What is unusual?

* expected vs actual demand
* unusual observations
* weather context
* anomaly exploration

### Page 4 — Can the system be trusted?

Potentially:

* latest data timestamp
* pipeline status
* test status
* model refresh information

The exact number of pages will depend on how much useful information the actual data produces.

---

## 13. What I'm NOT doing

I want to be quite deliberate about what I don't build.

### A chatbot

It would add an interface, but not necessarily useful analytical value.

### A giant neural network

There's no reason to use one simply because it sounds advanced.

### Random Forest/XGBoost just for the sake of saying “ML”

I'll only use a more complex model if it answers a question that simpler methods can't answer adequately.

### Fake revenue calculations

The case study gives me CitiBike trips and NYC weather. It doesn't say that I have revenue or pricing data.

I'm not going to invent financial conclusions and present them as facts.

### Exact fleet-rebalancing instructions

I shouldn't claim:

> “Move 37 bikes from Station A to Station B”

unless the available data actually supports that conclusion.

I can discuss potential operational implications, but I need to distinguish those from what the data actually demonstrates.

### Causal claims

I want to avoid saying:

> “Weather caused exactly X fewer trips.”

unless the methodology genuinely supports a causal claim.

Instead, I can say:

> “Demand was X below the modelled expectation under these weather conditions.”

That's much more defensible.

---

## 14. Where the creativity actually comes from

The creativity isn't:

> “I used AI.”

It isn't:

> “I used 17 different ML algorithms.”

And it isn't:

> “Look at my complicated architecture.”

The creativity is in the question and the system design.

Most people could produce:

> Rainy days → fewer trips.

I want to ask:

> What should demand have been?

> How far did reality deviate from that expectation?

> At what weather conditions does behaviour change?

> Which observations break the expected pattern?

> Does weather actually improve prediction?

> Can the analysis continuously update when new data arrives?

> How do I know the automated pipeline is still producing trustworthy results?

That's the difference between a chart and a system.

---

## 15. What I want Alex to see

When Alex looks at the project, I want the solution to communicate:

> **“I didn't just analyse the historical data. I thought about how this could become a maintainable analytics system.”**

The technical stack demonstrates:

**Snowflake →** data platform

**dbt →** transformation, modelling, testing and documentation

**Power BI →** insight delivery

The analytical layer demonstrates:

**Expected demand
→ weather impact
→ behavioural thresholds
→ anomalies
→ optional predictive modelling**

And the production layer demonstrates:

**New data
→ automated pipeline
→ quality checks
→ updated models
→ updated dashboard**

---

## 16. My guiding principle

I'm **not** trying to make the most complicated project possible.

I'm trying to make the most defensible project possible.

For every feature, I want to be able to answer:

> **“Why does this exist?”**

If I can't answer that, I don't build it.

If a simple SQL model answers a question better than an ML model, I'll use SQL.

If the data doesn't support a proposed insight, I'll drop the insight.

If the result contradicts my hypothesis, I'll report the contradiction.

If an assumption is necessary, I'll state it.

If something cannot be inferred from the data, I'll say so.

That's how I want to keep the project technically credible.

---

## 17. The one-sentence version

If Alex asks:

> “So, what did you actually build?”

I'd say:

> **“I built a weather-resilience analytics pipeline that establishes expected CitiBike demand, measures how weather shifts that expectation, identifies behavioural thresholds and unusual demand, and is designed as a repeatable Snowflake/dbt/Power BI workflow that can update as new data arrives.”**

That's the idea I'm sticking to.

---

## 18. What I do next

I'm deliberately **not** starting with the fancy stuff.

### Phase 1 — Understand the actual data

I need to determine:

* exact CitiBike schema
* exact weather schema
* date ranges
* time granularity
* missing data
* duplicate records
* available weather variables
* available trip variables
* whether the two datasets can be reliably aligned

The case study gives me the two source locations, but it doesn't give me the detailed schema in the brief itself.

### Phase 2 — Design the data model

I'll decide the correct grain and dbt layers.

### Phase 3 — Build the ELT pipeline

Snowflake → dbt → tests.

### Phase 4 — Explore the data

I'll find out what relationships actually exist rather than deciding the answer beforehand.

### Phase 5 — Build the resilience analysis

Expected demand → weather impact → thresholds → anomalies.

### Phase 6 — Decide whether ML adds genuine value

Only if the data and analysis justify it.

### Phase 7 — Build Power BI

Turn the findings into a coherent story.

### Phase 8 — Productionise

Think through refresh, testing, monitoring, failures and maintainability.

### Phase 9 — Presentation

Tell the story as a consultant:

**Problem → Question → Architecture → Analysis → Insight → Production → Business implication → Limitations → Next steps**

---

## The thing I want to remember throughout this project

The project is not simply:

> **“weather vs CitiBike.”**

That's the starting problem.

My solution is a **continuously maintainable weather-demand intelligence pipeline.**

And the interesting analytical idea inside it is:

> **Normal demand → weather-adjusted demand → behavioural thresholds → unexpected behaviour → optional prediction.**

Everything I build from here should serve that story.
