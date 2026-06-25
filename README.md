# xyz Trader Analytics — dbt + DuckDB + Rill

Historical trader-behavior analytics for the **trade.xyz** HIP-3 dex, built from
the Hydromancer Reservoir S3 dataset. dbt transforms 30 days of raw fills into
per-trader marts stored in a local DuckDB file, visualised in Rill.

```
S3 (hydromancer-reservoir)  →  dbt (DuckDB)  →  xyz_analytics.duckdb  →  Rill
        raw Parquet              transforms        local tables           dashboards
```

## Pipeline at a glance

| Model | Layer | What it gives you |
|---|---|---|
| `stg_xyz_fills` | staging | Cleaned fills, last 30 days. **Only model that reads S3.** |
| `int_trader_daily` | intermediate | Per trader / day / coin: volume, PnL, fees, liquidations, maker/taker |
| `int_trader_cohorts` | intermediate | Each wallet's first trade date + cohort week |
| `mart_trader_summary` | mart | Lifetime stats per trader + volume percentile (power users) |
| `mart_cohort_retention` | mart | Week-over-week retention curves |
| `mart_pnl_distribution` | mart | Winner/loser breakdown by PnL bucket |

## Running the pipeline

```bash
cd dbt
dbt run  --profiles-dir .          # build/refresh all models (S3 hit only in staging)
dbt test --profiles-dir .          # validate grain + not-null constraints
dbt run  --profiles-dir . --full-refresh   # rebuild from scratch (re-reads 30d from S3)
```

Daily refresh via cron:
```
0 3 * * * cd /Users/genkisudo/Documents/hydromancer_duckdb/dbt && dbt run --profiles-dir . >> /tmp/dbt_xyz.log 2>&1
```

## Using Rill

Rill (v0.87.4) is the dashboard layer. The project lives at `xyz/` inside this repo.

```bash
# Start the dev server (http://localhost:9009)
cd /Users/genkisudo/Documents/hydromancer_duckdb/xyz
rill start
```

The Rill project connects to `dbt/xyz_analytics.duckdb` read-only via
`xyz/connectors/duckdb.yaml`. Because DuckDB only allows one writer at a time,
stop Rill before running dbt, then restart it after:

```bash
# 1. Stop Rill (Ctrl-C)
# 2. Refresh data
cd /Users/genkisudo/Documents/hydromancer_duckdb/dbt
dbt run --profiles-dir .
# 3. Restart Rill
cd ../xyz && rill start
```

Tables available in Rill's DATA EXPLORER:
- `mart_trader_summary` — lifetime stats, volume percentiles, power users
- `mart_cohort_retention` — week-over-week retention curves
- `mart_pnl_distribution` — winner/loser breakdown by PnL bucket
- `int_trader_daily` — daily per-trader per-coin drill-through
- `int_trader_cohorts` — first trade date per wallet

---

## Important data facts (read before writing queries)

- **Grain is `(trade_id, trader)`, not `trade_id`.** Every trade is recorded from
  both counterparties, so each `trade_id` appears **twice** (maker + taker).
- **Don't compute market-wide volume as `SUM(volume_usd)` across all fills — it
  double-counts by 2×.** Either divide by 2, or filter to one side
  (`WHERE crossed = true` for taker-side only). Per-trader marts are already
  correct because each row is attributed to one trader.
- **All dates are UTC.** The pipeline pins the DuckDB session to UTC so
  `trade_date` and day/week buckets match the S3 UTC date partitions.
- **Window is rolling.** Initial load = last 30 days. Incremental runs append new
  days without deleting old ones, so history grows over time.

