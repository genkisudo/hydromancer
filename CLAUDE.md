# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A collection of SQL, Python snippets, and documentation for querying the **Hydromancer Reservoir** — a public Hyperliquid on-chain dataset stored in S3 as Parquet files.

- Source bucket: `s3://hydromancer-reservoir` (region `ap-northeast-1`, **requester pays**)
- AWS account: `400694392038` (IAM user `s3-admin-user`, creds configured via `~/.aws/credentials`)
- DuckDB CLI: v1.5.4 — `duckdb`; Python package: `duckdb` 1.5.2

## Critical: requester-pays + credentials

`fills.sql` and `fills_db.py` are outdated — they use `SET s3_region` only and will 403. Every query against this bucket requires **both** of the following:

```sql
CREATE SECRET hydro (
    TYPE s3,
    PROVIDER credential_chain,
    REGION 'ap-northeast-1'
);
SET s3_requester_pays = true;
```

`REQUESTER_PAYS` is not a valid `CREATE SECRET` parameter in DuckDB 1.5 — it must be a separate `SET` statement. See `GUIDE.md` for verified working examples.

## Running queries

**DuckDB CLI:**
```bash
duckdb                          # interactive REPL
duckdb < fills.sql              # run a SQL file (will fail without requester-pays fix above)
```

**Python:**
```bash
python3 fills_db.py             # will fail without requester-pays fix; see GUIDE.md
```

## File map

| File | Purpose |
|---|---|
| `GUIDE.md` | Verified step-by-step guide — start here |
| `docs.md` | Full dataset docs: schemas, S3 paths, examples for all 4 datasets |
| `aws.md` | AWS env constants, IAM policy, `aws s3 sync` command for local mirroring |
| `iam_policy.md` | IAM policy deep-dive and troubleshooting |
| `fills.sql` | SQL query examples (requester-pays fix needed) |
| `fills_db.py` | Python query example (requester-pays fix needed) |
| `dbt/` | dbt project — trader-behavior analytics for xyz. See `dbt/README.md` |

## Dataset paths (bucket `s3://hydromancer-reservoir`)

```
global/fills/raw/date=YYYY-MM-DD/fills.parquet
by_dex/{dex}/fills/perp/all/date=YYYY-MM-DD/fills.parquet
by_dex/{dex}/fills/perp/liquidations/date=YYYY-MM-DD/fills.parquet
by_dex/{dex}/candles/1s/date=YYYY-MM-DD/candles.parquet
global/snapshots/perp/all/date=YYYY-MM-DD/*.parquet
by_dex/{dex}/orderbook/1m/perps/date=YYYY-MM-DD/{coin}.parquet
```

Dexes: `hyperliquid`, `xyz`, `cash`, `hyna`, `flx`, `km`, `vntl`. Wildcards work across date and dex segments. Files only exist for dates with data.

## Analytics stack: dbt → DuckDB → Rill

The `dbt/` project turns raw S3 fills into trader-behavior marts (xyz dex, rolling
30 days). Full guide in `dbt/README.md`; the short version:

**dbt ↔ DuckDB** — adapter is `dbt-duckdb`. `dbt/profiles.yml` points at a local
file `xyz_analytics.duckdb` and carries the S3 access config as connection
`settings` (`s3_region`, `s3_requester_pays: true`, `TimeZone: UTC`). The S3
secret is created once per run via an `on-run-start` hook in `dbt_project.yml`
(`CREATE OR REPLACE PERSISTENT SECRET ... PROVIDER credential_chain`). Only the
staging model (`stg_xyz_fills`, incremental) reads S3; everything downstream
reads the local DuckDB tables. Run with `dbt run --profiles-dir .`.

**DuckDB ↔ Rill** — Rill (v0.87.4) is the dashboard/viz layer. The Rill project
lives at `xyz/` and connects to `dbt/xyz_analytics.duckdb` via
`xyz/connectors/duckdb.yaml`. Start with `rill start` from the `xyz/` directory
(serves on http://localhost:9009). Because DuckDB allows only one writer, stop
Rill before running `dbt run`, then restart it — they cannot run simultaneously.

Two non-obvious data facts the marts depend on (also in `dbt/README.md`):
- Fills grain is `(trade_id, trader)` — every trade is recorded from **both**
  counterparties, so `trade_id` is not unique and `SUM(volume_usd)` over all rows
  double-counts market volume by 2×. Per-trader aggregates are unaffected.
- Timestamps are UTC; pin the DuckDB session to `TimeZone: UTC` or day/week
  buckets drift by the local offset (~7% of rows land on the wrong day).

## Cost awareness

Requester pays means account `400694392038` is billed for all S3 GET requests (~$0.0004/1000) and egress from Tokyo (~$0.09/GB). Broad `date=*` wildcards touch many files. To avoid per-query costs, mirror partitions locally with:

```bash
aws s3 sync s3://hydromancer-reservoir/by_dex/xyz/ s3://my-hyperliquid-xyz-reservoir/ \
  --request-payer requester --region ap-northeast-1 --copy-props none
```
