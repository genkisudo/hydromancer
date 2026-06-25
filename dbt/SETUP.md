# xyz Analytics — Setup & Run Guide

## Prerequisites

```bash
pip install dbt-duckdb          # dbt adapter for DuckDB
```

Rill (v0.87.4) is installed at `/usr/local/bin/rill`. The Rill project lives at
`../xyz/` and is already configured to read `xyz_analytics.duckdb`.

Confirm AWS creds work (needed for S3 access):
```bash
aws sts get-caller-identity
```

---

## 1. Configure dbt profile

Two options:

**Option A — copy to the global dbt profiles location:**
```bash
cp profiles.yml ~/.dbt/profiles.yml
```

**Option B — use the local file per run:**
```bash
dbt run --profiles-dir .
```

---

## 2. First run (loads last 30 days from S3)

```bash
cd /path/to/hydromancer_duckdb/dbt

# Validate connection
dbt debug --profiles-dir .

# Run all models — fetches ~30 days of xyz fills from S3, writes to xyz_analytics.duckdb
dbt run --profiles-dir .

# Optional: run data tests
dbt test --profiles-dir .
```

The first run queries S3 (requester-pays, ~$0.01–0.05 for 30 days of xyz data).
Subsequent `dbt run` calls only fetch new rows since the last timestamp.

---

## 3. Daily refresh (cron or manual)

```bash
dbt run --profiles-dir .
```

Add to crontab for daily 3am run:
```
0 3 * * * cd /Users/genkisudo/Documents/hydromancer_duckdb/dbt && dbt run --profiles-dir . >> /tmp/dbt_xyz.log 2>&1
```

---

## 4. View in Rill

After `dbt run` completes, start Rill to explore the marts:

```bash
cd /Users/genkisudo/Documents/hydromancer_duckdb/xyz
rill start
```

Open http://localhost:9009. Tables appear under DATA EXPLORER → duckdb.

> **Important:** DuckDB allows only one writer. Stop Rill before running `dbt run`,
> then restart it after. They cannot hold the file simultaneously.

---

## Model DAG

```
S3 (hydromancer-reservoir)
  ├── stg_xyz_fills          (incremental — queries S3 once)
  │     ├── int_trader_daily       (table — all trader/day stats)
  │     │     ├── mart_trader_summary     (power users, percentiles)
  │     │     ├── mart_cohort_retention   (retention curves)
  │     │     └── mart_pnl_distribution   (winner/loser buckets)
  │     └── int_trader_cohorts     (table — first trade per wallet)
  │           ├── mart_trader_summary
  │           └── mart_cohort_retention
  └── stg_xyz_positions      (table — latest perp snapshot/day, last 30d)
        └── mart_open_interest      (open interest & leverage per market/day)
```

---

## Roadmap: conventions to adopt from the Airbnb reference project

The Airbnb course project (`../../northquant_dbt/course/airbnb`) showcases several dbt
features worth borrowing. We **keep our current `staging` / `intermediate` / `marts`
layering and `stg_` / `int_` / `mart_` naming** (the current dbt-Labs standard — Airbnb's
older `src_`/`dim_`/`fct_` style is a lateral move and our data isn't strongly dimensional).
What's worth adopting are three *features*:

### A. Source freshness

**What:** add `loaded_at_field` + `freshness` thresholds to the sources in
`models/staging/_stg_sources.yml`, so `dbt source freshness` can flag stale or missing
S3 partitions before dashboards go stale.

```yaml
- name: xyz_perp_fills
  config:
    loaded_at_field: "timestamp"
    freshness:
      warn_after:  {count: 12, period: hour}
      error_after: {count: 36, period: hour}
```

**Caveat:** with the dbt-duckdb `external_location` pattern, `dbt source freshness` runs
`SELECT max(timestamp) FROM read_parquet(...)`, which scans S3 (requester-pays). Bound the
cost by running freshness only in the daily job (not every build), and note that
`xyz_perp_snapshots` has no per-row timestamp — its freshness would key off the partition
`date` instead.

### B. `{% docs %}` doc blocks

**What:** create `models/docs.md` with reusable doc blocks for the data caveats that are
currently duplicated across SQL comments and multiple `_*.yml` files, then reference them
with `description: '{{ doc("...") }}'`. Single source of truth, and they render in `dbt docs`.

Candidate blocks: `fills__grain` (the `(trade_id, trader)` maker/taker double-count),
`fills__volume_usd_doublecount` (SUM over all rows = 2× market volume), `trade_date__utc`
(UTC day-bucketing rationale), `retention_rate` (retained ÷ *fixed* cohort_size, ∈ [0,1]),
`positions__latest_per_day` (latest-snapshot dedupe), `oi__notional` (gross OI = `SUM(|notional|)`).

```jinja
{% docs fills__grain %}
Grain is (trade_id, trader). Every Hyperliquid trade is recorded from both
counterparties, so trade_id appears twice (maker + taker); trade_id alone is not unique.
{% enddocs %}
```

### C. Unit tests

**What:** add `unit_tests.yml` with mocked-row tests for logic that schema tests cannot
catch. Schema tests passed while `mart_cohort_retention` was returning an always-1.0 result —
a unit test with fixed fixtures would have caught it.

Priority cases:
1. **`mart_cohort_retention`** — given a small cohort active across weeks, assert
   `retention_rate` *declines* (e.g. week 0 = 1.0, week 1 = 0.5). Guards the exact bug fixed
   in this project's history.
2. **`stg_xyz_positions`** — given two snapshot files on the same day (different
   `snapshot_ms`) for one position, assert only the latest row survives.
3. *(optional)* **`int_trader_daily`** — given fills with `crossed` true/false, assert the
   `taker_fills` / `maker_fills` split.

Unit tests are supported on our dbt (1.10) and run under `dbt build` / `dbt test` with no
warehouse data — cheap and Rill-lock-free.

