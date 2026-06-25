{{ config(materialized='table') }}

/*
  GRAIN: one row per (snapshot_date, trader, market) — each trader's open
  position in each market, as of the LATEST snapshot of that day.

  Snapshots are point-in-time state (not flow), so there is no maker/taker
  double-count. A day can have several snapshot files (block_timestamp in the
  filename); we keep only the most recent per day via the row_number filter.

  Last 30 days only, to match stg_xyz_fills. Materialized as a table (full
  rebuild) rather than incremental: the data is small and the latest-per-day
  dedupe is awkward to express incrementally.
*/
WITH raw AS (
    SELECT
        "user"                              AS trader,
        market,
        CAST(size AS DOUBLE)                AS size,
        CAST(notional AS DOUBLE)            AS notional,
        CAST(entry_price AS DOUBLE)         AS entry_price,
        CAST(liquidation_price AS DOUBLE)   AS liquidation_price,
        leverage_type,
        leverage,
        CAST(funding_pnl AS DOUBLE)         AS funding_pnl,
        CAST(account_value AS DOUBLE)       AS account_value,
        account_mode,
        CAST("date" AS DATE)                AS snapshot_date,
        -- block_timestamp (ms) from the filename, e.g. 926030000_1773706027926.parquet
        TRY_CAST(regexp_extract(filename, '_([0-9]+)\.parquet', 1) AS BIGINT) AS snapshot_ms
    FROM {{ source('hydromancer', 'xyz_perp_snapshots') }}
    WHERE CAST("date" AS DATE) >= CURRENT_DATE - INTERVAL '30 days'
),
ranked AS (
    -- rank each position's rows so we can keep the latest snapshot of the day
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY snapshot_date, trader, market
            ORDER BY snapshot_ms DESC
        ) AS rn
    FROM raw
)

SELECT
    trader,
    market,
    size,
    notional,
    entry_price,
    liquidation_price,
    leverage_type,
    leverage,
    funding_pnl,
    account_value,
    account_mode,
    snapshot_date
FROM ranked
WHERE rn = 1
