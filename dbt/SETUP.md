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
  └── stg_xyz_fills          (incremental — queries S3 once)
        ├── int_trader_daily       (table — all trader/day stats)
        │     ├── mart_trader_summary     (power users, percentiles)
        │     ├── mart_cohort_retention   (retention curves)
        │     └── mart_pnl_distribution   (winner/loser buckets)
        └── int_trader_cohorts     (table — first trade per wallet)
              ├── mart_trader_summary
              └── mart_cohort_retention
```
